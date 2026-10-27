//! Opt-in, one-use TLS 1.3 mutual-authenticated LAN pairing.
use crate::{
    discovery::is_lan_address,
    invitation::PairingInvitation,
    pairing::{PairingIdentity, tls_server_name, validate_ca},
    presence::valid_alias,
};
use aws_lc_rs::digest::{SHA256, digest};
use rustls::{ClientConfig, ServerConfig};
use serde::{Deserialize, Serialize};
use socket2::{Domain, Protocol, Socket, Type};
use std::{
    fmt,
    io::{self, Read, Write},
    net::{Ipv4Addr, SocketAddrV4, TcpListener, TcpStream},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, SyncSender},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};
use subtle::ConstantTimeEq;
use zeroize::{Zeroize, Zeroizing};

const MAX_PAIRING_MESSAGE_BYTES: usize = 2048;
const MAX_MUTUAL_AUTH_ATTEMPTS: u8 = 5;
const IO_TIMEOUT: Duration = Duration::from_secs(3);
const ACCEPT_POLL: Duration = Duration::from_millis(100);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PairingStatus {
    #[default]
    Idle,
    WaitingForPeer,
    Connecting,
    AwaitingApproval,
    Paired,
    Rejected,
    Expired,
    Stopped,
    Error,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct PairingSnapshot {
    pub status: PairingStatus,
    pub peer_alias: Option<String>,
    pub peer_ca_certificate_der_hex: Option<String>,
    pub error_code: Option<&'static str>,
}

#[derive(Clone)]
struct SharedState(Arc<Mutex<PairingSnapshot>>);

impl SharedState {
    fn new(status: PairingStatus) -> Self {
        Self(Arc::new(Mutex::new(PairingSnapshot {
            status,
            ..PairingSnapshot::default()
        })))
    }

    fn set(&self, value: PairingSnapshot) {
        *self.0.lock().unwrap_or_else(|error| error.into_inner()) = value;
    }

    fn update(&self, update: impl FnOnce(&mut PairingSnapshot)) {
        update(&mut self.0.lock().unwrap_or_else(|error| error.into_inner()));
    }

    fn snapshot(&self) -> PairingSnapshot {
        self.0
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }
}

pub struct HostSession {
    payload: Zeroizing<String>,
    endpoint: SocketAddrV4,
    state: SharedState,
    cancel: Arc<AtomicBool>,
    decision: SyncSender<bool>,
    worker: Option<JoinHandle<()>>,
}

impl fmt::Debug for HostSession {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("HostSession { redacted } ")
    }
}

impl HostSession {
    pub fn start(
        local_ipv4: Ipv4Addr,
        port: u16,
        identity: PairingIdentity,
        host_alias: &str,
        validity: Duration,
    ) -> Result<Self, PairingTransportError> {
        if !is_lan_address(local_ipv4) || !valid_alias(host_alias) {
            return Err(PairingTransportError::InvalidInput);
        }
        let listener = TcpListener::bind(SocketAddrV4::new(local_ipv4, port))
            .map_err(|_| PairingTransportError::Network)?;
        listener
            .set_nonblocking(true)
            .map_err(|_| PairingTransportError::Network)?;
        let local = listener
            .local_addr()
            .map_err(|_| PairingTransportError::Network)?;
        let endpoint = SocketAddrV4::new(local_ipv4, local.port());
        let generated = PairingInvitation::generate(endpoint, identity.certificate_der(), validity)
            .map_err(|_| PairingTransportError::InvalidInput)?;
        let (payload, invitation) = generated.into_parts();
        let state = SharedState::new(PairingStatus::WaitingForPeer);
        let cancel = Arc::new(AtomicBool::new(false));
        let (decision, decision_rx) = mpsc::sync_channel(1);
        let worker_state = state.clone();
        let worker_cancel = cancel.clone();
        let host_alias = host_alias.trim().to_owned();
        let worker = thread::Builder::new()
            .name("mirquova-pairing-host".into())
            .spawn(move || {
                host_worker(
                    listener,
                    identity,
                    invitation,
                    &host_alias,
                    worker_state,
                    worker_cancel,
                    decision_rx,
                );
            })
            .map_err(|_| PairingTransportError::Network)?;
        Ok(Self {
            payload,
            endpoint,
            state,
            cancel,
            decision,
            worker: Some(worker),
        })
    }

    pub fn payload(&self) -> &str {
        self.payload.as_str()
    }

    pub fn endpoint(&self) -> SocketAddrV4 {
        self.endpoint
    }

    pub fn snapshot(&self) -> PairingSnapshot {
        self.state.snapshot()
    }

    pub fn approve(&self) -> bool {
        self.decision.try_send(true).is_ok()
    }

    pub fn reject(&self) -> bool {
        self.decision.try_send(false).is_ok()
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
            PairingStatus::Paired | PairingStatus::Rejected
        ) {
            self.state
                .update(|value| value.status = PairingStatus::Stopped);
        }
        self.payload.zeroize();
    }
}

impl Drop for HostSession {
    fn drop(&mut self) {
        self.stop();
    }
}

pub struct JoinSession {
    state: SharedState,
    cancel: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
}

impl fmt::Debug for JoinSession {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("JoinSession { redacted }")
    }
}

impl JoinSession {
    pub fn start(
        invitation_payload: &[u8],
        confirmed_fingerprint_sha256: &[u8; 32],
        identity: PairingIdentity,
        alias: &str,
    ) -> Result<Self, PairingTransportError> {
        if !valid_alias(alias) {
            return Err(PairingTransportError::InvalidInput);
        }
        let invitation = PairingInvitation::parse(invitation_payload)
            .map_err(|_| PairingTransportError::InvalidInvitation)?;
        validate_ca(invitation.identity_ca_certificate_der())
            .map_err(|_| PairingTransportError::InvalidInvitation)?;
        let fingerprint = digest(&SHA256, invitation.identity_ca_certificate_der());
        if fingerprint
            .as_ref()
            .ct_eq(confirmed_fingerprint_sha256)
            .unwrap_u8()
            != 1
        {
            return Err(PairingTransportError::FingerprintMismatch);
        }

        let state = SharedState::new(PairingStatus::Connecting);
        let cancel = Arc::new(AtomicBool::new(false));
        let worker_state = state.clone();
        let worker_cancel = cancel.clone();
        let alias = alias.trim().to_owned();
        let worker = thread::Builder::new()
            .name("mirquova-pairing-join".into())
            .spawn(move || {
                join_worker(invitation, identity, &alias, worker_state, worker_cancel);
            })
            .map_err(|_| PairingTransportError::Network)?;
        Ok(Self {
            state,
            cancel,
            worker: Some(worker),
        })
    }

    pub fn snapshot(&self) -> PairingSnapshot {
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
            PairingStatus::Paired | PairingStatus::Rejected
        ) {
            self.state
                .update(|value| value.status = PairingStatus::Stopped);
        }
    }
}

impl Drop for JoinSession {
    fn drop(&mut self) {
        self.stop();
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PairingTransportError {
    InvalidInput,
    InvalidInvitation,
    FingerprintMismatch,
    Network,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct BootstrapRequest {
    secret: String,
    identity_ca_certificate_der_hex: String,
}

#[derive(Serialize)]
struct BootstrapRequestRef<'a> {
    secret: &'a str,
    identity_ca_certificate_der_hex: String,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PairingProof {
    alias: String,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PairingResponse {
    status: ResponseStatus,
    peer_alias: Option<String>,
}

#[derive(Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum ResponseStatus {
    Continue,
    Accepted,
    Rejected,
}

fn host_worker(
    listener: TcpListener,
    identity: PairingIdentity,
    mut invitation: PairingInvitation,
    host_alias: &str,
    state: SharedState,
    cancel: Arc<AtomicBool>,
    decisions: Receiver<bool>,
) {
    let deadline = Instant::now() + invitation.remaining_validity();
    let bootstrap_config = match identity.bootstrap_server_config() {
        Ok(config) => config,
        Err(_) => return fail(&state, "tls_configuration"),
    };
    let mut candidate_ca = None;
    while !cancel.load(Ordering::Acquire) && Instant::now() < deadline {
        let Some(socket) = accept_until(&listener, deadline, &cancel) else {
            break;
        };
        match accept_bootstrap(
            socket,
            bootstrap_config.clone(),
            &mut invitation,
            host_alias,
        ) {
            Ok(certificate) => {
                candidate_ca = Some(certificate);
                break;
            }
            Err(InvitationFailure::AttemptsExceeded | InvitationFailure::Expired) => {
                state.update(|value| value.status = PairingStatus::Expired);
                return;
            }
            Err(InvitationFailure::Network | InvitationFailure::InvalidRequest) => continue,
        }
    }
    let Some(candidate_ca) = candidate_ca else {
        if !cancel.load(Ordering::Acquire) {
            state.update(|value| value.status = PairingStatus::Expired);
        }
        return;
    };

    let server_config = match identity.mutual_server_config(&candidate_ca) {
        Ok(config) => config,
        Err(_) => return fail(&state, "tls_configuration"),
    };
    let mut authenticated_peer = None;
    for _ in 0..MAX_MUTUAL_AUTH_ATTEMPTS {
        let Some(socket) = accept_until(&listener, deadline, &cancel) else {
            break;
        };
        let mut stream = match server_stream(socket, server_config.clone()) {
            Ok(stream) => stream,
            // A second bearer attempt or arbitrary LAN client cannot abort the
            // already-consumed invitation's mutually authenticated exchange.
            Err(_) => continue,
        };
        let proof: PairingProof = match read_frame(&mut stream)
            .and_then(|bytes| serde_json::from_slice::<PairingProof>(&bytes).map_err(invalid_data))
        {
            Ok(proof) if valid_alias(&proof.alias) => proof,
            _ => continue,
        };
        authenticated_peer = Some((stream, proof));
        break;
    }
    let Some((mut stream, proof)) = authenticated_peer else {
        if !cancel.load(Ordering::Acquire) {
            fail(
                &state,
                if Instant::now() >= deadline {
                    "expired"
                } else {
                    "client_authentication_failed"
                },
            );
        }
        return;
    };
    state.set(PairingSnapshot {
        status: PairingStatus::AwaitingApproval,
        peer_alias: Some(proof.alias),
        peer_ca_certificate_der_hex: Some(encode_hex(&candidate_ca)),
        error_code: None,
    });

    let decision = decisions.recv_timeout(deadline.saturating_duration_since(Instant::now()));
    match decision {
        Ok(true) if !cancel.load(Ordering::Acquire) => {
            if write_frame(
                &mut stream,
                &PairingResponse {
                    status: ResponseStatus::Accepted,
                    peer_alias: Some(host_alias.to_owned()),
                },
            )
            .is_err()
            {
                return fail(&state, "network");
            }
            state.update(|value| value.status = PairingStatus::Paired);
        }
        Ok(false) => {
            let _ = write_frame(
                &mut stream,
                &PairingResponse {
                    status: ResponseStatus::Rejected,
                    peer_alias: None,
                },
            );
            state.update(|value| {
                value.status = if cancel.load(Ordering::Acquire) {
                    PairingStatus::Stopped
                } else {
                    PairingStatus::Rejected
                }
            });
        }
        Err(_) => {
            let _ = write_frame(
                &mut stream,
                &PairingResponse {
                    status: ResponseStatus::Rejected,
                    peer_alias: None,
                },
            );
            if !cancel.load(Ordering::Acquire) {
                state.update(|value| value.status = PairingStatus::Expired);
            }
        }
        Ok(true) => state.update(|value| value.status = PairingStatus::Stopped),
    }
}

fn accept_bootstrap(
    socket: TcpStream,
    config: Arc<ServerConfig>,
    invitation: &mut PairingInvitation,
    host_alias: &str,
) -> Result<Vec<u8>, InvitationFailure> {
    let mut stream = match server_stream(socket, config) {
        Ok(stream) => stream,
        Err(_) => return Err(charge_failed_attempt(invitation)),
    };
    let mut bytes = match read_frame(&mut stream) {
        Ok(bytes) => bytes,
        Err(_) => return Err(charge_failed_attempt(invitation)),
    };
    let request = serde_json::from_slice(&bytes);
    bytes.zeroize();
    let mut request: BootstrapRequest = match request {
        Ok(request) => request,
        Err(_) => return Err(charge_failed_attempt(invitation)),
    };
    let certificate = match decode_hex(&request.identity_ca_certificate_der_hex, 512) {
        Some(certificate) => certificate,
        None => {
            request.secret.zeroize();
            return Err(charge_failed_attempt(invitation));
        }
    };
    if validate_ca(&certificate).is_err() {
        request.secret.zeroize();
        return Err(charge_failed_attempt(invitation));
    }
    let secret_check = invitation.consume_secret_hex(&request.secret);
    request.secret.zeroize();
    match secret_check {
        Ok(()) => {}
        Err(crate::invitation::InvitationError::AttemptsExceeded) => {
            return Err(InvitationFailure::AttemptsExceeded);
        }
        Err(crate::invitation::InvitationError::Expired) => return Err(InvitationFailure::Expired),
        Err(_) => {
            let _ = write_frame(
                &mut stream,
                &PairingResponse {
                    status: ResponseStatus::Rejected,
                    peer_alias: None,
                },
            );
            return Err(InvitationFailure::InvalidRequest);
        }
    }
    write_frame(
        &mut stream,
        &PairingResponse {
            status: ResponseStatus::Continue,
            peer_alias: Some(host_alias.to_owned()),
        },
    )
    .map_err(|_| InvitationFailure::Network)?;
    Ok(certificate)
}

fn charge_failed_attempt(invitation: &mut PairingInvitation) -> InvitationFailure {
    match invitation.record_failed_attempt() {
        Err(crate::invitation::InvitationError::AttemptsExceeded) => {
            InvitationFailure::AttemptsExceeded
        }
        Err(crate::invitation::InvitationError::Expired) => InvitationFailure::Expired,
        _ => InvitationFailure::InvalidRequest,
    }
}

fn join_worker(
    invitation: PairingInvitation,
    identity: PairingIdentity,
    alias: &str,
    state: SharedState,
    cancel: Arc<AtomicBool>,
) {
    let endpoint = invitation.endpoint();
    let timeout = invitation.remaining_validity().min(Duration::from_secs(15));
    if timeout.is_zero() {
        return fail(&state, "expired");
    }
    let config =
        match PairingIdentity::bootstrap_client_config(invitation.identity_ca_certificate_der()) {
            Ok(config) => config,
            Err(_) => return fail(&state, "invalid_invitation"),
        };
    let socket = match connect_interruptibly(&endpoint.into(), timeout, &cancel) {
        Ok(socket) => socket,
        Err(_) if cancel.load(Ordering::Acquire) => return,
        Err(_) => return fail(&state, "bootstrap_connect"),
    };
    if configure_socket(&socket).is_err() {
        return fail(&state, "bootstrap_socket_setup");
    }
    let mut bootstrap = match client_stream(socket, config) {
        Ok(stream) => stream,
        Err(_) => return fail(&state, "tls_verification_failed"),
    };
    let secret = zeroize::Zeroizing::new(invitation.secret_hex());
    let request = BootstrapRequestRef {
        secret: &secret,
        identity_ca_certificate_der_hex: encode_hex(identity.certificate_der()),
    };
    if write_sensitive_frame(&mut bootstrap, &request).is_err() {
        return fail(&state, "bootstrap_write");
    }
    let response: PairingResponse = match read_frame(&mut bootstrap)
        .and_then(|bytes| serde_json::from_slice(&bytes).map_err(invalid_data))
    {
        Ok(response) => response,
        Err(_) => return fail(&state, "invalid_response"),
    };
    if response.status != ResponseStatus::Continue {
        return fail(&state, "invitation_rejected");
    }
    drop(bootstrap);
    if cancel.load(Ordering::Acquire) {
        return;
    }
    let config = match identity.mutual_client_config(invitation.identity_ca_certificate_der()) {
        Ok(config) => config,
        Err(_) => return fail(&state, "tls_configuration"),
    };
    let socket = match connect_interruptibly(&endpoint.into(), IO_TIMEOUT, &cancel) {
        Ok(socket) => socket,
        Err(_) if cancel.load(Ordering::Acquire) => return,
        Err(_) => return fail(&state, "mutual_connect"),
    };
    if configure_socket(&socket).is_err() {
        return fail(&state, "mutual_socket_setup");
    }
    let mut stream = match client_stream(socket, config) {
        Ok(stream) => stream,
        Err(_) => return fail(&state, "host_authentication_failed"),
    };
    if write_frame(
        &mut stream,
        &PairingProof {
            alias: alias.to_owned(),
        },
    )
    .is_err()
    {
        return fail(&state, "mutual_proof_write");
    }
    let response: PairingResponse = match read_frame(&mut stream)
        .and_then(|bytes| serde_json::from_slice(&bytes).map_err(invalid_data))
    {
        Ok(response) => response,
        Err(_) => return fail(&state, "network"),
    };
    match response.status {
        ResponseStatus::Accepted => state.set(PairingSnapshot {
            status: PairingStatus::Paired,
            peer_alias: response.peer_alias,
            peer_ca_certificate_der_hex: Some(encode_hex(invitation.identity_ca_certificate_der())),
            error_code: None,
        }),
        ResponseStatus::Rejected => state.update(|value| value.status = PairingStatus::Rejected),
        ResponseStatus::Continue => fail(&state, "invalid_response"),
    }
}

enum InvitationFailure {
    AttemptsExceeded,
    Expired,
    Network,
    InvalidRequest,
}

fn accept_until(
    listener: &TcpListener,
    deadline: Instant,
    cancel: &AtomicBool,
) -> Option<TcpStream> {
    while !cancel.load(Ordering::Acquire) && Instant::now() < deadline {
        match listener.accept() {
            Ok((socket, _)) if configure_socket(&socket).is_ok() => return Some(socket),
            Ok(_) => continue,
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(ACCEPT_POLL);
            }
            Err(_) => return None,
        }
    }
    None
}

fn connect_interruptibly(
    address: &std::net::SocketAddr,
    timeout: Duration,
    cancel: &AtomicBool,
) -> io::Result<TcpStream> {
    if cancel.load(Ordering::Acquire) {
        return Err(io::Error::new(
            io::ErrorKind::Interrupted,
            "pairing was cancelled",
        ));
    }
    let socket = Socket::new(
        Domain::for_address(*address),
        Type::STREAM,
        Some(Protocol::TCP),
    )?;
    socket.set_nonblocking(true)?;
    match socket.connect(&(*address).into()) {
        Ok(()) => {}
        Err(error)
            if matches!(
                error.kind(),
                io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
            ) => {}
        Err(error) => return Err(error),
    }

    wait_for_connect(&socket, Instant::now() + timeout, cancel)?;
    socket.set_nonblocking(false)?;
    Ok(socket.into())
}

fn wait_for_connect(socket: &Socket, deadline: Instant, cancel: &AtomicBool) -> io::Result<()> {
    loop {
        if cancel.load(Ordering::Acquire) {
            return Err(io::Error::new(
                io::ErrorKind::Interrupted,
                "pairing was cancelled",
            ));
        }
        if let Some(error) = socket.take_error()? {
            return Err(error);
        }
        if socket.peer_addr().is_ok() {
            return Ok(());
        }
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "pairing connection timed out",
            ));
        }
        thread::sleep(remaining.min(ACCEPT_POLL));
    }
}

fn configure_socket(socket: &TcpStream) -> io::Result<()> {
    // The listening socket is polled in nonblocking mode. Accepted streams
    // must switch back to blocking IO before Rustls drives its handshake.
    socket.set_nonblocking(false)?;
    socket.set_read_timeout(Some(IO_TIMEOUT))?;
    socket.set_write_timeout(Some(IO_TIMEOUT))?;
    socket.set_nodelay(true)
}

type ClientStream = rustls::StreamOwned<rustls::ClientConnection, TcpStream>;
type ServerStream = rustls::StreamOwned<rustls::ServerConnection, TcpStream>;

fn client_stream(socket: TcpStream, config: Arc<ClientConfig>) -> io::Result<ClientStream> {
    let connection = rustls::ClientConnection::new(config, tls_server_name())
        .map_err(|_| io::Error::other("TLS client configuration failed"))?;
    Ok(rustls::StreamOwned::new(connection, socket))
}

fn server_stream(socket: TcpStream, config: Arc<ServerConfig>) -> io::Result<ServerStream> {
    let connection = rustls::ServerConnection::new(config)
        .map_err(|_| io::Error::other("TLS server configuration failed"))?;
    Ok(rustls::StreamOwned::new(connection, socket))
}

fn write_frame<T: Serialize>(stream: &mut impl Write, value: &T) -> io::Result<()> {
    let bytes = serde_json::to_vec(value).map_err(invalid_data)?;
    if bytes.is_empty() || bytes.len() > MAX_PAIRING_MESSAGE_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "pairing message exceeds limit",
        ));
    }
    stream.write_all(&(bytes.len() as u32).to_be_bytes())?;
    stream.write_all(&bytes)?;
    stream.flush()
}

fn write_sensitive_frame<T: Serialize>(stream: &mut impl Write, value: &T) -> io::Result<()> {
    let mut bytes = serde_json::to_vec(value).map_err(invalid_data)?;
    let result = if bytes.is_empty() || bytes.len() > MAX_PAIRING_MESSAGE_BYTES {
        Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "pairing message exceeds limit",
        ))
    } else {
        stream
            .write_all(&(bytes.len() as u32).to_be_bytes())
            .and_then(|()| stream.write_all(&bytes))
            .and_then(|()| stream.flush())
    };
    bytes.zeroize();
    result
}

fn read_frame(stream: &mut impl Read) -> io::Result<Vec<u8>> {
    let mut header = [0; 4];
    stream.read_exact(&mut header)?;
    let length = u32::from_be_bytes(header) as usize;
    if length == 0 || length > MAX_PAIRING_MESSAGE_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "pairing message exceeds limit",
        ));
    }
    let mut bytes = vec![0; length];
    stream.read_exact(&mut bytes)?;
    Ok(bytes)
}

fn decode_hex(value: &str, max_bytes: usize) -> Option<Vec<u8>> {
    if value.is_empty() || !value.len().is_multiple_of(2) || value.len() / 2 > max_bytes {
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
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| Some((digit(pair[0])? << 4) | digit(pair[1])?))
        .collect()
}

fn encode_hex(bytes: &[u8]) -> String {
    let mut encoded = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use fmt::Write as _;
        write!(&mut encoded, "{byte:02x}").expect("writing into String cannot fail");
    }
    encoded
}

fn invalid_data(error: impl std::error::Error + Send + Sync + 'static) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, error)
}

fn fail(state: &SharedState, error_code: &'static str) {
    state.set(PairingSnapshot {
        status: PairingStatus::Error,
        error_code: Some(error_code),
        ..PairingSnapshot::default()
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pairing::PairingIdentity;
    use aws_lc_rs::digest::{SHA256, digest};
    use std::{net::UdpSocket, sync::Mutex};

    static TRANSPORT_TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn cancelled_connect_returns_before_opening_a_socket() {
        let cancel = AtomicBool::new(true);
        let address = "192.168.1.1:1".parse().unwrap();
        let error = connect_interruptibly(&address, Duration::from_secs(15), &cancel)
            .expect_err("a cancelled pairing must not connect");
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
    }

    #[test]
    fn cancellation_interrupts_connection_polling() {
        let socket = Socket::new(Domain::IPV4, Type::STREAM, Some(Protocol::TCP)).unwrap();
        socket.set_nonblocking(true).unwrap();
        let cancel = Arc::new(AtomicBool::new(false));
        let signal = cancel.clone();
        let canceller = thread::spawn(move || {
            thread::sleep(Duration::from_millis(30));
            signal.store(true, Ordering::Release);
        });
        let started = Instant::now();
        let error = wait_for_connect(&socket, started + Duration::from_secs(15), &cancel)
            .expect_err("cancellation must interrupt a pending socket poll");
        canceller.join().unwrap();
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert!(started.elapsed() < Duration::from_secs(1));
    }

    // Explicit local-LAN test. UDP connect only asks the OS for a route and
    // sends no packet; all pairing TCP traffic stays on this machine/interface.
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
        Some(address)
    }

    fn exercise_pairing(approve: bool) {
        let _serial = TRANSPORT_TEST_LOCK.lock().unwrap();
        let address = private_interface_address()
            .expect("set MIRQUOVA_PAIRING_TEST_IPV4 to an available RFC1918 interface");
        let host_identity = PairingIdentity::generate().unwrap();
        let joining_identity = PairingIdentity::generate().unwrap();
        let host_ca = host_identity.certificate_der().to_vec();
        let joining_ca = joining_identity.certificate_der().to_vec();
        let fingerprint = digest(&SHA256, &host_ca);
        let host = HostSession::start(
            address,
            0,
            host_identity,
            "Host device",
            Duration::from_secs(30),
        )
        .expect("bind a pairing listener to the selected private interface");

        // A modified bearer secret is rejected through the TLS bootstrap while
        // leaving the invitation available for a legitimate single use.
        let mut wrong_payload = host.payload().to_owned();
        let secret_start = wrong_payload.find("\"secret\":\"").unwrap() + 10;
        let replacement = if wrong_payload.as_bytes()[secret_start] == b'0' {
            b'1'
        } else {
            b'0'
        };
        wrong_payload.replace_range(
            secret_start..secret_start + 1,
            &(replacement as char).to_string(),
        );
        let wrong_attempt = JoinSession::start(
            wrong_payload.as_bytes(),
            fingerprint.as_ref().try_into().unwrap(),
            PairingIdentity::generate().unwrap(),
            "Wrong secret",
        )
        .expect("a structurally valid invitation starts a bounded attempt");
        let deadline = Instant::now() + Duration::from_secs(5);
        while wrong_attempt.snapshot().status != PairingStatus::Error && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(20));
        }
        assert_eq!(wrong_attempt.snapshot().status, PairingStatus::Error);
        assert_eq!(
            wrong_attempt.snapshot().error_code,
            Some("invitation_rejected")
        );
        drop(wrong_attempt);
        assert_eq!(host.snapshot().status, PairingStatus::WaitingForPeer);

        let joining = JoinSession::start(
            host.payload().as_bytes(),
            fingerprint.as_ref().try_into().unwrap(),
            joining_identity,
            "Joining phone",
        )
        .expect("start the joiner with the displayed certificate fingerprint");

        let deadline = Instant::now() + Duration::from_secs(10);
        while host.snapshot().status != PairingStatus::AwaitingApproval && Instant::now() < deadline
        {
            thread::sleep(Duration::from_millis(20));
        }
        let pending = host.snapshot();
        assert_eq!(
            pending.status,
            PairingStatus::AwaitingApproval,
            "join status {:?}, join error {:?}, host error {:?}",
            joining.snapshot().status,
            joining.snapshot().error_code,
            pending.error_code,
        );
        assert_eq!(pending.peer_alias.as_deref(), Some("Joining phone"));
        assert_eq!(
            pending.peer_ca_certificate_der_hex.as_deref(),
            Some(encode_hex(&joining_ca).as_str())
        );

        assert!(if approve {
            host.approve()
        } else {
            host.reject()
        });
        let expected = if approve {
            PairingStatus::Paired
        } else {
            PairingStatus::Rejected
        };
        let deadline = Instant::now() + Duration::from_secs(5);
        while joining.snapshot().status != expected && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(20));
        }
        let joining_snapshot = joining.snapshot();
        assert_eq!(joining_snapshot.status, expected);
        assert_eq!(host.snapshot().status, expected);
        if approve {
            assert_eq!(
                joining_snapshot.peer_ca_certificate_der_hex.as_deref(),
                Some(encode_hex(&host_ca).as_str())
            );
        }

        drop(joining);
        drop(host);
    }

    fn exercise_competing_joiners() {
        let _serial = TRANSPORT_TEST_LOCK.lock().unwrap();
        let address = private_interface_address()
            .expect("set MIRQUOVA_PAIRING_TEST_IPV4 to an available RFC1918 interface");
        let host_identity = PairingIdentity::generate().unwrap();
        let fingerprint = digest(&SHA256, host_identity.certificate_der());
        let host = HostSession::start(
            address,
            0,
            host_identity,
            "Host device",
            Duration::from_secs(30),
        )
        .expect("bind a pairing listener to the selected private interface");
        let payload = host.payload().to_owned();

        let first = JoinSession::start(
            payload.as_bytes(),
            fingerprint.as_ref().try_into().unwrap(),
            PairingIdentity::generate().unwrap(),
            "First phone",
        )
        .unwrap();
        let second = JoinSession::start(
            payload.as_bytes(),
            fingerprint.as_ref().try_into().unwrap(),
            PairingIdentity::generate().unwrap(),
            "Second phone",
        )
        .unwrap();

        let deadline = Instant::now() + Duration::from_secs(10);
        while host.snapshot().status != PairingStatus::AwaitingApproval
            && !matches!(
                host.snapshot().status,
                PairingStatus::Error | PairingStatus::Expired
            )
            && Instant::now() < deadline
        {
            thread::sleep(Duration::from_millis(20));
        }
        assert!(
            host.snapshot().status == PairingStatus::AwaitingApproval,
            "one racing joiner should reach approval; host status {:?}",
            host.snapshot().status,
        );
        assert!(host.approve());

        let deadline = Instant::now() + Duration::from_secs(10);
        while !matches!(
            first.snapshot().status,
            PairingStatus::Paired
                | PairingStatus::Rejected
                | PairingStatus::Expired
                | PairingStatus::Stopped
                | PairingStatus::Error
        ) || !matches!(
            second.snapshot().status,
            PairingStatus::Paired
                | PairingStatus::Rejected
                | PairingStatus::Expired
                | PairingStatus::Stopped
                | PairingStatus::Error
        ) {
            if Instant::now() >= deadline {
                break;
            }
            thread::sleep(Duration::from_millis(20));
        }
        let paired_joiners = [first.snapshot(), second.snapshot()]
            .iter()
            .filter(|snapshot| snapshot.status == PairingStatus::Paired)
            .count();
        assert!(
            ![first.snapshot(), second.snapshot()]
                .iter()
                .any(|snapshot| snapshot.status == PairingStatus::Connecting),
            "joiners did not settle: first={:?}, second={:?}, host={:?}",
            first.snapshot().status,
            second.snapshot().status,
            host.snapshot().status
        );
        assert!(
            paired_joiners <= 1,
            "one invitation must not authenticate multiple joiners"
        );
        assert_eq!(host.snapshot().status, PairingStatus::Paired);
        assert_eq!(paired_joiners, 1);
        drop(first);
        drop(second);
        drop(host);
    }

    fn exercise_restart_invalidates_invitation() {
        let _serial = TRANSPORT_TEST_LOCK.lock().unwrap();
        let address = private_interface_address()
            .expect("set MIRQUOVA_PAIRING_TEST_IPV4 to an available RFC1918 interface");
        let identity = PairingIdentity::generate().unwrap();
        let host_certificate = identity.certificate_der().to_vec();
        let host_key = identity.private_key_pkcs8_der().to_vec();
        let fingerprint = digest(&SHA256, &host_certificate);
        let mut first_host =
            HostSession::start(address, 0, identity, "Host device", Duration::from_secs(30))
                .expect("bind the first pairing listener");
        let old_payload = first_host.payload().to_owned();
        let port = first_host.endpoint().port();
        first_host.stop();
        drop(first_host);

        let replacement_identity =
            PairingIdentity::from_stored(&host_certificate, &host_key).unwrap();
        let replacement_host = HostSession::start(
            address,
            port,
            replacement_identity,
            "Host device",
            Duration::from_secs(30),
        )
        .expect("restart the listener with the same persisted identity");
        let replay = JoinSession::start(
            old_payload.as_bytes(),
            fingerprint.as_ref().try_into().unwrap(),
            PairingIdentity::generate().unwrap(),
            "Replay attempt",
        )
        .unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        while replay.snapshot().status != PairingStatus::Error && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(20));
        }
        assert_eq!(replay.snapshot().status, PairingStatus::Error);
        assert_eq!(
            replay.snapshot().error_code,
            Some("invitation_rejected"),
            "the replacement listener must reject the old bearer secret"
        );
        assert_eq!(
            replacement_host.snapshot().status,
            PairingStatus::WaitingForPeer
        );
        drop(replay);
        drop(replacement_host);
    }

    #[test]
    fn join_rejects_a_wrong_fingerprint_before_opening_a_connection() {
        let identity = PairingIdentity::generate().unwrap();
        let invitation = crate::invitation::PairingInvitation::generate(
            SocketAddrV4::new(Ipv4Addr::new(192, 168, 1, 20), 45_833),
            identity.certificate_der(),
            Duration::from_secs(30),
        )
        .unwrap();
        let joiner = PairingIdentity::generate().unwrap();
        let wrong_fingerprint = [0; 32];
        let error = JoinSession::start(
            invitation.payload().as_bytes(),
            &wrong_fingerprint,
            joiner,
            "Joining phone",
        )
        .err();
        assert!(matches!(
            error,
            Some(PairingTransportError::FingerprintMismatch)
        ));
    }

    #[test]
    #[ignore = "explicit same-host private-interface TLS transport run; not physical-device validation"]
    fn local_private_interface_pairing_can_be_approved() {
        exercise_pairing(true);
    }

    #[test]
    #[ignore = "explicit same-host private-interface TLS transport run; not physical-device validation"]
    fn local_private_interface_pairing_can_be_rejected() {
        exercise_pairing(false);
    }

    #[test]
    #[ignore = "explicit same-host private-interface TLS transport run; not physical-device validation"]
    fn local_private_interface_pairing_can_be_used_once_under_racing_joiners() {
        exercise_competing_joiners();
    }

    #[test]
    #[ignore = "explicit same-host private-interface TLS transport run; not physical-device validation"]
    fn local_private_interface_pairing_restart_invalidates_old_invitation() {
        exercise_restart_invalidates_invitation();
    }
}
