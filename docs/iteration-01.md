# Iteration 01: foundation and discovery

Date: 2026-10-26 (Asia/Singapore). The user authorized implementation after the preparation workspace was created. This increment implements the proposed infrastructure/discovery slice, with native app build gates still open.

## Delivered code

- apps/mirquova_flutter: generated Windows/Android platform projects, Material 3 shell, seven destinations, Nearby scan controls, manual private-IPv4 candidates, session appearance, unavailable-feature states and lifecycle cancellation.
- lib/core/discovery_port.dart: typed candidate/snapshot/endpoint boundary; lib/adapters/native_discovery.dart: ABI validation, JSON ownership/free, scan polling and Android multicast-lock lifecycle.
- crates/mirquova-core: mDNS browse worker, bounded six-second scans, cancellation, strict protocol TXT filter, RFC1918 IPv4 filtering, 128-peer/16-address bounds, name sanitization and record removal. No transfer listener or automatic advertisement.
- discovery-spike CLI: explicit 15-second test advertiser and six-second browser.
- shared/contracts: versioned C ABI and behavior/ownership contract, derived independently because the original protocol specification was not supplied.
- scripts: checks, Windows bundle build, real multicast smoke test, SDK environment, original launcher-icon generation and dependency-notice collection.
- .github/workflows/ci.yml: Windows checks/build and separate ARM64 Android native/debug build definitions. Added only; no remote CI execution or publishing occurred.
- third_party/licenses and THIRD_PARTY_NOTICES.md: original notices for 56 resolved packages/SDK entries plus bundled-font notices. Development dependencies are included. The Flutter SDK license also governs its test package, which has no separate root LICENSE.
- Original geometric M launcher icons replace generated Flutter branding. Source: scripts/Generate-Icons.ps1, independently authored for this prototype. No external media or third-party editor composition was copied.

## Verified outputs

```text
cargo fmt --all -- --check                     PASS
cargo clippy --workspace --all-targets --locked -- -D warnings
                                              PASS
cargo test --workspace --locked                5 passed; 0 failed
cargo build -p mirquova-core --lib --locked     PASS (Windows GNU DLL)
cargo build -p mirquova-core --bin discovery-spike --locked
                                              PASS (Windows CLI)
flutter pub get --enforce-lockfile             PASS
 dart format --output=none --set-exit-if-changed lib test
                                              PASS (no changes)
flutter analyze                               No issues found
flutter test --reporter expanded --dart-define=MIRQUOVA_CORE_LIBRARY=D:/Mirquova/target/debug/mirquova_core.dll
                                              16 passed; 0 failed; no skipped tests
scripts/Smoke-Discovery.ps1                    PASS real same-host mDNS:
                                              1 test candidate, unverified
scripts/collect_notices.py                     56 package/SDK notice directories collected
```

Native bridge coverage actually loads the compiled Rust DLL, reads/frees its initial JSON snapshot, and observes an empty idle discovery state. Rust tests also read/free 128 snapshots. UI tests inject fixture ports to test user-visible behavior; they do not claim network results.

Phone/tablet/desktop layout checks include 375x812, 812x375, 768x1024 and 1440x900 logical sizes, 2x text and reduced motion. All four readable light/dark phone/desktop golden renders were visually inspected. Physical screen-reader, keyboard walkthrough, real phone and TV remote testing remain outstanding.

The compiled DLL exports all five documented mq_* functions. PE import inspection showed Windows system/UCRT imports and no GCC runtime DLL import for this build; redistribution/minimum-Windows/runtime review is still required before release.

## Build attempts and failures

- flutter build windows --debug: FAILED, "Unable to find suitable Visual Studio toolchain. Please run flutter doctor for more details."
- flutter build apk --debug: FAILED, "No Android SDK found. Try setting the ANDROID_HOME environment variable."
- flutter doctor -v confirms missing Visual Studio and Android SDK. The installed GNU toolchain is sufficient for Rust, not Flutter's native Windows runner.

No Windows app EXE, Android APK, release installer or signed TV package was produced. Widget tests run through Flutter's test engine, not the Windows runner.

## Toolchains and setup evidence

Installed locally under .toolchains: Flutter 3.47.8 (stable Git revision 737ba8f885; engine cf636b1dfb), Dart 3.13.7, Rust 1.99.1 (stable-x86_64-pc-windows-gnu), rustfmt/clippy, WinLibs GCC 16.2.0 UCRT and portable Python 3.13.3 for skill searches/notice generation. No global PATH change or Android license acceptance occurred.

The official Flutter release JSON/archive attempts returned 404; bootstrapped from https://github.com/flutter/flutter.git branch stable instead. Initial LLVM-MinGW linkage lacked libgcc/libgcc_eh; the final supported local setup uses GCC. A slow compiler download was completed in verified byte ranges, concatenated, ZIP-integrity checked and extracted. All SDK/download artifacts are excluded from version control. REA was neither needed nor installed.

## Next work

1. Provide Microsoft Desktop development with C++ tools and Android SDK/NDK/JDK, then run the native builds and validate platform permissions on actual devices.
2. Add production app advertisement and verify Windows/Android discovery on two physical devices; add IPv6/QR support as separately tested increments.
3. Specify and review authenticated pairing/key storage/revocation and protocol negotiation before any transfer or remote access.
4. Implement one approved streaming file-transfer round trip, then move through the roadmap. Keep ACE hardware gates and original missing P01-P22 definitions explicit.

SDK installation, device permission, signing and dependency-license review do not establish release readiness. This iteration does not claim a finished app.
