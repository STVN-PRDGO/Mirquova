//! Process-wide discovery/presence ABI v2. No callbacks cross threads or trust boundary.
use crate::{
    discovery::Discovery,
    pairing::PairingIdentity,
    pairing_transport::{HostSession, JoinSession, PairingSnapshot},
    presence::Presence,
    transfer::{ReceiveSession, SendSession, TransferSnapshot, decode_hex},
};
use std::{
    ffi::{CStr, CString, c_char},
    ptr,
    sync::{Mutex, OnceLock},
};
use zeroize::Zeroize;

#[derive(Default)]
struct Runtime {
    discovery: Discovery,
    presence: Presence,
}

fn runtime() -> &'static Mutex<Runtime> {
    static INSTANCE: OnceLock<Mutex<Runtime>> = OnceLock::new();
    INSTANCE.get_or_init(|| Mutex::new(Runtime::default()))
}

#[derive(Default)]
struct PairingRuntime {
    active: Option<ActivePairing>,
}

enum ActivePairing {
    Host(HostSession),
    Join(JoinSession),
}

impl ActivePairing {
    fn stop(&mut self) {
        match self {
            Self::Host(session) => session.stop(),
            Self::Join(session) => session.stop(),
        }
    }

    fn snapshot(&self) -> PairingSnapshot {
        match self {
            Self::Host(session) => session.snapshot(),
            Self::Join(session) => session.snapshot(),
        }
    }
}

fn pairing_runtime() -> &'static Mutex<PairingRuntime> {
    static INSTANCE: OnceLock<Mutex<PairingRuntime>> = OnceLock::new();
    INSTANCE.get_or_init(|| Mutex::new(PairingRuntime::default()))
}

#[derive(Default)]
struct TransferRuntime {
    active: Option<ActiveTransfer>,
}

enum ActiveTransfer {
    Receive(ReceiveSession),
    Send(SendSession),
}

impl ActiveTransfer {
    fn stop(&mut self) {
        match self {
            Self::Receive(session) => session.stop(),
            Self::Send(session) => session.stop(),
        }
    }

    fn snapshot(&self) -> TransferSnapshot {
        match self {
            Self::Receive(session) => session.snapshot(),
            Self::Send(session) => session.snapshot(),
        }
    }
}

fn transfer_runtime() -> &'static Mutex<TransferRuntime> {
    static INSTANCE: OnceLock<Mutex<TransferRuntime>> = OnceLock::new();
    INSTANCE.get_or_init(|| Mutex::new(TransferRuntime::default()))
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_abi_version() -> u32 {
    2
}

#[repr(C)]
pub struct MqPairingIdentity {
    certificate_der: *mut u8,
    certificate_len: u32,
    private_key_pkcs8_der: *mut u8,
    private_key_len: u32,
}

/// Creates an identity for immediate persistence in OS-backed secure storage.
/// Both buffers contain secret-bearing data and must never be logged.
#[unsafe(no_mangle)]
pub extern "C" fn mq_pairing_identity_create() -> *mut MqPairingIdentity {
    std::panic::catch_unwind(|| {
        let Ok(identity) = PairingIdentity::generate() else {
            return ptr::null_mut();
        };
        let certificate = identity.certificate_der().to_vec().into_boxed_slice();
        let private_key = identity.private_key_pkcs8_der().to_vec().into_boxed_slice();
        let certificate_len = certificate.len() as u32;
        let private_key_len = private_key.len() as u32;
        let certificate_der = Box::into_raw(certificate) as *mut u8;
        let private_key_pkcs8_der = Box::into_raw(private_key) as *mut u8;
        Box::into_raw(Box::new(MqPairingIdentity {
            certificate_der,
            certificate_len,
            private_key_pkcs8_der,
            private_key_len,
        }))
    })
    .unwrap_or(ptr::null_mut())
}

/// # Safety
/// `identity` must be null or an unfreed pointer returned by
/// `mq_pairing_identity_create`; free it exactly once with this function.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mq_pairing_identity_free(identity: *mut MqPairingIdentity) {
    if identity.is_null() {
        return;
    }
    let _ = std::panic::catch_unwind(|| unsafe {
        let identity = Box::from_raw(identity);
        zeroize_boxed_bytes(identity.certificate_der, identity.certificate_len);
        zeroize_boxed_bytes(identity.private_key_pkcs8_der, identity.private_key_len);
    });
}

/// # Safety
/// Both pointers must reference their declared readable byte lengths for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mq_pairing_identity_validate(
    certificate_der: *const u8,
    certificate_len: u32,
    private_key_pkcs8_der: *const u8,
    private_key_len: u32,
) -> i32 {
    if certificate_der.is_null()
        || private_key_pkcs8_der.is_null()
        || certificate_len == 0
        || certificate_len > 512
        || private_key_len == 0
        || private_key_len > 4096
    {
        return 0;
    }
    std::panic::catch_unwind(|| {
        let certificate =
            unsafe { std::slice::from_raw_parts(certificate_der, certificate_len as usize) };
        let private_key =
            unsafe { std::slice::from_raw_parts(private_key_pkcs8_der, private_key_len as usize) };
        i32::from(PairingIdentity::from_stored(certificate, private_key).is_ok())
    })
    .unwrap_or(-1)
}

/// # Safety
/// All pointers must reference their declared readable byte lengths for this call.
/// The returned invitation JSON contains a bearer secret and must be freed with
/// `mq_string_free`; never log or persist it outside the active session.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mq_pairing_host_start(
    local_ipv4: *const u8,
    address_len: u32,
    port: u16,
    host_alias: *const u8,
    alias_len: u32,
    certificate_der: *const u8,
    certificate_len: u32,
    private_key_pkcs8_der: *const u8,
    private_key_len: u32,
) -> *mut c_char {
    if local_ipv4.is_null()
        || address_len == 0
        || address_len > 15
        || host_alias.is_null()
        || alias_len == 0
        || alias_len > 64
        || certificate_der.is_null()
        || certificate_len == 0
        || certificate_len > 512
        || private_key_pkcs8_der.is_null()
        || private_key_len == 0
        || private_key_len > 4096
    {
        return ptr::null_mut();
    }
    std::panic::catch_unwind(|| {
        let address = unsafe { std::slice::from_raw_parts(local_ipv4, address_len as usize) };
        let alias = unsafe { std::slice::from_raw_parts(host_alias, alias_len as usize) };
        let certificate =
            unsafe { std::slice::from_raw_parts(certificate_der, certificate_len as usize) };
        let private_key =
            unsafe { std::slice::from_raw_parts(private_key_pkcs8_der, private_key_len as usize) };
        let (Ok(address), Ok(alias)) = (std::str::from_utf8(address), std::str::from_utf8(alias))
        else {
            return ptr::null_mut();
        };
        let (Ok(address), Ok(identity)) = (
            address.parse(),
            PairingIdentity::from_stored(certificate, private_key),
        ) else {
            return ptr::null_mut();
        };
        let Ok(mut session) = HostSession::start(
            address,
            port,
            identity,
            alias,
            std::time::Duration::from_secs(120),
        ) else {
            return ptr::null_mut();
        };
        let Ok(payload) = CString::new(session.payload()) else {
            session.stop();
            return ptr::null_mut();
        };
        let Ok(mut manager) = pairing_runtime().lock() else {
            session.stop();
            return ptr::null_mut();
        };
        if let Some(mut active) = manager.active.take() {
            active.stop();
        }
        manager.active = Some(ActivePairing::Host(session));
        payload.into_raw()
    })
    .unwrap_or(ptr::null_mut())
}

/// # Safety
/// All pointers must reference their declared readable byte lengths for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mq_pairing_join(
    invitation_payload: *const u8,
    payload_len: u32,
    confirmed_fingerprint_sha256: *const u8,
    identity_ca_certificate_der: *const u8,
    certificate_len: u32,
    private_key_pkcs8_der: *const u8,
    private_key_len: u32,
    alias: *const u8,
    alias_len: u32,
) -> i32 {
    if invitation_payload.is_null()
        || payload_len == 0
        || payload_len > 2048
        || confirmed_fingerprint_sha256.is_null()
        || identity_ca_certificate_der.is_null()
        || certificate_len == 0
        || certificate_len > 512
        || private_key_pkcs8_der.is_null()
        || private_key_len == 0
        || private_key_len > 4096
        || alias.is_null()
        || alias_len == 0
        || alias_len > 64
    {
        return 0;
    }
    std::panic::catch_unwind(|| {
        let payload =
            unsafe { std::slice::from_raw_parts(invitation_payload, payload_len as usize) };
        let fingerprint = unsafe { std::slice::from_raw_parts(confirmed_fingerprint_sha256, 32) };
        let certificate = unsafe {
            std::slice::from_raw_parts(identity_ca_certificate_der, certificate_len as usize)
        };
        let private_key =
            unsafe { std::slice::from_raw_parts(private_key_pkcs8_der, private_key_len as usize) };
        let alias = unsafe { std::slice::from_raw_parts(alias, alias_len as usize) };
        let (Ok(identity), Ok(alias), Ok(fingerprint)) = (
            PairingIdentity::from_stored(certificate, private_key),
            std::str::from_utf8(alias),
            <&[u8; 32]>::try_from(fingerprint),
        ) else {
            return 0;
        };
        let Ok(session) = JoinSession::start(payload, fingerprint, identity, alias) else {
            return 0;
        };
        let Ok(mut manager) = pairing_runtime().lock() else {
            return 0;
        };
        if let Some(mut active) = manager.active.take() {
            active.stop();
        }
        manager.active = Some(ActivePairing::Join(session));
        1
    })
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_pairing_approve() -> i32 {
    std::panic::catch_unwind(|| {
        pairing_runtime()
            .lock()
            .map(|manager| match &manager.active {
                Some(ActivePairing::Host(session)) => i32::from(session.approve()),
                _ => 0,
            })
            .unwrap_or(-1)
    })
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_pairing_reject() -> i32 {
    std::panic::catch_unwind(|| {
        pairing_runtime()
            .lock()
            .map(|manager| match &manager.active {
                Some(ActivePairing::Host(session)) => i32::from(session.reject()),
                _ => 0,
            })
            .unwrap_or(-1)
    })
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_pairing_snapshot() -> *mut c_char {
    std::panic::catch_unwind(|| {
        let snapshot = pairing_runtime()
            .lock()
            .map(|manager| {
                manager
                    .active
                    .as_ref()
                    .map(ActivePairing::snapshot)
                    .unwrap_or_default()
            })
            .unwrap_or_default();
        serde_json::to_string(&snapshot)
            .ok()
            .and_then(|json| CString::new(json).ok())
            .map(CString::into_raw)
            .unwrap_or(ptr::null_mut())
    })
    .unwrap_or(ptr::null_mut())
}

#[derive(serde::Deserialize)]
struct ReceiveStartConfig {
    local_ipv4: String,
    port: u16,
    destination_directory: String,
    peer_ca_certificates_der_hex: Vec<String>,
}

#[derive(serde::Deserialize)]
struct SendStartConfig {
    peer_ipv4: String,
    port: u16,
    peer_ca_certificate_der_hex: String,
    paths: Vec<String>,
}

fn read_config<T: serde::de::DeserializeOwned>(bytes: *const u8, length: u32) -> Option<T> {
    if bytes.is_null() || length == 0 || length > 256 * 1024 {
        return None;
    }
    let bytes = unsafe { std::slice::from_raw_parts(bytes, length as usize) };
    let text = std::str::from_utf8(bytes).ok()?;
    serde_json::from_str(text).ok()
}

fn load_identity(
    certificate_der: *const u8,
    certificate_len: u32,
    private_key_pkcs8_der: *const u8,
    private_key_len: u32,
) -> Option<PairingIdentity> {
    if certificate_der.is_null()
        || certificate_len == 0
        || certificate_len > 512
        || private_key_pkcs8_der.is_null()
        || private_key_len == 0
        || private_key_len > 4096
    {
        return None;
    }
    let certificate =
        unsafe { std::slice::from_raw_parts(certificate_der, certificate_len as usize) };
    let private_key =
        unsafe { std::slice::from_raw_parts(private_key_pkcs8_der, private_key_len as usize) };
    PairingIdentity::from_stored(certificate, private_key).ok()
}

fn replace_transfer(active: ActiveTransfer) -> bool {
    let Ok(mut manager) = transfer_runtime().lock() else {
        return false;
    };
    if let Some(mut current) = manager.active.take() {
        current.stop();
    }
    manager.active = Some(active);
    true
}

/// # Safety
/// Pointers must reference their declared readable byte lengths for this call.
/// The private key is used only to start the listener and is not retained in a snapshot.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mq_transfer_receive_start(
    config_json: *const u8,
    config_len: u32,
    certificate_der: *const u8,
    certificate_len: u32,
    private_key_pkcs8_der: *const u8,
    private_key_len: u32,
) -> i32 {
    std::panic::catch_unwind(|| {
        let Some(config) = read_config::<ReceiveStartConfig>(config_json, config_len) else {
            return 0;
        };
        let Some(identity) = load_identity(
            certificate_der,
            certificate_len,
            private_key_pkcs8_der,
            private_key_len,
        ) else {
            return 0;
        };
        let Ok(address) = config.local_ipv4.parse() else {
            return 0;
        };
        let mut peers = Vec::new();
        if config.peer_ca_certificates_der_hex.is_empty()
            || config.peer_ca_certificates_der_hex.len() > 32
        {
            return 0;
        }
        for hex in &config.peer_ca_certificates_der_hex {
            let Some(certificate) = decode_hex(hex) else {
                return 0;
            };
            if certificate.is_empty() || certificate.len() > 512 {
                return 0;
            }
            peers.push(certificate);
        }
        let Ok(session) = ReceiveSession::start(
            address,
            config.port,
            identity,
            &peers,
            std::path::Path::new(&config.destination_directory),
        ) else {
            return 0;
        };
        i32::from(replace_transfer(ActiveTransfer::Receive(session)))
    })
    .unwrap_or(-1)
}

/// # Safety
/// Pointers must reference their declared readable byte lengths for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mq_transfer_send_start(
    config_json: *const u8,
    config_len: u32,
    certificate_der: *const u8,
    certificate_len: u32,
    private_key_pkcs8_der: *const u8,
    private_key_len: u32,
) -> i32 {
    std::panic::catch_unwind(|| {
        let Some(config) = read_config::<SendStartConfig>(config_json, config_len) else {
            return 0;
        };
        let Some(identity) = load_identity(
            certificate_der,
            certificate_len,
            private_key_pkcs8_der,
            private_key_len,
        ) else {
            return 0;
        };
        let Ok(address) = config.peer_ipv4.parse::<std::net::Ipv4Addr>() else {
            return 0;
        };
        let Some(peer_ca) = decode_hex(&config.peer_ca_certificate_der_hex) else {
            return 0;
        };
        if peer_ca.is_empty() || peer_ca.len() > 512 || config.paths.len() > 32 {
            return 0;
        }
        let paths = config
            .paths
            .iter()
            .map(std::path::PathBuf::from)
            .collect::<Vec<_>>();
        let Ok(session) = SendSession::start(address, config.port, identity, &peer_ca, &paths)
        else {
            return 0;
        };
        i32::from(replace_transfer(ActiveTransfer::Send(session)))
    })
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_transfer_approve() -> i32 {
    std::panic::catch_unwind(|| {
        transfer_runtime()
            .lock()
            .map(|manager| match &manager.active {
                Some(ActiveTransfer::Receive(session)) => i32::from(session.approve()),
                _ => 0,
            })
            .unwrap_or(-1)
    })
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_transfer_reject() -> i32 {
    std::panic::catch_unwind(|| {
        transfer_runtime()
            .lock()
            .map(|manager| match &manager.active {
                Some(ActiveTransfer::Receive(session)) => i32::from(session.reject()),
                _ => 0,
            })
            .unwrap_or(-1)
    })
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_transfer_snapshot() -> *mut c_char {
    std::panic::catch_unwind(|| {
        let snapshot = transfer_runtime()
            .lock()
            .map(|manager| {
                manager
                    .active
                    .as_ref()
                    .map(ActiveTransfer::snapshot)
                    .unwrap_or_default()
            })
            .unwrap_or_default();
        serde_json::to_string(&snapshot)
            .ok()
            .and_then(|json| CString::new(json).ok())
            .map(CString::into_raw)
            .unwrap_or(ptr::null_mut())
    })
    .unwrap_or(ptr::null_mut())
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_transfer_stop() {
    let _ = std::panic::catch_unwind(|| {
        if let Ok(mut manager) = transfer_runtime().lock()
            && let Some(mut active) = manager.active.take()
        {
            active.stop();
        }
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_pairing_stop() {
    let _ = std::panic::catch_unwind(|| {
        if let Ok(mut manager) = pairing_runtime().lock()
            && let Some(mut active) = manager.active.take()
        {
            active.stop();
        }
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_discovery_start() -> i32 {
    std::panic::catch_unwind(|| {
        runtime()
            .lock()
            .map(|mut d| i32::from(d.discovery.start()))
            .unwrap_or(-1)
    })
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_discovery_stop() {
    let _ = std::panic::catch_unwind(|| {
        if let Ok(d) = runtime().lock() {
            d.discovery.stop();
        }
    });
}

/// Returns an owned UTF-8 JSON snapshot or null on failure.
#[unsafe(no_mangle)]
pub extern "C" fn mq_discovery_snapshot() -> *mut c_char {
    std::panic::catch_unwind(|| {
        let Ok(d) = runtime().lock() else {
            return ptr::null_mut();
        };
        serde_json::to_string(&{
            let snapshot = d.discovery.snapshot().without_self(&d.presence.fullname());
            let mut value = serde_json::to_value(snapshot).unwrap_or(serde_json::Value::Null);
            value["presence"] =
                serde_json::to_value(d.presence.snapshot()).unwrap_or(serde_json::Value::Null);
            value
        })
        .ok()
        .and_then(|json| CString::new(json).ok())
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
    })
    .unwrap_or(ptr::null_mut())
}

/// # Safety
/// alias must reference alias_len readable bytes for this call. No ownership transfers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mq_presence_start(alias: *const u8, alias_len: u32) -> i32 {
    if alias.is_null() || alias_len == 0 || alias_len > 64 {
        return 0;
    }
    std::panic::catch_unwind(|| {
        let bytes = unsafe { std::slice::from_raw_parts(alias, alias_len as usize) };
        let Ok(alias) = std::str::from_utf8(bytes) else {
            return 0;
        };
        runtime()
            .lock()
            .map(|mut d| i32::from(d.presence.start(alias)))
            .unwrap_or(-1)
    })
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_presence_stop() {
    let _ = std::panic::catch_unwind(|| {
        if let Ok(d) = runtime().lock() {
            d.presence.hide();
        }
    });
}

/// # Safety
/// `value` must be null or an unfreed pointer returned by mq_discovery_snapshot.
/// Free exactly once through this function, never with Dart/C allocators.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mq_string_free(value: *mut c_char) {
    if !value.is_null() {
        let _ = std::panic::catch_unwind(|| unsafe {
            let length = CStr::from_ptr(value).to_bytes_with_nul().len();
            std::slice::from_raw_parts_mut(value.cast::<u8>(), length).zeroize();
            drop(CString::from_raw(value));
        });
    }
}

unsafe fn zeroize_boxed_bytes(value: *mut u8, length: u32) {
    if value.is_null() || length == 0 {
        return;
    }
    let slice = ptr::slice_from_raw_parts_mut(value, length as usize);
    unsafe {
        (&mut *slice).zeroize();
        drop(Box::from_raw(slice));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    #[test]
    fn snapshots_use_the_documented_allocator_and_version() {
        assert_eq!(mq_abi_version(), 2);
        for _ in 0..128 {
            let pointer = mq_discovery_snapshot();
            assert!(!pointer.is_null());
            let value: serde_json::Value =
                serde_json::from_str(unsafe { CStr::from_ptr(pointer) }.to_str().unwrap()).unwrap();
            assert_eq!(value["abi_version"], 2);
            unsafe {
                mq_string_free(pointer);
            }
        }
        unsafe {
            mq_string_free(std::ptr::null_mut());
        }
    }

    #[test]
    fn pairing_identity_ffi_returns_valid_key_material_without_debugging_it() {
        let pointer = mq_pairing_identity_create();
        assert!(!pointer.is_null());
        let identity = unsafe { &*pointer };
        let certificate = unsafe {
            std::slice::from_raw_parts(identity.certificate_der, identity.certificate_len as usize)
        };
        let private_key = unsafe {
            std::slice::from_raw_parts(
                identity.private_key_pkcs8_der,
                identity.private_key_len as usize,
            )
        };
        assert!(!certificate.is_empty());
        assert!(!private_key.is_empty());
        assert_eq!(
            unsafe {
                mq_pairing_identity_validate(
                    certificate.as_ptr(),
                    certificate.len() as u32,
                    private_key.as_ptr(),
                    private_key.len() as u32,
                )
            },
            1
        );
        unsafe {
            mq_pairing_identity_free(pointer);
        }
    }
}
