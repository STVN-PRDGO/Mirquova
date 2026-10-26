# Preview 03: opt-in LAN visibility

Version: 0.2.0+2. Local verification recorded on 2026-10-27. Previous results remain in iteration-01.md and iteration-02.md as historical records.

## Implemented

The Nearby page now offers Make discoverable, a chosen-name consent dialog, and Hide now. Visibility is hidden by default, lasts up to 120 seconds including startup, and stops on background or disposal. Names are bounded and reject control/bidi characters. The app uses a fresh UUIDv4 announcement identifier for each process, without publishing the OS or account hostname. This identifier is not an authenticated identity.

The experimental `_mirq-presence._tcp.local.` record carries protocol=2, phase=presence, and port 0. It advertises no application listener. Only this prototype convention is accepted by the browser; earlier preview records are ignored. Both test apps must use the current preview. Candidate addresses are bounded RFC1918 IPv4 entries; results remain unverified. The app filters its own instance.

ABI v2 adds explicit presence start/stop and snapshot status. Rust owns announcement cleanup and the time limit. Dart copies owned UTF-8 inputs, frees native snapshots, serializes multicast leases, and handles canceled or overlapping scan/visibility requests. Android shares one Wi-Fi multicast lock across demand and releases it when idle or backgrounded.

## Verification

| Check | Result |
| --- | --- |
| Rust formatting and clippy with warnings denied | Passed |
| Rust default unit suite | 12 passed; two real-network tests excluded by default |
| Explicit real-network tests | 2 passed on this Windows host: hide/restart/expiry and actual presence resolution |
| Flutter formatting and analysis | Passed |
| Flutter suite with compiled native DLL | 24 passed |
| Actual Windows runner integration | 1 passed: consent, visibility, scan completion, self filtering, stop and hide |
| Reference renders | Light/dark at phone/desktop sizes inspected; large text and reduced-motion tests passed |
| Windows release bundle | Built with ABI v2 core |
| Android ARM64 debug APK | Built; version 0.2.0+2, minimum API 24, debug signature and 16 KiB alignment checked |
| Connected Android device probe | No authorized or unauthorized devices found |
| Dependency notices | 81 package/SDK entries collected; original notices retained |

Network tests are opt-in because they use actual multicast interfaces:

```powershell
cargo test network_presence_ -- --ignored --test-threads=1
```

The native runner image is [windows-presence.png](previews/windows-presence.png). It demonstrates this workstation only. No Android/TV runtime, two-physical-device discovery, authenticated pairing, transfer, or casting is claimed. Remote GitHub CI is separate from these local results.

## Local packages

Packages are ignored by Git and are not automatically published as releases. Extract the complete Windows ZIP before launching mirquova.exe. The APK is an ARM64 phone debug build, not a production-signed or validated TV package.

| File under artifacts/iteration-03 | Bytes | SHA-256 |
| --- | ---: | --- |
| Mirquova-preview-windows-x64.zip | 12889510 | 400c525e041d621cb7b56966cbb74fa501f9034553243f6918813e7493a8b290 |
| Mirquova-preview-android-arm64-debug.apk | 79793786 | 1fe948f71db555774de54178a61922b430b69727f973c2be1db2c8f5b448ad18 |

Packaging verifies the Windows ABI and compares the APK native library with the NDK-stripped current Rust build. The package manifest and notices are alongside the local files; packaging refuses to overwrite an existing iteration directory.

## Next work

The [pairing review](pairing-design-review.md) proposes a separate authenticated channel and an expiring invitation with identity binding. It does not implement pairing. Physical Android access, two-device LAN validation, platform identity storage, protocol review, and adversarial identity/session tests remain gates before trusted peers or file access can be offered.
