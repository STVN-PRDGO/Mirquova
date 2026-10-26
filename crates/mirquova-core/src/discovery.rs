use mdns_sd::{DaemonEvent, ResolvedService, ServiceDaemon, ServiceEvent};
use serde::Serialize;
use std::{
    collections::BTreeMap,
    net::Ipv4Addr,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

pub const SERVICE_TYPE: &str = "_mirq-presence._tcp.local.";
pub const MAX_PEERS: usize = 128;
pub const SCAN_DURATION: Duration = Duration::from_secs(6);

/// Only RFC1918 IPv4 is supported in this first discovery spike.
/// No public, loopback, multicast, unspecified or IPv6 endpoints are accepted.
pub fn is_lan_address(ip: Ipv4Addr) -> bool {
    ip.is_private() && !ip.is_broadcast() && !ip.is_unspecified()
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct Candidate {
    pub id: String,
    pub name: String,
    pub addresses: Vec<String>,
    pub port: u16,
    pub verified: bool,
}

pub fn candidate_from_service(info: &ResolvedService) -> Option<Candidate> {
    if info.ty_domain != SERVICE_TYPE
        || info.get_property_val_str("protocol") != Some("2")
        || info.get_property_val_str("phase") != Some("presence")
        || info.port != 0
        || info.fullname.len() > 255
    {
        return None;
    }
    let mut addresses: Vec<_> = info
        .get_addresses_v4()
        .into_iter()
        .filter(|ip| is_lan_address(*ip))
        .map(|ip| ip.to_string())
        .collect();
    addresses.sort();
    addresses.truncate(16);
    if addresses.is_empty() {
        return None;
    }
    let name = info
        .get_property_val_str("name")
        .unwrap_or("Nearby device")
        .chars()
        .filter(|c| {
            !c.is_control() && !matches!(*c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
        })
        .take(64)
        .collect::<String>();
    Some(Candidate {
        id: info.fullname.clone(),
        name: if name.trim().is_empty() {
            "Nearby device".into()
        } else {
            name
        },
        addresses,
        port: info.port,
        verified: false,
    })
}

#[derive(Clone, Debug, Serialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ScanStatus {
    #[default]
    Idle,
    Scanning,
    Complete,
    Stopped,
    Error,
}

#[derive(Clone, Debug, Serialize, Default)]
pub struct Snapshot {
    pub abi_version: u32,
    pub status: ScanStatus,
    pub peers: BTreeMap<String, Candidate>,
    pub error: Option<String>,
}

impl Snapshot {
    pub(crate) fn without_self(mut self, fullname: &str) -> Self {
        self.peers.remove(fullname);
        self
    }
    fn apply(&mut self, event: ServiceEvent) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                if let Some(peer) = candidate_from_service(&info) {
                    if self.peers.len() < MAX_PEERS || self.peers.contains_key(&peer.id) {
                        self.peers.insert(peer.id.clone(), peer);
                    }
                } else {
                    // A now-invalid record must not leave an earlier valid candidate behind.
                    self.peers.remove(&info.fullname);
                }
            }
            ServiceEvent::ServiceRemoved(_, id) => {
                self.peers.remove(&id);
            }
            _ => {}
        }
    }
}

pub struct Discovery {
    state: Arc<Mutex<Snapshot>>,
    cancel: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
}

impl Default for Discovery {
    fn default() -> Self {
        Self {
            state: Arc::new(Mutex::new(Snapshot {
                abi_version: 2,
                ..Snapshot::default()
            })),
            cancel: Arc::new(AtomicBool::new(false)),
            worker: None,
        }
    }
}

impl Discovery {
    pub fn snapshot(&self) -> Snapshot {
        self.state.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }

    /// Starting while an earlier scan is active is rejected, never duplicated.
    pub fn start(&mut self) -> bool {
        if let Some(worker) = &self.worker
            && !worker.is_finished()
            && matches!(self.snapshot().status, ScanStatus::Scanning)
        {
            return false;
        }
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
        self.cancel.store(false, Ordering::Release);
        *self.state.lock().unwrap_or_else(|e| e.into_inner()) = Snapshot {
            abi_version: 2,
            status: ScanStatus::Scanning,
            ..Snapshot::default()
        };
        let state = Arc::clone(&self.state);
        let cancel = Arc::clone(&self.cancel);
        match thread::Builder::new()
            .name("mirquova-discovery".into())
            .spawn(move || {
                let result = std::panic::catch_unwind(|| browse(&state, &cancel))
                    .unwrap_or_else(|_| Err("Discovery worker stopped unexpectedly.".into()));
                let mut current = state.lock().unwrap_or_else(|e| e.into_inner());
                match result {
                    Ok(()) => {
                        current.status = if cancel.load(Ordering::Acquire) {
                            ScanStatus::Stopped
                        } else {
                            ScanStatus::Complete
                        }
                    }
                    Err(message) => {
                        current.status = ScanStatus::Error;
                        current.error = Some(message);
                    }
                }
            }) {
            Ok(worker) => {
                self.worker = Some(worker);
                true
            }
            Err(_) => {
                let mut current = self.state.lock().unwrap_or_else(|e| e.into_inner());
                current.status = ScanStatus::Error;
                current.error = Some("Could not start discovery worker.".into());
                false
            }
        }
    }

    pub fn stop(&self) {
        self.cancel.store(true, Ordering::Release);
    }
}

impl Drop for Discovery {
    fn drop(&mut self) {
        self.stop();
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

fn browse(state: &Mutex<Snapshot>, cancel: &AtomicBool) -> Result<(), String> {
    let daemon = ServiceDaemon::new().map_err(|_| "Could not initialize LAN discovery.")?;
    let result = (|| {
        let monitor = daemon
            .monitor()
            .map_err(|_| "Could not monitor multicast discovery.")?;
        let events = daemon
            .browse(SERVICE_TYPE)
            .map_err(|_| "Could not browse the LAN.")?;
        let deadline = Instant::now() + SCAN_DURATION;
        while Instant::now() < deadline && !cancel.load(Ordering::Acquire) {
            while let Ok(event) = monitor.try_recv() {
                if matches!(event, DaemonEvent::Error(_)) {
                    return Err("Multicast discovery failed. Try a manual LAN address.".into());
                }
            }
            match events.recv_timeout(Duration::from_millis(100)) {
                Ok(event) => state.lock().unwrap_or_else(|e| e.into_inner()).apply(event),
                Err(_) if events.is_disconnected() => {
                    return Err("Discovery service disconnected. Try scanning again.".into());
                }
                Err(_) => {}
            }
        }
        let _ = daemon.stop_browse(SERVICE_TYPE);
        Ok(())
    })();
    // Always shut down, including errors, so each scan releases its sockets/thread.
    if let Ok(shutdown) = daemon.shutdown() {
        let _ = shutdown.recv_timeout(Duration::from_secs(1));
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use mdns_sd::ServiceInfo;

    fn resolved(info: ResolvedService) -> ServiceEvent {
        ServiceEvent::ServiceResolved(Box::new(info))
    }

    fn service(ip: &str, protocol: &str, port: u16, name: &str) -> ResolvedService {
        ServiceInfo::new(
            SERVICE_TYPE,
            "fixture",
            "fixture.local.",
            ip,
            port,
            &[
                ("protocol", protocol),
                ("phase", "presence"),
                ("name", name),
            ][..],
        )
        .unwrap()
        .as_resolved_service()
    }

    #[test]
    fn discovery_never_authenticates_advertised_identity() {
        let peer = candidate_from_service(&service("192.168.2.4", "2", 0, "Office PC")).unwrap();
        assert!(!peer.verified);
        assert_eq!(peer.name, "Office PC");
    }
    #[test]
    fn rejects_public_localhost_multicast_and_missing_protocol() {
        for ip in [
            "8.8.8.8",
            "127.0.0.1",
            "0.0.0.0",
            "224.0.0.251",
            "169.254.1.2",
        ] {
            assert!(candidate_from_service(&service(ip, "2", 0, "Peer")).is_none());
        }
        assert!(candidate_from_service(&service("10.0.0.2", "99", 0, "Peer")).is_none());
        assert!(candidate_from_service(&service("10.0.0.2", "2", 45833, "Peer")).is_none());
    }
    #[test]
    fn bounds_and_cleans_untrusted_display_names() {
        let peer = candidate_from_service(&service(
            "10.1.2.3",
            "2",
            0,
            &format!("\n{}", "x".repeat(100)),
        ))
        .unwrap();
        assert!(peer.name.chars().count() <= 64);
        assert!(!peer.name.chars().any(char::is_control));
    }
    #[test]
    fn snapshot_has_stable_version_and_no_initial_fake_peers() {
        let value = serde_json::to_value(Discovery::default().snapshot()).unwrap();
        assert_eq!(value["abi_version"], 2);
        assert_eq!(value["status"], "idle");
        assert_eq!(value["peers"], serde_json::json!({}));
    }
    #[test]
    fn updates_replace_candidates_and_goodbye_removes_them() {
        let mut snapshot = Snapshot::default();
        let first = service("10.1.2.3", "2", 0, "First");
        let id = first.fullname.clone();
        snapshot.apply(resolved(first));
        snapshot.apply(resolved(service("10.1.2.4", "2", 0, "Updated")));
        assert_eq!(snapshot.peers.len(), 1);
        assert_eq!(snapshot.peers[&id].name, "Updated");
        snapshot.apply(ServiceEvent::ServiceRemoved(SERVICE_TYPE.into(), id));
        assert!(snapshot.peers.is_empty());
    }

    #[test]
    fn unsupported_record_update_removes_an_old_candidate() {
        let mut snapshot = Snapshot::default();
        snapshot.apply(resolved(service("10.1.2.3", "2", 0, "Valid")));
        snapshot.apply(resolved(service("10.1.2.3", "99", 0, "Incompatible")));
        assert!(snapshot.peers.is_empty());
    }

    #[test]
    fn peer_cap_allows_existing_records_to_update() {
        let mut snapshot = Snapshot::default();
        for i in 0..=MAX_PEERS {
            let record = ServiceInfo::new(
                SERVICE_TYPE,
                &format!("peer-{i}"),
                "fixture.local.",
                "10.1.2.3",
                0,
                &[("protocol", "2"), ("phase", "presence"), ("name", "Peer")][..],
            )
            .unwrap()
            .as_resolved_service();
            snapshot.apply(resolved(record));
        }
        assert_eq!(snapshot.peers.len(), MAX_PEERS);
        let record = ServiceInfo::new(
            SERVICE_TYPE,
            "peer-0",
            "fixture.local.",
            "10.1.2.4",
            0,
            &[
                ("protocol", "2"),
                ("phase", "presence"),
                ("name", "Updated"),
            ][..],
        )
        .unwrap()
        .as_resolved_service();
        let id = record.fullname.clone();
        snapshot.apply(resolved(record));
        assert_eq!(snapshot.peers[&id].name, "Updated");
        assert_eq!(snapshot.peers.len(), MAX_PEERS);
    }
    #[test]
    fn removing_own_announcement_preserves_remote_candidates() {
        let mut snapshot = Snapshot::default();
        let own = service("10.1.2.3", "2", 0, "Own device");
        let own_id = own.fullname.clone();
        snapshot.apply(resolved(own));
        let remote = ServiceInfo::new(
            SERVICE_TYPE,
            "remote",
            "remote.local.",
            "10.1.2.4",
            0,
            &[
                ("protocol", "2"),
                ("phase", "presence"),
                ("name", "Remote device"),
            ][..],
        )
        .unwrap()
        .as_resolved_service();
        let remote_id = remote.fullname.clone();
        snapshot.apply(resolved(remote));
        let filtered = snapshot.without_self(&own_id);
        assert!(!filtered.peers.contains_key(&own_id));
        assert_eq!(filtered.peers[&remote_id].name, "Remote device");
    }
}
