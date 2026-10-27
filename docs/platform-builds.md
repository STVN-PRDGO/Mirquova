# Platform expansion evidence

Recorded on 2026-10-27 for source version 0.3.0+3. Historical Windows/Android results remain in iteration-02.md and iteration-03.md. This work expands the infrastructure milestone only; pairing, transfers, casting and playback remain unavailable.

## Implementation

- Existing macOS ARM64 runner and app-version/browser bridge retained; its packaging script now activates the portable toolchain environment.
- New Linux GTK runner includes the app-version/browser bridge, independently validates release URLs, and bundles the Rust shared library under `lib/`.
- New iOS runner includes the app-version/browser bridge, local-network privacy text, Bonjour service declaration and multicast entitlement. Rust builds as a static library; Xcode force loads and retains the seven ABI exports for Dart process lookup. Device and simulator libraries are separate; both are ARM64.
- Unix build scripts produce a Linux bundle, Android debug APK, unsigned iOS device app or simulator app. Signed IPA export requires caller-supplied signing configuration. Windows PowerShell scripts remain available.
- CI adds Linux/macOS checks and native packaging, unsigned iOS device/simulator builds and artifact uploads. Remote jobs have not been run from this session.
- The separate `Release` workflow (`.github/workflows/release.yml`) now builds Windows, Android, macOS ARM64, Linux x64 and an unsigned iOS ARM64 device app. Publishing waits for all five jobs and attaches their packages, plus checksums for the three new platforms. macOS/Linux/iOS packages include third-party notices. iOS remains an unsigned app ZIP, not an installable IPA; signed export requires Apple credentials and provisioning. Existing queued/running workflows retain their original job graph; the expanded workflow applies to a new run after the change is pushed.

## Local evidence

| Check | Result |
| --- | --- |
| Rust format | Passed |
| Rust clippy, workspace/all targets, warnings denied | Passed |
| Rust workspace tests | 23 passed, 2 real-network tests intentionally ignored |
| macOS Rust dylib/static library | Built on this host |
| Android ARM64 Rust library | Release build passed with cargo-ndk 4.1.2 and NDK 28.2.13676358 |
| Locked Flutter dependency resolution | Passed; Cargo.lock and pubspec.lock unchanged |
| Dart formatting | 23 files, no changes |
| Flutter analysis | Passed, no issues |
| Selected offline Flutter tests | 70 passed, including compiled macOS native ABI loading |
| Shell script syntax and bash/zsh toolchain activation | Passed |
| iOS Swift syntax, plist and Xcode project structure | Parsed successfully; not an SDK compilation |
| macOS native app build | Blocked: Flutter reports full Xcode is not installed |
| iOS native app build | Blocked: `xcrun` cannot find the iPhoneOS SDK; only Command Line Tools are installed |
| Linux native app build | Not run: current host is macOS; no running Linux container engine |
| Android APK | Built successfully; ARM64 payload, APK v2 signature and 16 KiB ZIP alignment verified |

At the time of this platform-build verification, Windows golden-image references were excluded from the selected tests and were not regenerated. The subsequent design refresh regenerated these references on macOS; exact golden comparisons now run on the macOS CI job, while Windows/Linux exclude only tests tagged `golden`. Dependencies and preserved source originals/notices were not changed. No live release API, discovery scan, advertisement, physical-device installation or authenticated connection was exercised. iOS multicast entitlement approval, signing, installation, permissions and physical discovery are pending. macOS packages remain Apple Silicon only and require notarization/installation QA before production distribution.

## Generated Android APK

- Build output: `apps/mirquova_flutter/build/app/outputs/flutter-apk/app-debug.apk`.
- Review copy with notices: `artifacts/platform-preview-2026-10-27/android-arm64/Mirquova-0.3.0+3-android-arm64-debug.apk` (ignored local artifact).
- SHA-256: `d4164b94c669dfb950b6d4f3b33614483c53bfe65596141384653693ef6908cf`.
- Size: 79751050 bytes. Development debug signature only; not a production/store release.

The first Gradle wrapper download was interrupted after making slow progress. An official `downloads.gradle.org` download was verified against the repository's pinned SHA-256 (`17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43`) and used to seed the wrapper cache. The subsequent build completed after resolving first-build dependencies. No Gradle repository URL, checksum, dependency version or lockfile was changed.
