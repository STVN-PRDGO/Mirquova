//! Process-wide discovery/presence ABI v2. No callbacks cross threads or trust boundary.
use crate::{discovery::Discovery, presence::Presence};
use std::{
    ffi::{CString, c_char},
    ptr,
    sync::{Mutex, OnceLock},
};

#[derive(Default)]
struct Runtime {
    discovery: Discovery,
    presence: Presence,
}

fn runtime() -> &'static Mutex<Runtime> {
    static INSTANCE: OnceLock<Mutex<Runtime>> = OnceLock::new();
    INSTANCE.get_or_init(|| Mutex::new(Runtime::default()))
}

#[unsafe(no_mangle)]
pub extern "C" fn mq_abi_version() -> u32 {
    2
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
        unsafe {
            drop(CString::from_raw(value));
        }
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
}
