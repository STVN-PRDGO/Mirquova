//! Consent-gated screen share over mutually authenticated TLS 1.3.
//! Frames are JPEG stills, with optional 16-bit system-audio chunks.
//! This is Mirquova-to-Mirquova, not Chromecast.
use crate::{discovery::is_lan_address, pairing::PairingIdentity};
use rustls::{pki_types::UnixTime, server::danger::ClientCertVerifier};
use serde::{Deserialize, Serialize};
use std::{
    collections::VecDeque,
    io::{self, Read, Write},
    net::{Ipv4Addr, SocketAddr, SocketAddrV4, TcpListener, TcpStream},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, SyncSender},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

const PROTOCOL_VERSION: u16 = 1;
const MAX_FRAME_BYTES: usize = 16 * 1024;
const MAX_JPEG_BYTES: usize = 512 * 1024;
const MAX_AUDIO_BYTES: usize = 64 * 1024;
const AUDIO_MAGIC: &[u8] = b"MQA2";
const AUDIO_HEADER: usize = 18;
/// 10 ms of 48 kHz stereo 16-bit PCM.
const AUDIO_10MS: usize = 48_000 / 100 * 2 * 2;
const IO_TIMEOUT: Duration = Duration::from_secs(15);
const FRAME_IDLE_TIMEOUT: Duration = Duration::from_secs(5);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
const ACCEPT_POLL: Duration = Duration::from_millis(100);
const APPROVAL_TIMEOUT: Duration = Duration::from_secs(60);
const DECISION_READ_TIMEOUT: Duration = Duration::from_secs(75);
const MAX_DIMENSION: u32 = 1920;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CastStartError {
    InvalidInput,
    Network,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CastStatus {
    #[default]
    Idle,
    Listening,
    Connecting,
    AwaitingApproval,
    Casting,
    Rejected,
    Stopped,
    Error,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CastRole {
    Send,
    Receive,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize)]
pub struct CastSnapshot {
    pub status: CastStatus,
    pub role: Option<CastRole>,
    pub endpoint: Option<String>,
    pub error_code: Option<&'static str>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub frames: u64,
    #[serde(default)]
    pub audio: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub peer_index: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub peer_ipv4: Option<String>,
}

#[derive(Clone)]
struct SharedState(Arc<Mutex<CastSnapshot>>);

impl SharedState {
    fn new(status: CastStatus, role: CastRole) -> Self {
        Self(Arc::new(Mutex::new(CastSnapshot {
            status,
            role: Some(role),
            ..CastSnapshot::default()
        })))
    }

    fn update(&self, update: impl FnOnce(&mut CastSnapshot)) {
        update(&mut self.0.lock().unwrap_or_else(|error| error.into_inner()));
    }

    fn snapshot(&self) -> CastSnapshot {
        self.0
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    fn fail(&self, code: &'static str) {
        self.update(|value| {
            value.status = CastStatus::Error;
            value.error_code = Some(code);
        });
    }
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Offer {
    version: u16,
    purpose: String,
    mode: String,
    width: u32,
    height: u32,
    #[serde(default)]
    audio: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AudioChunk {
    pub sample_rate: u32,
    pub channels: u16,
    pub time_us: u64,
    pub pcm: Vec<u8>,
}

/// Playback buffer for mirrored system audio. It waits until about 40 ms has
/// arrived, plays silence and gathers again after a stall, and drops the
/// oldest sound when more than 200 ms is waiting.
#[derive(Debug)]
struct AudioJitter {
    bytes: VecDeque<u8>,
    rate: u32,
    channels: u16,
    frame: usize,
    per_ms: usize,
    waiting: bool,
}

impl AudioJitter {
    fn new(rate: u32, channels: u16) -> Self {
        let channels = if channels == 0 { 2 } else { channels };
        let frame = 2 * usize::from(channels);
        Self {
            bytes: VecDeque::new(),
            rate,
            channels,
            frame,
            per_ms: frame * rate as usize / 1000,
            waiting: true,
        }
    }

    fn push_format(&mut self, rate: u32, channels: u16, pcm: &[u8]) {
        if self.rate != rate || self.channels != channels {
            *self = Self::new(rate, channels);
        }
        self.push(pcm);
    }

    fn push(&mut self, data: &[u8]) {
        let aligned = data.len() - data.len() % self.frame.max(1);
        self.bytes.extend(&data[..aligned]);
        let most = self.per_ms.saturating_mul(200);
        let keep = self.per_ms.saturating_mul(60);
        if self.per_ms > 0 && self.bytes.len() > most {
            let drop = self.bytes.len().saturating_sub(keep) / self.frame * self.frame;
            self.bytes.drain(..drop);
        }
    }

    fn fill(&mut self, out: &mut [u8]) {
        if self.waiting && self.bytes.len() >= self.per_ms.saturating_mul(40) {
            self.waiting = false;
        }
        let mut filled = 0;
        if !self.waiting {
            filled = out.len().min(self.bytes.len()) / self.frame.max(1) * self.frame;
            if filled > 0 {
                for (index, byte) in self.bytes.drain(..filled).enumerate() {
                    out[index] = byte;
                }
            }
            if filled < out.len() {
                self.waiting = true;
            }
        }
        out[filled..].fill(0);
    }
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Decision {
    version: u16,
    purpose: String,
    accept: bool,
}

pub struct ReceiveSession {
    endpoint: SocketAddrV4,
    state: SharedState,
    latest: Arc<Mutex<Option<Vec<u8>>>>,
    audio: Arc<Mutex<VecDeque<AudioChunk>>>,
    playback: Arc<Mutex<AudioJitter>>,
    playback_muted: Arc<AtomicBool>,
    cancel: Arc<AtomicBool>,
    decision: SyncSender<bool>,
    worker: Option<JoinHandle<()>>,
}

impl ReceiveSession {
    pub fn start(
        bind_ipv4: Ipv4Addr,
        port: u16,
        identity: PairingIdentity,
        trusted_peer_cas: &[impl AsRef<[u8]>],
    ) -> Result<Self, CastStartError> {
        if !(bind_ipv4.is_unspecified() || is_lan_address(bind_ipv4)) || trusted_peer_cas.is_empty()
        {
            return Err(CastStartError::InvalidInput);
        }
        let config = identity
            .mutual_server_config_for_trusted_peers(trusted_peer_cas)
            .map_err(|_| CastStartError::InvalidInput)?;
        let verifiers = trusted_peer_cas
            .iter()
            .map(|ca| PairingIdentity::client_verifier_for_peer(ca.as_ref()))
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| CastStartError::InvalidInput)?;
        let listener = TcpListener::bind(SocketAddrV4::new(bind_ipv4, port))
            .map_err(|_| CastStartError::Network)?;
        listener
            .set_nonblocking(true)
            .map_err(|_| CastStartError::Network)?;
        let local = listener.local_addr().map_err(|_| CastStartError::Network)?;
        let endpoint = SocketAddrV4::new(bind_ipv4, local.port());
        let state = SharedState::new(CastStatus::Listening, CastRole::Receive);
        state.update(|value| value.endpoint = Some(endpoint.to_string()));
        let cancel = Arc::new(AtomicBool::new(false));
        let (decision, decision_rx) = mpsc::sync_channel(1);
        let latest = Arc::new(Mutex::new(None));
        let audio = Arc::new(Mutex::new(VecDeque::new()));
        let playback = Arc::new(Mutex::new(AudioJitter::new(48_000, 2)));
        let playback_muted = Arc::new(AtomicBool::new(false));
        let worker_state = state.clone();
        let worker_cancel = Arc::clone(&cancel);
        let worker_latest = Arc::clone(&latest);
        let worker_audio = Arc::clone(&audio);
        let worker_playback = Arc::clone(&playback);
        let worker = thread::Builder::new()
            .name("mirquova-cast-receive".into())
            .spawn(move || {
                receive_worker(
                    listener,
                    config,
                    verifiers,
                    worker_state,
                    ReceivePipes {
                        latest: worker_latest,
                        audio: worker_audio,
                        playback: worker_playback,
                    },
                    worker_cancel,
                    decision_rx,
                );
            })
            .map_err(|_| CastStartError::Network)?;
        Ok(Self {
            endpoint,
            state,
            latest,
            audio,
            playback,
            playback_muted,
            cancel,
            decision,
            worker: Some(worker),
        })
    }

    pub fn endpoint(&self) -> SocketAddrV4 {
        self.endpoint
    }

    pub fn snapshot(&self) -> CastSnapshot {
        self.state.snapshot()
    }

    pub fn latest_frame(&self) -> Option<Vec<u8>> {
        self.latest
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn take_audio(&self) -> Option<AudioChunk> {
        self.audio
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .pop_front()
    }

    pub fn set_playback_muted(&self, muted: bool) {
        self.playback_muted.store(muted, Ordering::Release);
    }

    pub fn render_audio(&self, out: &mut [u8]) {
        self.playback
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .fill(out);
        if self.playback_muted.load(Ordering::Acquire) {
            out.fill(0);
        }
    }

    pub fn approve(&self) -> bool {
        self.state.snapshot().status == CastStatus::AwaitingApproval
            && self.decision.try_send(true).is_ok()
    }

    pub fn reject(&self) -> bool {
        self.state.snapshot().status == CastStatus::AwaitingApproval
            && self.decision.try_send(false).is_ok()
    }

    pub fn stop(&mut self) {
        self.cancel.store(true, Ordering::Release);
        let _ = self.decision.try_send(false);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
        let current = self.state.snapshot();
        if !matches!(current.status, CastStatus::Rejected | CastStatus::Error) {
            self.state
                .update(|value| value.status = CastStatus::Stopped);
        }
    }
}

impl Drop for ReceiveSession {
    fn drop(&mut self) {
        self.stop();
    }
}

pub struct SendSession {
    state: SharedState,
    cancel: Arc<AtomicBool>,
    pending: Arc<Mutex<Option<Vec<u8>>>>,
    pending_audio: Arc<Mutex<VecDeque<AudioChunk>>>,
    audio_tail: Mutex<Vec<u8>>,
    worker: Option<JoinHandle<()>>,
}

impl SendSession {
    pub fn start(
        peer_ipv4: Ipv4Addr,
        port: u16,
        identity: PairingIdentity,
        peer_ca: &[u8],
        width: u32,
        height: u32,
        audio: bool,
    ) -> Result<Self, CastStartError> {
        if !is_lan_address(peer_ipv4)
            || port == 0
            || !valid_dimension(width)
            || !valid_dimension(height)
        {
            return Err(CastStartError::InvalidInput);
        }
        let config = identity
            .mutual_client_config(peer_ca)
            .map_err(|_| CastStartError::InvalidInput)?;
        let state = SharedState::new(CastStatus::Connecting, CastRole::Send);
        state.update(|value| {
            value.endpoint = Some(SocketAddrV4::new(peer_ipv4, port).to_string());
            value.width = Some(width);
            value.height = Some(height);
            value.audio = audio;
        });
        let cancel = Arc::new(AtomicBool::new(false));
        let pending = Arc::new(Mutex::new(None));
        let pending_audio = Arc::new(Mutex::new(VecDeque::new()));
        let worker_state = state.clone();
        let worker_cancel = Arc::clone(&cancel);
        let worker_pending = Arc::clone(&pending);
        let worker_audio = Arc::clone(&pending_audio);
        let worker = thread::Builder::new()
            .name("mirquova-cast-send".into())
            .spawn(move || {
                send_worker(
                    SocketAddrV4::new(peer_ipv4, port),
                    config,
                    Offer {
                        version: PROTOCOL_VERSION,
                        purpose: "cast-offer".to_owned(),
                        mode: "mirror".to_owned(),
                        width,
                        height,
                        audio,
                    },
                    SendPipes {
                        pending: worker_pending,
                        audio: worker_audio,
                    },
                    worker_state,
                    worker_cancel,
                );
            })
            .map_err(|_| CastStartError::Network)?;
        Ok(Self {
            state,
            cancel,
            pending,
            pending_audio,
            audio_tail: Mutex::new(Vec::new()),
            worker: Some(worker),
        })
    }

    pub fn snapshot(&self) -> CastSnapshot {
        self.state.snapshot()
    }

    pub fn push_frame(&self, jpeg: &[u8]) -> bool {
        if !is_jpeg(jpeg) || jpeg.len() > MAX_JPEG_BYTES {
            return false;
        }
        if self.state.snapshot().status != CastStatus::Casting {
            return false;
        }
        *self
            .pending
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = Some(jpeg.to_vec());
        true
    }

    pub fn push_audio(&self, pcm: &[u8], sample_rate: u32, channels: u16) -> bool {
        if !valid_pcm(sample_rate, channels, pcm) {
            return false;
        }
        if self.state.snapshot().status != CastStatus::Casting {
            return false;
        }
        let mut tail = self
            .audio_tail
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let mut queue = self
            .pending_audio
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if sample_rate == 48_000 && channels == 2 && (pcm.len() >= AUDIO_10MS || !tail.is_empty()) {
            tail.extend_from_slice(pcm);
            while tail.len() >= AUDIO_10MS {
                let packet: Vec<u8> = tail.drain(..AUDIO_10MS).collect();
                queue_audio(&mut queue, sample_rate, channels, packet);
            }
        } else {
            queue_audio(&mut queue, sample_rate, channels, pcm.to_vec());
        }
        trim_audio_queue(&mut queue);
        true
    }

    pub fn stop(&mut self) {
        self.cancel.store(true, Ordering::Release);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
        let current = self.state.snapshot();
        if !matches!(current.status, CastStatus::Rejected | CastStatus::Error) {
            self.state
                .update(|value| value.status = CastStatus::Stopped);
        }
    }
}

impl Drop for SendSession {
    fn drop(&mut self) {
        self.stop();
    }
}

struct ReceivePipes {
    latest: Arc<Mutex<Option<Vec<u8>>>>,
    audio: Arc<Mutex<VecDeque<AudioChunk>>>,
    playback: Arc<Mutex<AudioJitter>>,
}

struct SendPipes {
    pending: Arc<Mutex<Option<Vec<u8>>>>,
    audio: Arc<Mutex<VecDeque<AudioChunk>>>,
}

fn receive_worker(
    listener: TcpListener,
    config: std::sync::Arc<rustls::ServerConfig>,
    verifiers: Vec<Arc<dyn ClientCertVerifier>>,
    state: SharedState,
    pipes: ReceivePipes,
    cancel: Arc<AtomicBool>,
    decision_rx: Receiver<bool>,
) {
    let (socket, peer) = loop {
        if cancel.load(Ordering::Acquire) {
            return;
        }
        match listener.accept() {
            Ok((socket, SocketAddr::V4(peer)))
                if is_lan_address(*peer.ip()) || peer.ip().is_loopback() =>
            {
                break (socket, *peer.ip());
            }
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(ACCEPT_POLL);
            }
            Err(_) => {
                state.fail("network");
                return;
            }
        }
    };
    if configure_socket(&socket).is_err() {
        state.fail("network");
        return;
    }
    let mut stream = match server_stream(socket, config) {
        Ok(stream) => stream,
        Err(()) => {
            state.fail("tls_failed");
            return;
        }
    };
    let offer = match read_json::<Offer>(&mut stream) {
        Ok(offer) => offer,
        Err(_) => {
            state.fail("protocol");
            return;
        }
    };
    if let Err(code) = validate_offer(&offer) {
        state.fail(code);
        return;
    }
    let sender = stream
        .conn
        .peer_certificates()
        .and_then(|chain| chain.first())
        .and_then(|leaf| {
            verifiers.iter().position(|verifier| {
                verifier
                    .verify_client_cert(leaf, &[], UnixTime::now())
                    .is_ok()
            })
        });
    state.update(|value| {
        value.peer_index = sender;
        value.peer_ipv4 = is_lan_address(peer).then(|| peer.to_string());
        value.status = CastStatus::AwaitingApproval;
        value.width = Some(offer.width);
        value.height = Some(offer.height);
        value.audio = offer.audio;
    });
    let accept = wait_for_decision(&decision_rx, &cancel);
    if cancel.load(Ordering::Acquire) {
        let _ = write_json(&mut stream, &decision(false));
        return;
    }
    match accept {
        Some(true) => {}
        Some(false) => {
            let _ = write_json(&mut stream, &decision(false));
            state.update(|value| value.status = CastStatus::Rejected);
            return;
        }
        None => {
            let _ = write_json(&mut stream, &decision(false));
            state.update(|value| {
                value.status = CastStatus::Rejected;
                value.error_code = Some("no_answer");
            });
            return;
        }
    }
    if write_json(&mut stream, &decision(true)).is_err() {
        state.fail("network");
        return;
    }
    if stream
        .sock
        .set_read_timeout(Some(FRAME_IDLE_TIMEOUT))
        .is_err()
    {
        state.fail("network");
        return;
    }
    state.update(|value| value.status = CastStatus::Casting);
    loop {
        if cancel.load(Ordering::Acquire) {
            return;
        }
        match read_packet(&mut stream) {
            Ok(Packet::Frame(frame)) => {
                {
                    *pipes
                        .latest
                        .lock()
                        .unwrap_or_else(|error| error.into_inner()) = Some(frame);
                }
                state.update(|value| value.frames = value.frames.saturating_add(1));
            }
            Ok(Packet::Audio(chunk)) => {
                pipes
                    .playback
                    .lock()
                    .unwrap_or_else(|error| error.into_inner())
                    .push_format(chunk.sample_rate, chunk.channels, &chunk.pcm);
                let mut queue = pipes
                    .audio
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                trim_audio_queue(&mut queue);
                queue.push_back(chunk);
                trim_audio_queue(&mut queue);
            }
            Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => {
                state.update(|value| {
                    if value.status == CastStatus::Casting {
                        value.status = CastStatus::Stopped;
                    }
                });
                return;
            }
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::TimedOut | io::ErrorKind::WouldBlock
                ) =>
            {
                if cancel.load(Ordering::Acquire) {
                    return;
                }
                state.fail("network");
                return;
            }
            Err(_) => {
                if cancel.load(Ordering::Acquire) {
                    return;
                }
                state.fail("network");
                return;
            }
        }
    }
}

fn send_worker(
    endpoint: SocketAddrV4,
    config: std::sync::Arc<rustls::ClientConfig>,
    offer: Offer,
    pipes: SendPipes,
    state: SharedState,
    cancel: Arc<AtomicBool>,
) {
    let socket = match TcpStream::connect_timeout(&endpoint.into(), CONNECT_TIMEOUT) {
        Ok(socket) => socket,
        Err(_) => {
            state.fail("network");
            return;
        }
    };
    if configure_socket(&socket).is_err() {
        state.fail("network");
        return;
    }
    let mut stream = match client_stream(socket, config) {
        Ok(stream) => stream,
        Err(()) => {
            state.fail("tls_failed");
            return;
        }
    };
    if write_json(&mut stream, &offer).is_err() {
        state.fail("network");
        return;
    }
    state.update(|value| value.status = CastStatus::AwaitingApproval);
    if stream
        .sock
        .set_read_timeout(Some(DECISION_READ_TIMEOUT))
        .is_err()
    {
        state.fail("network");
        return;
    }
    let decision = match read_json::<Decision>(&mut stream) {
        Ok(decision) => decision,
        Err(error) => {
            if cancel.load(Ordering::Acquire) {
                return;
            }
            state.fail(match error.kind() {
                io::ErrorKind::InvalidData => "protocol",
                io::ErrorKind::TimedOut | io::ErrorKind::WouldBlock => "no_answer",
                _ => "network",
            });
            return;
        }
    };
    if stream.sock.set_write_timeout(Some(IO_TIMEOUT)).is_err() {
        state.fail("network");
        return;
    }
    if decision.version != PROTOCOL_VERSION || decision.purpose != "cast-decision" {
        state.fail("protocol");
        return;
    }
    if !decision.accept {
        state.update(|value| value.status = CastStatus::Rejected);
        return;
    }
    if cancel.load(Ordering::Acquire) {
        return;
    }
    state.update(|value| value.status = CastStatus::Casting);
    loop {
        if cancel.load(Ordering::Acquire) {
            return;
        }
        let frame = pipes
            .pending
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
        let chunk = pipes
            .audio
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .pop_front();
        if frame.is_none() && chunk.is_none() {
            thread::sleep(ACCEPT_POLL);
            continue;
        }
        if let Some(frame) = frame {
            if write_jpeg(&mut stream, &frame).is_err() {
                if cancel.load(Ordering::Acquire) {
                    return;
                }
                state.fail("network");
                return;
            }
            state.update(|value| value.frames = value.frames.saturating_add(1));
        }
        if let Some(chunk) = chunk
            && write_audio(&mut stream, &chunk).is_err()
        {
            if cancel.load(Ordering::Acquire) {
                return;
            }
            state.fail("network");
            return;
        }
    }
}

fn wait_for_decision(decision_rx: &Receiver<bool>, cancel: &AtomicBool) -> Option<bool> {
    let deadline = Instant::now() + APPROVAL_TIMEOUT;
    loop {
        if cancel.load(Ordering::Acquire) {
            return Some(false);
        }
        if Instant::now() >= deadline {
            return None;
        }
        match decision_rx.recv_timeout(ACCEPT_POLL) {
            Ok(accept) => return Some(accept),
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => return Some(false),
        }
    }
}

fn validate_offer(offer: &Offer) -> Result<(), &'static str> {
    if offer.version != PROTOCOL_VERSION || offer.purpose != "cast-offer" {
        return Err("protocol");
    }
    if offer.mode != "mirror" && offer.mode != "media" {
        return Err("protocol");
    }
    if !valid_dimension(offer.width) || !valid_dimension(offer.height) {
        return Err("protocol");
    }
    Ok(())
}

fn valid_dimension(value: u32) -> bool {
    value > 0 && value <= MAX_DIMENSION
}

pub fn is_jpeg(bytes: &[u8]) -> bool {
    bytes.len() >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff
}

fn decision(accept: bool) -> Decision {
    Decision {
        version: PROTOCOL_VERSION,
        purpose: "cast-decision".to_owned(),
        accept,
    }
}

fn configure_socket(socket: &TcpStream) -> io::Result<()> {
    socket.set_nonblocking(false)?;
    socket.set_read_timeout(Some(IO_TIMEOUT))?;
    socket.set_write_timeout(Some(IO_TIMEOUT))?;
    socket.set_nodelay(true)
}

fn server_stream(
    socket: TcpStream,
    config: std::sync::Arc<rustls::ServerConfig>,
) -> Result<rustls::StreamOwned<rustls::ServerConnection, TcpStream>, ()> {
    let connection = rustls::ServerConnection::new(config).map_err(|_| ())?;
    Ok(rustls::StreamOwned::new(connection, socket))
}

fn client_stream(
    socket: TcpStream,
    config: std::sync::Arc<rustls::ClientConfig>,
) -> Result<rustls::StreamOwned<rustls::ClientConnection, TcpStream>, ()> {
    let connection =
        rustls::ClientConnection::new(config, crate::pairing::tls_server_name()).map_err(|_| ())?;
    Ok(rustls::StreamOwned::new(connection, socket))
}

fn write_json(stream: &mut impl Write, value: &impl Serialize) -> io::Result<()> {
    let bytes = serde_json::to_vec(value).map_err(|_| invalid_data())?;
    if bytes.is_empty() || bytes.len() > MAX_FRAME_BYTES {
        return Err(invalid_data());
    }
    stream.write_all(&(bytes.len() as u32).to_be_bytes())?;
    stream.write_all(&bytes)?;
    stream.flush()
}

fn read_json<T: for<'de> Deserialize<'de>>(stream: &mut impl Read) -> io::Result<T> {
    let bytes = read_bounded(stream, MAX_FRAME_BYTES)?;
    serde_json::from_slice(&bytes).map_err(|_| invalid_data())
}

enum Packet {
    Frame(Vec<u8>),
    Audio(AudioChunk),
}

fn queue_audio(queue: &mut VecDeque<AudioChunk>, rate: u32, channels: u16, pcm: Vec<u8>) {
    let time_us = queue.back().map(|chunk| chunk.time_us).unwrap_or(0)
        + pcm_duration_us(rate, channels, pcm.len());
    queue.push_back(AudioChunk {
        sample_rate: rate,
        channels,
        time_us,
        pcm,
    });
}

fn pcm_duration_us(rate: u32, channels: u16, bytes: usize) -> u64 {
    let frame = 2 * usize::from(channels.max(1));
    if rate == 0 || frame == 0 {
        return 0;
    }
    (bytes / frame) as u64 * 1_000_000 / u64::from(rate)
}

fn trim_audio_queue(queue: &mut VecDeque<AudioChunk>) {
    let Some(last) = queue.back() else {
        return;
    };
    let frame = 2 * usize::from(last.channels.max(1));
    let per_ms = frame * last.sample_rate as usize / 1000;
    if per_ms == 0 {
        return;
    }
    let most = per_ms * 200;
    let keep = per_ms * 60;
    let mut total: usize = queue.iter().map(|chunk| chunk.pcm.len()).sum();
    if total <= most {
        return;
    }
    while total > keep {
        let Some(front) = queue.pop_front() else {
            break;
        };
        total = total.saturating_sub(front.pcm.len());
    }
}

fn valid_pcm(sample_rate: u32, channels: u16, pcm: &[u8]) -> bool {
    matches!(sample_rate, 8_000 | 16_000 | 22_050 | 44_100 | 48_000)
        && matches!(channels, 1 | 2)
        && !pcm.is_empty()
        && pcm.len() <= MAX_AUDIO_BYTES
        && pcm.len().is_multiple_of(channels as usize * 2)
}

fn write_audio(stream: &mut impl Write, chunk: &AudioChunk) -> io::Result<()> {
    if !valid_pcm(chunk.sample_rate, chunk.channels, &chunk.pcm) {
        return Err(invalid_data());
    }
    let mut payload = Vec::with_capacity(AUDIO_HEADER + chunk.pcm.len());
    payload.extend_from_slice(AUDIO_MAGIC);
    payload.extend_from_slice(&chunk.sample_rate.to_le_bytes());
    payload.extend_from_slice(&chunk.channels.to_le_bytes());
    payload.extend_from_slice(&chunk.time_us.to_le_bytes());
    payload.extend_from_slice(&chunk.pcm);
    stream.write_all(&(payload.len() as u32).to_be_bytes())?;
    stream.write_all(&payload)?;
    stream.flush()
}

fn read_packet(stream: &mut impl Read) -> io::Result<Packet> {
    let bytes = read_bounded(stream, MAX_JPEG_BYTES)?;
    if is_jpeg(&bytes) {
        return Ok(Packet::Frame(bytes));
    }
    if bytes.len() < AUDIO_HEADER || &bytes[..AUDIO_MAGIC.len()] != AUDIO_MAGIC {
        return Err(invalid_data());
    }
    let sample_rate = u32::from_le_bytes(bytes[4..8].try_into().map_err(|_| invalid_data())?);
    let channels = u16::from_le_bytes(bytes[8..10].try_into().map_err(|_| invalid_data())?);
    let time_us = u64::from_le_bytes(bytes[10..18].try_into().map_err(|_| invalid_data())?);
    let pcm = bytes[AUDIO_HEADER..].to_vec();
    if !valid_pcm(sample_rate, channels, &pcm) {
        return Err(invalid_data());
    }
    Ok(Packet::Audio(AudioChunk {
        sample_rate,
        channels,
        time_us,
        pcm,
    }))
}

fn write_jpeg(stream: &mut impl Write, jpeg: &[u8]) -> io::Result<()> {
    if !is_jpeg(jpeg) || jpeg.len() > MAX_JPEG_BYTES {
        return Err(invalid_data());
    }
    stream.write_all(&(jpeg.len() as u32).to_be_bytes())?;
    stream.write_all(jpeg)?;
    stream.flush()
}

fn read_bounded(stream: &mut impl Read, max: usize) -> io::Result<Vec<u8>> {
    let mut header = [0; 4];
    stream.read_exact(&mut header)?;
    let length = u32::from_be_bytes(header) as usize;
    if length == 0 || length > max {
        return Err(invalid_data());
    }
    let mut bytes = vec![0; length];
    stream.read_exact(&mut bytes)?;
    Ok(bytes)
}

fn invalid_data() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, "cast message was rejected")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::UdpSocket;

    const TINY_JPEG: &[u8] = &[
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06,
        0x05, 0x08, 0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b,
        0x0c, 0x19, 0x12, 0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20,
        0x24, 0x2e, 0x27, 0x20, 0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29, 0x2c, 0x30, 0x31,
        0x34, 0x34, 0x34, 0x1f, 0x27, 0x39, 0x3d, 0x38, 0x32, 0x3c, 0x2e, 0x33, 0x34, 0x32, 0xff,
        0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xff, 0xc4, 0x00,
        0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0xff, 0xc4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xda, 0x00, 0x08,
        0x01, 0x01, 0x00, 0x00, 0x3f, 0x00, 0x7f, 0xff, 0xd9,
    ];

    #[test]
    fn sound_waits_for_forty_milliseconds_then_plays() {
        let mut jitter = AudioJitter::new(48_000, 2);
        let ms = 192;
        let mut out = vec![9u8; 10 * ms];
        jitter.push(&vec![1; 30 * ms]);
        jitter.fill(&mut out);
        assert!(out.iter().all(|byte| *byte == 0));
        jitter.push(&vec![1; 10 * ms]);
        jitter.fill(&mut out);
        assert!(out.iter().all(|byte| *byte == 1));
    }

    #[test]
    fn a_stall_plays_silence_and_gathers_again() {
        let mut jitter = AudioJitter::new(48_000, 2);
        let ms = 192;
        jitter.push(&vec![1; 45 * ms]);
        let mut out = vec![9u8; 50 * ms];
        jitter.fill(&mut out);
        assert!(out[..45 * ms].iter().all(|byte| *byte == 1));
        assert!(out[45 * ms..].iter().all(|byte| *byte == 0));
        jitter.push(&vec![2; 10 * ms]);
        let mut again = vec![9u8; 5 * ms];
        jitter.fill(&mut again);
        assert!(again.iter().all(|byte| *byte == 0));
    }

    #[test]
    fn late_sound_drops_the_oldest_whole_frames() {
        let mut jitter = AudioJitter::new(48_000, 2);
        let ms = 192;
        jitter.push(&vec![1; 150 * ms]);
        jitter.push(&vec![2; 60 * ms]);
        assert_eq!(jitter.bytes.len(), 60 * ms);
        assert_eq!(jitter.bytes.len() % 4, 0);
        assert!(jitter.bytes.iter().all(|byte| *byte == 2));
    }

    #[test]
    fn jpeg_magic_rejects_non_images() {
        assert!(is_jpeg(TINY_JPEG));
        assert!(!is_jpeg(b"not-a-jpeg"));
        assert!(!is_jpeg(&[0xff, 0xd8]));
    }

    #[test]
    fn offer_rejects_zero_size() {
        let offer = Offer {
            version: 1,
            purpose: "cast-offer".to_owned(),
            mode: "mirror".to_owned(),
            width: 0,
            height: 720,
            audio: false,
        };
        assert!(matches!(validate_offer(&offer), Err("protocol")));
    }

    #[test]
    fn receiving_rejects_a_public_bind_address() {
        let receiver = PairingIdentity::generate().unwrap();
        let peer = PairingIdentity::generate().unwrap();
        let result = ReceiveSession::start(
            Ipv4Addr::new(8, 8, 8, 8),
            0,
            receiver,
            &[peer.certificate_der()],
        );
        assert!(matches!(result, Err(CastStartError::InvalidInput)));
    }

    #[test]
    fn approved_cast_delivers_a_frame_and_rejection_sends_nothing() {
        let Some(address) = private_interface_address() else {
            eprintln!("skipping cast transport: no connectable RFC1918 interface");
            return;
        };
        let sender = PairingIdentity::generate().unwrap();
        let sender_ca = sender.certificate_der().to_vec();
        let receiver = PairingIdentity::generate().unwrap();
        let receiver_ca = receiver.certificate_der().to_vec();
        let receive = ReceiveSession::start(address, 0, receiver, &[sender_ca.as_slice()]).unwrap();
        let send = SendSession::start(
            address,
            receive.endpoint().port(),
            sender,
            &receiver_ca,
            1280,
            720,
            true,
        )
        .unwrap();
        wait_until(&send, CastStatus::AwaitingApproval);
        wait_until(&receive, CastStatus::AwaitingApproval);
        assert!(receive.latest_frame().is_none());
        assert!(receive.reject());
        wait_until(&send, CastStatus::Rejected);
        wait_until(&receive, CastStatus::Rejected);
        assert!(receive.latest_frame().is_none());
        drop(send);
        drop(receive);

        let sender = PairingIdentity::generate().unwrap();
        let sender_ca = sender.certificate_der().to_vec();
        let receiver = PairingIdentity::generate().unwrap();
        let receiver_ca = receiver.certificate_der().to_vec();
        let receive =
            ReceiveSession::start(Ipv4Addr::UNSPECIFIED, 0, receiver, &[sender_ca.as_slice()])
                .unwrap();
        let send = SendSession::start(
            address,
            receive.endpoint().port(),
            sender,
            &receiver_ca,
            640,
            360,
            true,
        )
        .unwrap();
        wait_until(&receive, CastStatus::AwaitingApproval);
        assert_eq!(receive.snapshot().peer_index, Some(0));
        assert!(receive.approve());
        wait_until(&send, CastStatus::Casting);
        wait_until(&receive, CastStatus::Casting);
        let deadline = Instant::now() + Duration::from_secs(4);
        while Instant::now() < deadline && send.snapshot().frames == 0 {
            let _ = send.push_frame(TINY_JPEG);
            thread::sleep(Duration::from_millis(20));
        }
        assert!(send.snapshot().frames >= 1, "{:?}", send.snapshot());
        let deadline = Instant::now() + Duration::from_secs(4);
        while Instant::now() < deadline && receive.latest_frame().is_none() {
            thread::sleep(Duration::from_millis(20));
        }
        assert_eq!(receive.latest_frame().as_deref(), Some(TINY_JPEG));
        let mut pcm = Vec::new();
        for sample in [0_i16, 1000, -1000, 0] {
            pcm.extend_from_slice(&sample.to_le_bytes());
        }
        assert!(!send.push_audio(&[1, 2, 3], 48_000, 2));
        let mut heard = None;
        let deadline = Instant::now() + Duration::from_secs(4);
        while heard.is_none() && Instant::now() < deadline {
            assert!(send.push_audio(&pcm, 48_000, 2));
            heard = receive.take_audio();
            thread::sleep(Duration::from_millis(20));
        }
        let heard = heard.expect("system audio");
        assert_eq!(heard.sample_rate, 48_000);
        assert_eq!(heard.channels, 2);
        assert_eq!(heard.pcm, pcm);
        assert!(receive.snapshot().audio);
    }

    fn wait_until(session: &impl Snap, status: CastStatus) {
        let deadline = Instant::now() + Duration::from_secs(8);
        while session.snapshot().status != status && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(20));
        }
        assert_eq!(
            session.snapshot().status,
            status,
            "{:?}",
            session.snapshot().error_code
        );
    }

    trait Snap {
        fn snapshot(&self) -> CastSnapshot;
    }
    impl Snap for SendSession {
        fn snapshot(&self) -> CastSnapshot {
            SendSession::snapshot(self)
        }
    }
    impl Snap for ReceiveSession {
        fn snapshot(&self) -> CastSnapshot {
            ReceiveSession::snapshot(self)
        }
    }

    fn private_interface_address() -> Option<Ipv4Addr> {
        if let Ok(address) = std::env::var("MIRQUOVA_PAIRING_TEST_IPV4")
            && let Ok(address) = address.parse::<Ipv4Addr>()
            && is_lan_address(address)
        {
            return Some(address);
        }
        let socket = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)).ok()?;
        socket
            .connect(SocketAddrV4::new(Ipv4Addr::new(192, 0, 2, 1), 9))
            .ok()?;
        let address = match socket.local_addr().ok()?.ip() {
            std::net::IpAddr::V4(address) if is_lan_address(address) => address,
            _ => return None,
        };
        let listener = TcpListener::bind(SocketAddrV4::new(address, 0)).ok()?;
        listener.set_nonblocking(true).ok()?;
        let endpoint = listener.local_addr().ok()?;
        let stream = TcpStream::connect_timeout(&endpoint, Duration::from_millis(250)).ok()?;
        let accepted = listener.accept().ok()?;
        drop(stream);
        drop(accepted);
        Some(address)
    }
}
