//! Explicit, time-limited, discovery-only presence. No application listener.
use crate::discovery::SERVICE_TYPE;
use mdns_sd::{DaemonEvent, ServiceDaemon, ServiceInfo};
use serde::Serialize;
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

pub const VISIBILITY_DURATION: Duration = Duration::from_secs(120);

pub fn valid_alias(alias: &str) -> bool {
    !alias.trim().is_empty()
        && alias.len() <= 64
        && !alias.chars().any(|c| {
            c.is_control() || matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
        })
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PresenceStatus {
    #[default]
    Hidden,
    Starting,
    Visible,
    Stopping,
    Error,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct PresenceSnapshot {
    pub status: PresenceStatus,
    pub alias: Option<String>,
    pub remaining_seconds: u64,
    pub error: Option<String>,
    #[serde(skip)]
    deadline: Option<Instant>,
}

pub struct Presence {
    id: String,
    state: Arc<Mutex<PresenceSnapshot>>,
    cancel: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
}

impl Default for Presence {
    fn default() -> Self {
        Self {
            id: uuid::Uuid::new_v4().simple().to_string(),
            state: Arc::default(),
            cancel: Arc::new(AtomicBool::new(false)),
            worker: None,
        }
    }
}

impl Presence {
    pub fn fullname(&self) -> String {
        format!("Mirquova-{}.{}", self.id, SERVICE_TYPE)
    }

    pub fn snapshot(&self) -> PresenceSnapshot {
        let mut value = self.state.lock().unwrap_or_else(|e| e.into_inner()).clone();
        value.remaining_seconds = value
            .deadline
            .map(|deadline| deadline.saturating_duration_since(Instant::now()).as_secs())
            .unwrap_or(0);
        value
    }

    pub fn start(&mut self, alias: &str) -> bool {
        self.start_for(alias, VISIBILITY_DURATION)
    }

    fn start_for(&mut self, alias: &str, duration: Duration) -> bool {
        if !valid_alias(alias) || duration.is_zero() || duration > VISIBILITY_DURATION {
            return false;
        }
        if let Some(worker) = &self.worker
            && !worker.is_finished()
            && matches!(
                self.snapshot().status,
                PresenceStatus::Starting | PresenceStatus::Visible | PresenceStatus::Stopping
            )
        {
            return false;
        }
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
        self.cancel.store(false, Ordering::Release);
        *self.state.lock().unwrap_or_else(|e| e.into_inner()) = PresenceSnapshot {
            status: PresenceStatus::Starting,
            alias: Some(alias.trim().into()),
            ..PresenceSnapshot::default()
        };
        let state = Arc::clone(&self.state);
        let cancel = Arc::clone(&self.cancel);
        let id = self.id.clone();
        let alias = alias.trim().to_owned();
        match thread::Builder::new()
            .name("mirquova-presence".into())
            .spawn(move || {
                let result =
                    std::panic::catch_unwind(|| announce(&id, &alias, duration, &state, &cancel))
                        .unwrap_or_else(|_| Err("LAN visibility stopped unexpectedly.".into()));
                let mut value = state.lock().unwrap_or_else(|e| e.into_inner());
                *value = match result {
                    Ok(()) => PresenceSnapshot::default(),
                    Err(error) => PresenceSnapshot {
                        status: PresenceStatus::Error,
                        error: Some(error),
                        ..PresenceSnapshot::default()
                    },
                };
            }) {
            Ok(worker) => {
                self.worker = Some(worker);
                true
            }
            Err(_) => {
                *self.state.lock().unwrap_or_else(|e| e.into_inner()) = PresenceSnapshot {
                    status: PresenceStatus::Error,
                    error: Some("Could not start LAN visibility.".into()),
                    ..PresenceSnapshot::default()
                };
                false
            }
        }
    }

    pub fn hide(&self) {
        self.cancel.store(true, Ordering::Release);
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if matches!(
            state.status,
            PresenceStatus::Starting | PresenceStatus::Visible
        ) {
            state.status = PresenceStatus::Stopping;
        }
    }
}

impl Drop for Presence {
    fn drop(&mut self) {
        self.hide();
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

struct AnnouncementGuard {
    daemon: ServiceDaemon,
    fullname: String,
}
impl Drop for AnnouncementGuard {
    fn drop(&mut self) {
        if let Ok(removed) = self.daemon.unregister(&self.fullname) {
            let _ = removed.recv_timeout(Duration::from_secs(1));
        }
        if let Ok(stopped) = self.daemon.shutdown() {
            let _ = stopped.recv_timeout(Duration::from_secs(1));
        }
    }
}

fn announce(
    id: &str,
    alias: &str,
    duration: Duration,
    state: &Mutex<PresenceSnapshot>,
    cancel: &AtomicBool,
) -> Result<(), String> {
    let service = ServiceInfo::new(
        SERVICE_TYPE,
        &format!("Mirquova-{id}"),
        &format!("mirquova-{id}.local."),
        "",
        0,
        &[("protocol", "2"), ("phase", "presence"), ("name", alias)][..],
    )
    .map_err(|_| "Could not create a presence announcement.")?
    .enable_addr_auto();
    let fullname = service.get_fullname().to_owned();
    let daemon = ServiceDaemon::new().map_err(|_| "Could not initialize LAN visibility.")?;
    let _guard = AnnouncementGuard {
        daemon: daemon.clone(),
        fullname,
    };
    (|| {
        let monitor = daemon
            .monitor()
            .map_err(|_| "Could not monitor LAN visibility.")?;
        daemon
            .register(service)
            .map_err(|_| "Could not announce this device.")?;
        // Starting/probing time is included in the two-minute privacy limit.
        let deadline = Instant::now() + duration;
        while Instant::now() < deadline && !cancel.load(Ordering::Acquire) {
            match monitor.recv_timeout(Duration::from_millis(100)) {
                Ok(DaemonEvent::Announce(_, _)) => {
                    let mut value = state.lock().unwrap_or_else(|e| e.into_inner());
                    if !cancel.load(Ordering::Acquire) {
                        value.status = PresenceStatus::Visible;
                        value.deadline = Some(deadline);
                    }
                }
                Ok(DaemonEvent::Error(_)) => {
                    return Err("LAN visibility failed. Check local-network access.".into());
                }
                Err(_) if monitor.is_disconnected() => {
                    return Err("LAN visibility service disconnected.".into());
                }
                _ => {}
            }
        }
        Ok(())
    })()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn alias_rejects_empty_controls_bidi_and_oversized_utf8() {
        for alias in [
            "",
            "   ",
            "PC\nName",
            "PC\u{202e}Name",
            &"x".repeat(65),
            &"\u{1f600}".repeat(17),
        ] {
            assert!(!valid_alias(alias));
        }
        assert!(valid_alias("Living room laptop"));
    }
    #[test]
    fn default_is_hidden_and_session_identifiers_are_not_persistent_identities() {
        let a = Presence::default();
        let b = Presence::default();
        assert_eq!(a.snapshot().status, PresenceStatus::Hidden);
        assert_eq!(a.snapshot().alias, None);
        assert_ne!(a.fullname(), b.fullname());
        assert!(a.fullname().ends_with(SERVICE_TYPE));
    }
    #[test]
    fn invalid_start_does_not_create_a_worker_or_advertise() {
        let mut presence = Presence::default();
        assert!(!presence.start("\n"));
        assert!(presence.worker.is_none());
        assert!(!presence.start_for("PC", Duration::from_secs(121)));
        assert!(!presence.start_for("PC", Duration::ZERO));
        assert_eq!(presence.snapshot().status, PresenceStatus::Hidden);
    }
    #[test]
    #[ignore = "explicit real-network lifecycle test; not a fixture or device validation"]
    fn network_presence_expires_and_hides() {
        let mut presence = Presence::default();
        assert!(presence.start("Lifecycle test"));
        let deadline = Instant::now() + Duration::from_secs(5);
        while presence.snapshot().status == PresenceStatus::Starting && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(50));
        }
        assert_eq!(presence.snapshot().status, PresenceStatus::Visible);
        assert!(!presence.start("Duplicate"));
        presence.hide();
        let deadline = Instant::now() + Duration::from_secs(5);
        while presence.snapshot().status == PresenceStatus::Stopping && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(50));
        }
        assert_eq!(presence.snapshot().status, PresenceStatus::Hidden);
        assert!(presence.start_for("Expiry test", Duration::from_secs(2)));
        let deadline = Instant::now() + Duration::from_secs(5);
        while matches!(
            presence.snapshot().status,
            PresenceStatus::Starting | PresenceStatus::Visible
        ) && Instant::now() < deadline
        {
            thread::sleep(Duration::from_millis(50));
        }
        assert_eq!(presence.snapshot().status, PresenceStatus::Hidden);
        assert_eq!(presence.snapshot().alias, None);
        assert_eq!(VISIBILITY_DURATION.as_secs(), 120);
    }
    #[test]
    #[ignore = "explicit same-host network test; no two-device validation"]
    fn network_presence_is_discovered_without_a_transport_endpoint() {
        use crate::discovery::{Discovery, ScanStatus};
        let mut presence = Presence::default();
        assert!(presence.start("Presence integration"));
        let deadline = Instant::now() + Duration::from_secs(5);
        while presence.snapshot().status == PresenceStatus::Starting && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(50));
        }
        assert_eq!(presence.snapshot().status, PresenceStatus::Visible);
        let mut browser = Discovery::default();
        assert!(browser.start());
        let deadline = Instant::now() + Duration::from_secs(9);
        while matches!(browser.snapshot().status, ScanStatus::Scanning) && Instant::now() < deadline
        {
            thread::sleep(Duration::from_millis(50));
        }
        assert!(matches!(browser.snapshot().status, ScanStatus::Complete));
        let snapshot = browser.snapshot();
        let peer = snapshot
            .peers
            .get(&presence.fullname())
            .expect("Real presence announcement must resolve");
        assert_eq!(peer.name, "Presence integration");
        assert_eq!(peer.port, 0);
        assert!(!peer.verified);
        presence.hide();
    }
}
