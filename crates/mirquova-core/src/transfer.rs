//! Consent-gated file transfer over mutually authenticated TLS 1.3.
//! File bytes are written only after the receiver approves the offer.
use crate::{discovery::is_lan_address, pairing::PairingIdentity};
use aws_lc_rs::digest::{Context, SHA256};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File},
    io::{self, Read, Write},
    net::{Ipv4Addr, SocketAddrV4, TcpListener, TcpStream},
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, SyncSender},
    },
    thread::{self, JoinHandle},
    time::Duration,
};
use subtle::ConstantTimeEq;
use uuid::Uuid;

const PROTOCOL_VERSION: u16 = 1;
const MAX_FRAME_BYTES: usize = 16 * 1024;
const MAX_FILES: usize = 32;
const MAX_FILE_BYTES: u64 = 1024 * 1024 * 1024;
const MAX_NAME_BYTES: usize = 120;
const IO_TIMEOUT: Duration = Duration::from_secs(15);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
const ACCEPT_POLL: Duration = Duration::from_millis(100);
const CHUNK: usize = 64 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransferStartError {
    InvalidInput,
    Network,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferStatus {
    #[default]
    Idle,
    Listening,
    Connecting,
    AwaitingApproval,
    Transferring,
    Completed,
    Rejected,
    Stopped,
    Error,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferRole {
    Send,
    Receive,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferFileState {
    #[default]
    Pending,
    Transferring,
    Verified,
    Failed,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize)]
pub struct TransferFileSnapshot {
    pub name: String,
    pub size: u64,
    pub transferred: u64,
    pub state: TransferFileState,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize)]
pub struct TransferSnapshot {
    pub status: TransferStatus,
    pub role: Option<TransferRole>,
    pub endpoint: Option<String>,
    pub files: Vec<TransferFileSnapshot>,
    pub error_code: Option<&'static str>,
}

#[derive(Clone)]
struct SharedState(Arc<Mutex<TransferSnapshot>>);

impl SharedState {
    fn new(status: TransferStatus, role: TransferRole) -> Self {
        Self(Arc::new(Mutex::new(TransferSnapshot {
            status,
            role: Some(role),
            ..TransferSnapshot::default()
        })))
    }

    fn update(&self, update: impl FnOnce(&mut TransferSnapshot)) {
        update(&mut self.0.lock().unwrap_or_else(|error| error.into_inner()));
    }

    fn snapshot(&self) -> TransferSnapshot {
        self.0
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    fn fail(&self, code: &'static str) {
        self.update(|value| {
            value.status = TransferStatus::Error;
            value.error_code = Some(code);
            for file in &mut value.files {
                if file.state == TransferFileState::Transferring {
                    file.state = TransferFileState::Failed;
                }
            }
        });
    }
}

struct ListedFile {
    name: String,
    size: u64,
    sha256: String,
    path: PathBuf,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Offer {
    version: u16,
    purpose: String,
    files: Vec<OfferFile>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct OfferFile {
    name: String,
    size: u64,
    sha256: String,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Decision {
    version: u16,
    purpose: String,
    accept: bool,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ResultFrame {
    version: u16,
    purpose: String,
    ok: bool,
}

pub struct ReceiveSession {
    endpoint: SocketAddrV4,
    state: SharedState,
    cancel: Arc<AtomicBool>,
    decision: SyncSender<bool>,
    worker: Option<JoinHandle<()>>,
}

impl ReceiveSession {
    pub fn start(
        local_ipv4: Ipv4Addr,
        port: u16,
        identity: PairingIdentity,
        trusted_peer_cas: &[impl AsRef<[u8]>],
        destination: &Path,
    ) -> Result<Self, TransferStartError> {
        if !is_lan_address(local_ipv4) || trusted_peer_cas.is_empty() {
            return Err(TransferStartError::InvalidInput);
        }
        let destination = destination.to_path_buf();
        if !destination.is_dir() {
            return Err(TransferStartError::InvalidInput);
        }
        let config = identity
            .mutual_server_config_for_trusted_peers(trusted_peer_cas)
            .map_err(|_| TransferStartError::InvalidInput)?;
        let listener = TcpListener::bind(SocketAddrV4::new(local_ipv4, port))
            .map_err(|_| TransferStartError::Network)?;
        listener
            .set_nonblocking(true)
            .map_err(|_| TransferStartError::Network)?;
        let local = listener
            .local_addr()
            .map_err(|_| TransferStartError::Network)?;
        let endpoint = SocketAddrV4::new(local_ipv4, local.port());
        let state = SharedState::new(TransferStatus::Listening, TransferRole::Receive);
        state.update(|value| value.endpoint = Some(endpoint.to_string()));
        let cancel = Arc::new(AtomicBool::new(false));
        let (decision, decision_rx) = mpsc::sync_channel(1);
        let worker_state = state.clone();
        let worker_cancel = Arc::clone(&cancel);
        let worker = thread::Builder::new()
            .name("mirquova-transfer-receive".into())
            .spawn(move || {
                receive_worker(
                    listener,
                    config,
                    destination,
                    worker_state,
                    worker_cancel,
                    decision_rx,
                );
            })
            .map_err(|_| TransferStartError::Network)?;
        Ok(Self {
            endpoint,
            state,
            cancel,
            decision,
            worker: Some(worker),
        })
    }

    pub fn endpoint(&self) -> SocketAddrV4 {
        self.endpoint
    }

    pub fn snapshot(&self) -> TransferSnapshot {
        self.state.snapshot()
    }

    pub fn approve(&self) -> bool {
        self.state.snapshot().status == TransferStatus::AwaitingApproval
            && self.decision.try_send(true).is_ok()
    }

    pub fn reject(&self) -> bool {
        self.state.snapshot().status == TransferStatus::AwaitingApproval
            && self.decision.try_send(false).is_ok()
    }

    pub fn stop(&mut self) {
        self.cancel.store(true, Ordering::Release);
        let _ = self.decision.try_send(false);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
        let current = self.state.snapshot();
        if !matches!(
            current.status,
            TransferStatus::Completed | TransferStatus::Rejected | TransferStatus::Error
        ) {
            self.state
                .update(|value| value.status = TransferStatus::Stopped);
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
    worker: Option<JoinHandle<()>>,
}

impl SendSession {
    pub fn start(
        peer_ipv4: Ipv4Addr,
        port: u16,
        identity: PairingIdentity,
        peer_ca: &[u8],
        paths: &[PathBuf],
    ) -> Result<Self, TransferStartError> {
        if !is_lan_address(peer_ipv4) || port == 0 || paths.is_empty() || paths.len() > MAX_FILES {
            return Err(TransferStartError::InvalidInput);
        }
        let files = match list_local_files(paths) {
            Ok(files) => files,
            Err(code) => {
                let state = SharedState::new(TransferStatus::Error, TransferRole::Send);
                state.fail(code);
                return Ok(Self {
                    state,
                    cancel: Arc::new(AtomicBool::new(false)),
                    worker: None,
                });
            }
        };
        let config = identity
            .mutual_client_config(peer_ca)
            .map_err(|_| TransferStartError::InvalidInput)?;
        let state = SharedState::new(TransferStatus::Connecting, TransferRole::Send);
        state.update(|value| {
            value.endpoint = Some(SocketAddrV4::new(peer_ipv4, port).to_string());
            value.files = files
                .iter()
                .map(|file| TransferFileSnapshot {
                    name: file.name.clone(),
                    size: file.size,
                    transferred: 0,
                    state: TransferFileState::Pending,
                })
                .collect();
        });
        let cancel = Arc::new(AtomicBool::new(false));
        let worker_state = state.clone();
        let worker_cancel = Arc::clone(&cancel);
        let worker = thread::Builder::new()
            .name("mirquova-transfer-send".into())
            .spawn(move || {
                send_worker(
                    SocketAddrV4::new(peer_ipv4, port),
                    config,
                    files,
                    worker_state,
                    worker_cancel,
                );
            })
            .map_err(|_| TransferStartError::Network)?;
        Ok(Self {
            state,
            cancel,
            worker: Some(worker),
        })
    }

    pub fn snapshot(&self) -> TransferSnapshot {
        self.state.snapshot()
    }

    pub fn stop(&mut self) {
        self.cancel.store(true, Ordering::Release);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
        let current = self.state.snapshot();
        if !matches!(
            current.status,
            TransferStatus::Completed | TransferStatus::Rejected | TransferStatus::Error
        ) {
            self.state
                .update(|value| value.status = TransferStatus::Stopped);
        }
    }
}

impl Drop for SendSession {
    fn drop(&mut self) {
        self.stop();
    }
}

fn receive_worker(
    listener: TcpListener,
    config: std::sync::Arc<rustls::ServerConfig>,
    destination: PathBuf,
    state: SharedState,
    cancel: Arc<AtomicBool>,
    decision_rx: Receiver<bool>,
) {
    let socket = loop {
        if cancel.load(Ordering::Acquire) {
            return;
        }
        match listener.accept() {
            Ok((socket, _)) => break socket,
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
    let offer = match read_frame(&mut stream)
        .and_then(|bytes| serde_json::from_slice::<Offer>(&bytes).map_err(|_| invalid_data()))
    {
        Ok(offer) => offer,
        Err(_) => {
            state.fail("protocol");
            return;
        }
    };
    let files = match validate_offer(&offer) {
        Ok(files) => files,
        Err(code) => {
            state.fail(code);
            return;
        }
    };
    state.update(|value| {
        value.status = TransferStatus::AwaitingApproval;
        value.files = files
            .iter()
            .map(|file| TransferFileSnapshot {
                name: file.name.clone(),
                size: file.size,
                transferred: 0,
                state: TransferFileState::Pending,
            })
            .collect();
    });
    let accept = wait_for_decision(&decision_rx, &cancel);
    if cancel.load(Ordering::Acquire) {
        let _ = write_decision(&mut stream, false);
        return;
    }
    if !accept {
        let _ = write_decision(&mut stream, false);
        state.update(|value| value.status = TransferStatus::Rejected);
        return;
    }
    if write_decision(&mut stream, true).is_err() {
        state.fail("network");
        return;
    }
    state.update(|value| value.status = TransferStatus::Transferring);
    for (index, file) in files.iter().enumerate() {
        if cancel.load(Ordering::Acquire) {
            return;
        }
        match receive_file(&mut stream, &destination, file, index, &state, &cancel) {
            Ok(()) => {}
            Err(code) => {
                state.fail(code);
                let _ = write_result(&mut stream, false);
                return;
            }
        }
    }
    if write_result(&mut stream, true).is_err() {
        state.fail("network");
        return;
    }
    state.update(|value| value.status = TransferStatus::Completed);
}

fn send_worker(
    endpoint: SocketAddrV4,
    config: std::sync::Arc<rustls::ClientConfig>,
    files: Vec<ListedFile>,
    state: SharedState,
    cancel: Arc<AtomicBool>,
) {
    if cancel.load(Ordering::Acquire) {
        return;
    }
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
    let offer = Offer {
        version: PROTOCOL_VERSION,
        purpose: "file-offer".to_owned(),
        files: files
            .iter()
            .map(|file| OfferFile {
                name: file.name.clone(),
                size: file.size,
                sha256: file.sha256.clone(),
            })
            .collect(),
    };
    if write_frame(&mut stream, &offer).is_err() {
        state.fail("network");
        return;
    }
    state.update(|value| value.status = TransferStatus::AwaitingApproval);
    let decision = match read_frame(&mut stream)
        .and_then(|bytes| serde_json::from_slice::<Decision>(&bytes).map_err(|_| invalid_data()))
    {
        Ok(decision) => decision,
        Err(_) => {
            if cancel.load(Ordering::Acquire) {
                return;
            }
            state.fail("protocol");
            return;
        }
    };
    if decision.version != PROTOCOL_VERSION || decision.purpose != "file-decision" {
        state.fail("protocol");
        return;
    }
    if !decision.accept {
        state.update(|value| value.status = TransferStatus::Rejected);
        return;
    }
    if cancel.load(Ordering::Acquire) {
        return;
    }
    state.update(|value| value.status = TransferStatus::Transferring);
    for (index, file) in files.iter().enumerate() {
        if cancel.load(Ordering::Acquire) {
            return;
        }
        if let Err(code) = send_file(&mut stream, file, index, &state, &cancel) {
            state.fail(code);
            return;
        }
    }
    let result = match read_frame(&mut stream)
        .and_then(|bytes| serde_json::from_slice::<ResultFrame>(&bytes).map_err(|_| invalid_data()))
    {
        Ok(result) => result,
        Err(_) => {
            if cancel.load(Ordering::Acquire) {
                return;
            }
            state.fail("protocol");
            return;
        }
    };
    if result.version != PROTOCOL_VERSION || result.purpose != "file-result" || !result.ok {
        state.fail("not_verified");
        return;
    }
    state.update(|value| value.status = TransferStatus::Completed);
}

fn wait_for_decision(decision_rx: &Receiver<bool>, cancel: &AtomicBool) -> bool {
    loop {
        if cancel.load(Ordering::Acquire) {
            return false;
        }
        match decision_rx.recv_timeout(ACCEPT_POLL) {
            Ok(accept) => return accept,
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => return false,
        }
    }
}

fn receive_file(
    stream: &mut impl Read,
    destination: &Path,
    file: &OfferFile,
    index: usize,
    state: &SharedState,
    cancel: &AtomicBool,
) -> Result<(), &'static str> {
    let final_path = contained_path(destination, &file.name).map_err(|_| "invalid_name")?;
    if final_path.exists() {
        discard(stream, file.size, cancel)?;
        return Err("conflict");
    }
    state.update(|value| {
        if let Some(item) = value.files.get_mut(index) {
            item.state = TransferFileState::Transferring;
        }
    });
    let partial_path = destination.join(format!("{}.mqpart", Uuid::new_v4()));
    let mut partial = TempFile::create(&partial_path).map_err(|_| "storage")?;
    let mut hasher = Context::new(&SHA256);
    copy_stream(
        stream,
        &mut partial,
        file.size,
        &mut hasher,
        index,
        state,
        cancel,
    )?;
    let actual = hasher.finish();
    let expected = decode_hex(&file.sha256).ok_or("protocol")?;
    if expected.len() != actual.as_ref().len()
        || !bool::from(expected.as_slice().ct_eq(actual.as_ref()))
    {
        return Err("hash_mismatch");
    }
    partial.persist(&final_path).map_err(|_| "storage")?;
    state.update(|value| {
        if let Some(item) = value.files.get_mut(index) {
            item.transferred = file.size;
            item.state = TransferFileState::Verified;
        }
    });
    Ok(())
}

fn send_file(
    stream: &mut impl Write,
    file: &ListedFile,
    index: usize,
    state: &SharedState,
    cancel: &AtomicBool,
) -> Result<(), &'static str> {
    state.update(|value| {
        if let Some(item) = value.files.get_mut(index) {
            item.state = TransferFileState::Transferring;
        }
    });
    let mut source = File::open(&file.path).map_err(|_| "storage")?;
    let mut hasher = Context::new(&SHA256);
    let mut sent = 0_u64;
    let mut buffer = [0_u8; CHUNK];
    while sent < file.size {
        if cancel.load(Ordering::Acquire) {
            return Err("cancelled");
        }
        let want = usize::try_from((file.size - sent).min(CHUNK as u64)).unwrap_or(CHUNK);
        let read = source.read(&mut buffer[..want]).map_err(|_| "storage")?;
        if read == 0 {
            return Err("storage");
        }
        stream.write_all(&buffer[..read]).map_err(|_| "network")?;
        hasher.update(&buffer[..read]);
        sent += read as u64;
        let transferred = sent;
        state.update(|value| {
            if let Some(item) = value.files.get_mut(index) {
                item.transferred = transferred;
            }
        });
    }
    stream.flush().map_err(|_| "network")?;
    let actual = hasher.finish();
    let expected = decode_hex(&file.sha256).ok_or("protocol")?;
    if !bool::from(expected.as_slice().ct_eq(actual.as_ref())) {
        return Err("hash_mismatch");
    }
    state.update(|value| {
        if let Some(item) = value.files.get_mut(index) {
            item.state = TransferFileState::Verified;
        }
    });
    Ok(())
}

fn discard(stream: &mut impl Read, size: u64, cancel: &AtomicBool) -> Result<(), &'static str> {
    let mut left = size;
    let mut buffer = [0_u8; CHUNK];
    while left > 0 {
        if cancel.load(Ordering::Acquire) {
            return Err("cancelled");
        }
        let want = usize::try_from(left.min(CHUNK as u64)).unwrap_or(CHUNK);
        let read = stream.read(&mut buffer[..want]).map_err(|_| "network")?;
        if read == 0 {
            return Err("network");
        }
        left -= read as u64;
    }
    Ok(())
}

fn copy_stream(
    stream: &mut impl Read,
    output: &mut impl Write,
    size: u64,
    hasher: &mut Context,
    index: usize,
    state: &SharedState,
    cancel: &AtomicBool,
) -> Result<(), &'static str> {
    let mut received = 0_u64;
    let mut buffer = [0_u8; CHUNK];
    while received < size {
        if cancel.load(Ordering::Acquire) {
            return Err("cancelled");
        }
        let want = usize::try_from((size - received).min(CHUNK as u64)).unwrap_or(CHUNK);
        let read = stream.read(&mut buffer[..want]).map_err(|_| "network")?;
        if read == 0 {
            return Err("network");
        }
        output.write_all(&buffer[..read]).map_err(|_| "storage")?;
        hasher.update(&buffer[..read]);
        received += read as u64;
        let transferred = received;
        state.update(|value| {
            if let Some(item) = value.files.get_mut(index) {
                item.transferred = transferred;
            }
        });
    }
    output.flush().map_err(|_| "storage")
}

struct TempFile {
    path: PathBuf,
    file: Option<File>,
    keep: bool,
}

impl TempFile {
    fn create(path: &Path) -> io::Result<Self> {
        let file = File::create(path)?;
        Ok(Self {
            path: path.to_path_buf(),
            file: Some(file),
            keep: false,
        })
    }

    fn persist(mut self, final_path: &Path) -> io::Result<()> {
        if let Some(file) = self.file.take() {
            file.sync_all()?;
        }
        fs::rename(&self.path, final_path)?;
        self.keep = true;
        Ok(())
    }
}

impl Write for TempFile {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        self.file
            .as_mut()
            .ok_or_else(|| io::Error::other("partial file is closed"))?
            .write(buffer)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.file
            .as_mut()
            .ok_or_else(|| io::Error::other("partial file is closed"))?
            .flush()
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        self.file.take();
        if !self.keep {
            let _ = fs::remove_file(&self.path);
        }
    }
}

fn list_local_files(paths: &[PathBuf]) -> Result<Vec<ListedFile>, &'static str> {
    let mut files = Vec::with_capacity(paths.len());
    let mut names = Vec::with_capacity(paths.len());
    for path in paths {
        let name = path
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or("invalid_name")?;
        let name = sanitize_file_name(name).ok_or("invalid_name")?;
        if names.iter().any(|existing: &String| existing == name) {
            return Err("invalid_name");
        }
        let source = File::open(path).map_err(|_| "storage")?;
        let metadata = source.metadata().map_err(|_| "storage")?;
        if !metadata.is_file() || metadata.len() > MAX_FILE_BYTES {
            return Err("invalid_input");
        }
        let mut hasher = Context::new(&SHA256);
        let mut reader = source;
        let mut buffer = [0_u8; CHUNK];
        loop {
            let read = reader.read(&mut buffer).map_err(|_| "storage")?;
            if read == 0 {
                break;
            }
            hasher.update(&buffer[..read]);
        }
        names.push(name.to_owned());
        files.push(ListedFile {
            name: name.to_owned(),
            size: metadata.len(),
            sha256: encode_hex(hasher.finish().as_ref()),
            path: path.clone(),
        });
    }
    Ok(files)
}

fn validate_offer(offer: &Offer) -> Result<&[OfferFile], &'static str> {
    if offer.version != PROTOCOL_VERSION || offer.purpose != "file-offer" {
        return Err("protocol");
    }
    if offer.files.is_empty() || offer.files.len() > MAX_FILES {
        return Err("protocol");
    }
    let mut names = Vec::new();
    for file in &offer.files {
        let name = sanitize_file_name(&file.name).ok_or("invalid_name")?;
        if name != file.name || names.iter().any(|existing: &String| existing == name) {
            return Err("invalid_name");
        }
        if file.size > MAX_FILE_BYTES
            || decode_hex(&file.sha256)
                .filter(|bytes| bytes.len() == 32)
                .is_none()
        {
            return Err("protocol");
        }
        names.push(name.to_owned());
    }
    Ok(&offer.files)
}

pub fn sanitize_file_name(name: &str) -> Option<&str> {
    if name.is_empty()
        || name.len() > MAX_NAME_BYTES
        || name != name.trim()
        || name.ends_with('.')
        || name.chars().any(|character| {
            character.is_control()
                || matches!(
                    character,
                    '/' | '\\' | ':' | '<' | '>' | '"' | '|' | '?' | '*'
                )
        })
    {
        return None;
    }
    let stem = name.split('.').next().unwrap_or(name);
    let reserved = matches!(
        stem.to_ascii_uppercase().as_str(),
        "CON"
            | "PRN"
            | "AUX"
            | "NUL"
            | "COM1"
            | "COM2"
            | "COM3"
            | "COM4"
            | "COM5"
            | "COM6"
            | "COM7"
            | "COM8"
            | "COM9"
            | "LPT1"
            | "LPT2"
            | "LPT3"
            | "LPT4"
            | "LPT5"
            | "LPT6"
            | "LPT7"
            | "LPT8"
            | "LPT9"
    );
    if reserved || stem.is_empty() {
        return None;
    }
    Some(name)
}

fn contained_path(root: &Path, name: &str) -> io::Result<PathBuf> {
    let name = sanitize_file_name(name).ok_or_else(invalid_data)?;
    let root = root.canonicalize()?;
    if !root.is_dir() {
        return Err(invalid_data());
    }
    let candidate = root.join(name);
    if candidate.parent() != Some(root.as_path()) {
        return Err(invalid_data());
    }
    Ok(candidate)
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

fn write_decision(stream: &mut impl Write, accept: bool) -> io::Result<()> {
    write_frame(
        stream,
        &Decision {
            version: PROTOCOL_VERSION,
            purpose: "file-decision".to_owned(),
            accept,
        },
    )
}

fn write_result(stream: &mut impl Write, ok: bool) -> io::Result<()> {
    write_frame(
        stream,
        &ResultFrame {
            version: PROTOCOL_VERSION,
            purpose: "file-result".to_owned(),
            ok,
        },
    )
}

fn write_frame(stream: &mut impl Write, value: &impl Serialize) -> io::Result<()> {
    let bytes = serde_json::to_vec(value).map_err(|_| invalid_data())?;
    if bytes.is_empty() || bytes.len() > MAX_FRAME_BYTES {
        return Err(invalid_data());
    }
    stream.write_all(&(bytes.len() as u32).to_be_bytes())?;
    stream.write_all(&bytes)?;
    stream.flush()
}

fn read_frame(stream: &mut impl Read) -> io::Result<Vec<u8>> {
    let mut header = [0; 4];
    stream.read_exact(&mut header)?;
    let length = u32::from_be_bytes(header) as usize;
    if length == 0 || length > MAX_FRAME_BYTES {
        return Err(invalid_data());
    }
    let mut bytes = vec![0; length];
    stream.read_exact(&mut bytes)?;
    Ok(bytes)
}

fn invalid_data() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, "transfer message was rejected")
}

pub(crate) fn decode_hex(value: &str) -> Option<Vec<u8>> {
    if value.is_empty() || !value.len().is_multiple_of(2) {
        return None;
    }
    fn digit(value: u8) -> Option<u8> {
        match value {
            b'0'..=b'9' => Some(value - b'0'),
            b'a'..=b'f' => Some(value - b'a' + 10),
            _ => None,
        }
    }
    value
        .as_bytes()
        .chunks(2)
        .map(|pair| Some((digit(*pair.first()?)? << 4) | digit(*pair.get(1)?)?))
        .collect()
}

fn encode_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut encoded = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        encoded.push(HEX[(byte >> 4) as usize] as char);
        encoded.push(HEX[(byte & 0x0f) as usize] as char);
    }
    encoded
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::UdpSocket;
    use std::time::Instant;

    #[test]
    fn file_names_reject_traversal_and_reserved_devices() {
        assert!(sanitize_file_name("clip.mp4").is_some());
        assert!(sanitize_file_name("").is_none());
        assert!(sanitize_file_name("..").is_none());
        assert!(sanitize_file_name("../secret").is_none());
        assert!(sanitize_file_name("a/b").is_none());
        assert!(sanitize_file_name("a\\b").is_none());
        assert!(sanitize_file_name("CON").is_none());
        assert!(sanitize_file_name("con.txt").is_none());
        assert!(sanitize_file_name(" trailing ").is_none());
        assert!(sanitize_file_name("end.").is_none());
    }

    #[test]
    fn offer_rejects_a_bad_digest_before_approval() {
        let offer = Offer {
            version: 1,
            purpose: "file-offer".to_owned(),
            files: vec![OfferFile {
                name: "note.txt".to_owned(),
                size: 1,
                sha256: "abcd".to_owned(),
            }],
        };
        assert!(matches!(validate_offer(&offer), Err("protocol")));
    }

    #[test]
    fn offer_rejects_traversal_names() {
        let offer = Offer {
            version: 1,
            purpose: "file-offer".to_owned(),
            files: vec![OfferFile {
                name: "../note.txt".to_owned(),
                size: 0,
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                    .to_owned(),
            }],
        };
        assert!(matches!(validate_offer(&offer), Err("invalid_name")));
    }

    #[test]
    fn approved_transfer_verifies_bytes_and_rejection_writes_nothing() {
        let Some(address) = private_interface_address() else {
            eprintln!("skipping transfer transport: no connectable RFC1918 interface");
            return;
        };
        let root = std::env::temp_dir().join(format!("mirquova-transfer-{}", Uuid::new_v4()));
        fs::create_dir(&root).unwrap();
        let source = root.join("note.txt");
        fs::write(&source, b"hello").unwrap();
        let empty = root.join("empty.txt");
        fs::write(&empty, b"").unwrap();
        let destination = root.join("inbox");
        fs::create_dir(&destination).unwrap();

        let sender = PairingIdentity::generate().unwrap();
        let sender_ca = sender.certificate_der().to_vec();
        let receiver = PairingIdentity::generate().unwrap();
        let receiver_ca = receiver.certificate_der().to_vec();
        let receive =
            ReceiveSession::start(address, 0, receiver, &[sender_ca.as_slice()], &destination)
                .unwrap();
        let send = SendSession::start(
            address,
            receive.endpoint().port(),
            sender,
            &receiver_ca,
            std::slice::from_ref(&source),
        )
        .unwrap();
        wait_until(&send, TransferStatus::AwaitingApproval);
        wait_until(&receive, TransferStatus::AwaitingApproval);
        assert!(destination.read_dir().unwrap().next().is_none());
        assert!(receive.reject());
        wait_until(&send, TransferStatus::Rejected);
        wait_until(&receive, TransferStatus::Rejected);
        assert!(destination.read_dir().unwrap().next().is_none());
        drop(send);
        drop(receive);

        let sender = PairingIdentity::generate().unwrap();
        let sender_ca = sender.certificate_der().to_vec();
        let receiver = PairingIdentity::generate().unwrap();
        let receiver_ca = receiver.certificate_der().to_vec();
        let receive =
            ReceiveSession::start(address, 0, receiver, &[sender_ca.as_slice()], &destination)
                .unwrap();
        let send = SendSession::start(
            address,
            receive.endpoint().port(),
            sender,
            &receiver_ca,
            &[source, empty],
        )
        .unwrap();
        wait_until(&receive, TransferStatus::AwaitingApproval);
        assert_eq!(receive.snapshot().files[0].name, "note.txt");
        assert!(receive.approve());
        wait_until(&send, TransferStatus::Completed);
        wait_until(&receive, TransferStatus::Completed);
        assert_eq!(fs::read(destination.join("note.txt")).unwrap(), b"hello");
        assert_eq!(fs::read(destination.join("empty.txt")).unwrap(), b"");

        let sender = PairingIdentity::generate().unwrap();
        let sender_ca = sender.certificate_der().to_vec();
        let receiver = PairingIdentity::generate().unwrap();
        let receiver_ca = receiver.certificate_der().to_vec();
        let receive =
            ReceiveSession::start(address, 0, receiver, &[sender_ca.as_slice()], &destination)
                .unwrap();
        let conflict_source = root.join("note.txt");
        let send = SendSession::start(
            address,
            receive.endpoint().port(),
            sender,
            &receiver_ca,
            &[conflict_source],
        )
        .unwrap();
        wait_until(&receive, TransferStatus::AwaitingApproval);
        assert!(receive.approve());
        wait_until(&receive, TransferStatus::Error);
        assert_eq!(receive.snapshot().error_code, Some("conflict"));
        assert_eq!(fs::read(destination.join("note.txt")).unwrap(), b"hello");
        drop(send);
        drop(receive);
        let _ = fs::remove_dir_all(&root);
    }

    fn wait_until(session: &impl Snap, status: TransferStatus) {
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
        fn snapshot(&self) -> TransferSnapshot;
    }
    impl Snap for SendSession {
        fn snapshot(&self) -> TransferSnapshot {
            SendSession::snapshot(self)
        }
    }
    impl Snap for ReceiveSession {
        fn snapshot(&self) -> TransferSnapshot {
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
