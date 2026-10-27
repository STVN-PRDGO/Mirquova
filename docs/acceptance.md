# Acceptance and platform status

Current preview: 03 (0.2.0+2). Detailed evidence: [iteration-03.md](iteration-03.md). Earlier iteration reports remain historical.

The current source version is 0.3.0+3. New macOS/Linux/iOS build targets and current host verification are tracked separately in [platform-builds.md](platform-builds.md); the Preview 03 evidence below is historical.

## Foundation checklist

- [x] Preserve all five source plans with verified provenance.
- [x] Install local SDKs and generate Flutter Windows/Android and Rust projects.
- [x] Implement responsive navigation and light/dark/system appearance.
- [x] Implement bounded native mDNS scans and session-only manual IPv4 candidates.
- [x] Implement explicit two-minute visibility, cleanup, self filtering, and multicast lease sharing.
- [x] Exercise ABI v2 ownership and concurrent/canceled operations.
- [x] Pass 23 Rust unit tests (including 11 invitation validation tests), two opt-in same-host network tests, 24 Flutter tests, and one real Windows runner test.
- [x] Pass formatting, clippy, analysis, and inspect light/dark phone/desktop reference renders.
- [x] Build Windows release and Android ARM64 debug packages; verify APK signature, contents, and alignment.
- [x] Collect original third-party notices and provide CI configuration.
- [ ] Install/run Android APK on an authorized device.
- [ ] Validate Windows/Android discovery on two physical devices.
- [ ] Validate TalkBack, keyboard navigation across all flows, and device permission behavior.

## Product capabilities

| Capability/platform | Current evidence | Remaining gate |
| --- | --- | --- |
| Flutter shell | Widget tests, reference renders, actual Windows runner | Android/TV hardware UX |
| Rust Windows core | ABI v2 DLL, unit/network tests, release build | Broader host/device validation |
| Discovery/visibility | Bounded scans, explicit expiring presence, same-host resolution | Two physical devices and Android runtime |
| Manual fallback | Private IPv4 candidate validation/removal | Connection and identity verification |
| Pairing/trust | Design review and bounded invitation input parser; authentication NOT IMPLEMENTED | Authenticated protocol, key storage, adversarial tests |
| Transfer/casting | NOT IMPLEMENTED | Authenticated consent-scoped engines |
| Android phone | ARM64 debug APK verified | Device installation, permissions, LAN checks |
| ACE DE1L LED-909 | UNVERIFIED HARDWARE | OS/ABI, install, remote and decoder tests |
| Player/LAN media/subtitles | NOT IMPLEMENTED | Adapters and separate acceptance evidence |
| OpenSubtitles live | NOT IMPLEMENTED / credentials absent | Authorized access and current contract review |
| Web receiver/other TVs | NOT IMPLEMENTED | Independent adapters and device tests |
| P01-P22 | ORIGINAL MATRIX NOT SUPPLIED | Original definitions; no fabricated passes |

No Android/TV installation, throughput benchmark, live subtitle API request, or physical TV test is claimed. GitHub runner results must be checked separately from local evidence.
