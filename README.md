# Mirquova

[![Foundation checks](https://github.com/STVN-PRDGO/Mirquova/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/STVN-PRDGO/Mirquova/actions/workflows/ci.yml)

Every screen. One connection.

A Flutter Windows/Android app with a Rust LAN discovery core. Preview 03 (0.2.0+2) adds explicit, time-limited visibility: choose a name, advertise for up to two minutes, and hide at any time. Nearby candidates remain unverified.

## Current capabilities

- Responsive navigation, light/dark/system appearance, and native Material controls.
- Bounded six-second mDNS scans, cancellation, candidate updates/removal, and session-only manual private IPv4 entries.
- Hidden by default. Visibility requires consent, uses a random process identifier, and stops when the app backgrounds. Scans and visibility share Android multicast access.
- Versioned C/Dart FFI with owned snapshots. Self-announcements are excluded from results.
- Settings includes manual, consented app update checks, release notes and a browser link to a newer GitHub release. See [App updates](docs/app-updates.md) for release requirements and installation limits.

Visibility announces presence only; it opens no pairing or transfer endpoint. Manual addresses are not contacted. Pairing, transfer, casting, playback, persistent history, and online subtitles remain planned. Rust also contains a bounded, untrusted [invitation parser](shared/contracts/pairing-invitation.md) as pairing groundwork; it is not exposed in the app. See the [pairing design review](docs/pairing-design-review.md) for transport and identity gates.

## Build and check

Install Flutter 3.47.8 / Dart 3.13.7, Rust 1.99.1, and the platform prerequisites described in [Build and run](docs/build-and-run.md). On the development workstation, the scripts activate ignored project-local SDKs.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Windows.ps1 -Mode release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Android.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Windows.ps1
```

Preview 03 local verification: 12 Rust unit tests, two explicitly enabled same-host network tests, 24 Flutter tests, and one actual Windows integration test passed. Formatting, clippy, and Flutter analysis passed. Windows release and Android ARM64 debug builds passed; APK signature, contents, and alignment were checked. Android installation and discovery between two physical devices remain unverified.

The invitation groundwork adds 11 Rust input-validation and expiry tests. GitHub Actions checks the Windows foundation and Android ARM64 debug build on pushes and pull requests. Local preview packages live under ignored `artifacts/iteration-03/`; they are not GitHub release downloads. See [Preview 03 results](docs/iteration-03.md) for checksums and evidence.

## Documentation

- [Acceptance and platform status](docs/acceptance.md)
- [Roadmap](docs/implementation-roadmap.md)
- [Original analysis](docs/project-analysis.md)
- [Native discovery ABI v2](shared/contracts/README.md)
- [Dependency notices](THIRD_PARTY_NOTICES.md)
- [Original supplied plans](docs/source/) and [provenance](docs/source-manifest.json)

The five source plans are preserved unchanged. Prompts within them are reference material. REA was assessed and is unnecessary for the current source-based implementation. Project licensing, release identifiers, signing, and distribution review remain open; no project code license has been selected.
