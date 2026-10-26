# Iteration 02: native builds and discovery reliability

Date: 2026-10-26 (Asia/Singapore). The user requested continuation after the first infrastructure iteration. This increment removes the native build blockers, produces local previews, and verifies discovery in the actual Windows runner.

## Results

| Check | Result |
| --- | --- |
| Rust formatting and clippy with warnings denied | PASS |
| Rust unit tests | 8 passed, 0 failed |
| Flutter formatting/analyzer | PASS; no issues found |
| Flutter widget/native-library tests | 16 passed, 0 failed, none skipped |
| Windows release build | PASS; optimized Rust DLL bundled with native runner |
| Windows release launch smoke | PASS; process remained running for 8 seconds, then the test process was closed |
| Windows native integration | 1 passed; actual runner completes a scan, then cancels a second scan |
| Android ARM64 native build | PASS; NDK r28c, API 24 |
| Android debug APK | PASS; Gradle assembleDebug completed |
| APK archive contents | PASS; Flutter engine, Rust core, manifest and DEX present, ARM64 only |
| APK signature | PASS; one debug signer, APK Signature Scheme v2 |
| APK ZIP alignment | PASS; zipalign -c -P 16 4 |
| Native Android ELF LOAD alignment | 0x4000 (16 KiB) |
| flutter doctor -v | No issues found |

Native Windows UI evidence: [captured Flutter view](previews/windows-native.png). This image was rendered from the actual desktop integration test, not a fixture screenshot. The native integration test does not require a peer and does not establish Windows/Android connectivity.

## Local preview artifacts

artifacts/iteration-02 contains:

- Mirquova-preview-windows-x64.zip (12,775,421 bytes): extract the complete bundle, then run mirquova.exe. Native core, engine, data and notices are included. This is an unsigned preview bundle, not an installer.
- Mirquova-preview-android-arm64-debug.apk (79,688,714 bytes): debug-signed phone build, min SDK 24 (Android 7), target/compile SDK 36, application ID dev.mirquova.mirquova, version 0.1.0+1. It has not been installed on a device here.
- manifest.json with exact SHA-256 values; README and original dependency notices.

These are local build artifacts excluded from Git. The source remains in D:/Mirquova. No repository or binary was published.

## Code changes

- Extracted deterministic handling of service records and added tests for replacement, removal, incompatible updates and capped candidate updates.
- An invalid replacement now removes its earlier candidate rather than leaving stale compatible metadata visible.
- A disconnected discovery event channel returns an error instead of spinning until the timeout. Worker panics produce a terminal error state.
- Added Build-Android.ps1, Test-Windows.ps1, the native desktop integration test, verify_apk.py and package_preview.py.
- Added project-local Java/Android environment setup. Windows C++ tools are installed at .toolchains/vs-buildtools and registered through Microsoft's installer.
- Added the published Gradle distribution checksum and removed a CI-only absolute library path from the Windows packaged build.
- Collected notices for 65 resolved package/SDK entries and preserved available native Flutter engine/client-wrapper notices. No new production Dart dependency was added; integration_test is a development SDK dependency.

## Installed tooling and setup

Microsoft-signed Build Tools 2022 17.14.43 / Windows SDK 10.0.26100 installed successfully (exit 0). This also installed Microsoft's machine-level installer/SDK components. No host restart was performed.

Project-local Temurin JDK 17.0.20.1+1 and Google command-line tools 22.0 were verified against published checksums. Installed Android platform/build tools 36, NDK 28.2.13676358, CMake 3.22.1, platform tools, Rust Android ARM64 standard library and cargo-ndk 4.1.2. Standard SDK licenses were accepted for the authorized setup; global PATH was not edited.

The full JDK and Gradle downloads stalled. Official byte ranges were assembled and verified against published SHA-256 checksums. Gradle's original wrapper cache was seeded without replacing its HTTPS source. A non-fatal SDK XML schema warning occurred during the Android build; the build and artifact verification succeeded. These setup details do not imply deployment validation.

## Remaining work and limits

- No Android phone/emulator or ACE TV installation/run was performed. No two-device discovery test has passed. The app still browses only; it does not announce itself.
- Manual endpoints remain session-only, unverified and uncontacted. IPv6 and QR fallback are still pending.
- Pairing, pinned keys, SQLite persistence, transfers, screen capture/WebRTC, player and OpenSubtitles remain unimplemented.
- Physical TalkBack/D-pad, signing/update distribution, minimum Windows runtime and complete Android engine redistribution review remain open. The inspected Android engine/embedding JARs had no standalone license entries; available SDK/native notices are preserved, and no public release clearance is claimed.
- Remote CI has not run. The original protocol and P01-P22 source specifications are still missing.

Next implementation step is to design and review identity/pairing and add explicit app advertisement suitable for the eventual protocol, then validate discovery between Windows and an authorized Android device. Do not infer a secure session from a scan result or open a transfer server before authentication and consent exist.
