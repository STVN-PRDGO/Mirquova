use mdns_sd::{ServiceDaemon, ServiceInfo};
use mirquova_core::discovery::{Discovery, SERVICE_TYPE};
use std::{env, process::ExitCode, thread, time::Duration};

fn run() -> Result<(), Box<dyn std::error::Error>> {
    match env::args().nth(1).as_deref() {
        Some("browse") => {
            let mut discovery = Discovery::default();
            if !discovery.start() {
                return Err("Could not start scan".into());
            }
            loop {
                thread::sleep(Duration::from_millis(150));
                let snapshot = discovery.snapshot();
                if !matches!(
                    snapshot.status,
                    mirquova_core::discovery::ScanStatus::Scanning
                ) {
                    println!("{}", serde_json::to_string_pretty(&snapshot)?);
                    if snapshot.error.is_some() {
                        return Err("LAN scan failed".into());
                    }
                    break;
                }
            }
        }
        Some("advertise") => {
            // Opt-in test announcement only. Port 45833 has NO transfer listener.
            let daemon = ServiceDaemon::new()?;
            let id = format!("Mirquova-spike-{}", std::process::id());
            let service = ServiceInfo::new(
                SERVICE_TYPE,
                &id,
                &format!("{id}.local."),
                "",
                0,
                &[
                    ("protocol", "2"),
                    ("name", "Discovery test device"),
                    ("phase", "presence"),
                ][..],
            )?
            .enable_addr_auto();
            let name = service.get_fullname().to_owned();
            daemon.register(service)?;
            println!(
                "Advertising a discovery-only test candidate for 15 seconds. No transfer server."
            );
            thread::sleep(Duration::from_secs(15));
            if let Ok(removed) = daemon.unregister(&name) {
                let _ = removed.recv_timeout(Duration::from_secs(1));
            }
            if let Ok(stopped) = daemon.shutdown() {
                let _ = stopped.recv_timeout(Duration::from_secs(1));
            }
        }
        _ => return Err("Usage: discovery-spike browse|advertise".into()),
    }
    Ok(())
}
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}
