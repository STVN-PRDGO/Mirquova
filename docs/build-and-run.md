# Build and run

## macOS, Linux, iOS and Android from a Unix shell

The platform runners now include macOS (Apple Silicon), Linux and iOS (ARM64 device/simulator), alongside Windows and Android. These are preview build targets; runner source and CI configuration do not establish tested device support. See [platform build evidence](platform-builds.md) for current results and blockers. The older Windows workstation evidence below remains historical.

Use `scripts/Use-Toolchains.ps1` in PowerShell. For bash/zsh on macOS/Linux, its shell equivalent is:

```sh
source scripts/Use-Toolchains.sh
```

It selects project-local SDKs when present and otherwise uses installed tools. Keep Flutter 3.47.8 / Dart 3.13.7 and Rust 1.99.1. Install required Rust targets explicitly; build scripts do not install SDKs, accept licenses or change signing accounts.

| Target | Command from repository root | Output/prerequisite |
| --- | --- | --- |
| macOS ARM64 | `bash scripts/Build-macOS.sh` | Full Xcode; ad hoc app ZIP under `artifacts/iteration-04/` |
| Linux host architecture | `bash scripts/Build-Linux.sh` | Linux + GTK3 build tools; complete `apps/mirquova_flutter/build/linux/<arch>/release/bundle/` |
| Android ARM64 | `bash scripts/Build-Android.sh` | Android SDK/NDK, JDK, cargo-ndk; `apps/mirquova_flutter/build/app/outputs/flutter-apk/app-debug.apk` |
| iOS ARM64 device | `bash scripts/Build-iOS.sh device` | Full Xcode, `aarch64-apple-ios`; unsigned `apps/mirquova_flutter/build/ios/iphoneos/Runner.app` |
| iOS ARM64 simulator | `bash scripts/Build-iOS.sh simulator` | Full Xcode + simulator runtime, `aarch64-apple-ios-sim`; `apps/mirquova_flutter/build/ios/iphonesimulator/Runner.app` |

For Linux, install `clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev` on Ubuntu 24.04; see [Flutter Linux setup](https://docs.flutter.dev/platform-integration/linux/setup). Keep the entire bundle together, including `lib/libmirquova_core.so` and notices. Desktop integration checks can run with `xvfb-run -a flutter test integration_test/native_app_platform_test.dart -d linux --no-pub` from the app directory after building the core.

iOS uses a statically linked Rust library and `DynamicLibrary.process()`; Xcode configurations retain the ABI symbols for lookup. Build the matching Rust target before running from Xcode. The simulator target is Apple Silicon only. iOS discovery uses raw multicast sockets: signing profiles must include Apple's approved [multicast entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast), and the user must grant local-network access. Adding the entitlement file does not grant approval. Device discovery and background cleanup need physical iPhone testing.

An APK runs on Android. For an installable iOS IPA, first configure a valid bundle identity, signing team and provisioning profiles with the multicast entitlement in Xcode. Then set `MIRQUOVA_IOS_EXPORT_OPTIONS` to an export-options plist and run `bash scripts/Build-iOS.sh ipa`. Flutter writes the signed IPA to `apps/mirquova_flutter/build/ios/ipa/`; see [Flutter iOS distribution](https://docs.flutter.dev/deployment/ios). The default device build is unsigned and cannot be installed as an IPA.

CI now includes Linux/macOS checks and packaging, unsigned iOS device/simulator builds, and an uploaded Android debug APK. These run after the workflow reaches GitHub; no remote pass is implied by editing it. Production signing, notarization, installers and device QA remain pending.

On macOS/Linux, verify an Android build with `python3 scripts/verify_apk.py` after activating the toolchains. It checks the ARM64 Rust/Flutter payload, signature and 16 KiB ZIP alignment. Override `MIRQUOVA_ANDROID_BUILD_TOOLS` if using a build-tools version other than 36.0.0.

### Opening the macOS preview when Gatekeeper blocks it

The macOS preview is signed ad hoc, without Apple notarization. ZIP, DMG or PKG packaging does not remove Gatekeeper's checks. For a preview you trust, extract it, move `mirquova.app` into Applications and attempt to open it. If Apple cannot verify it, click **Done**, then **System Settings → Privacy & Security → Open Anyway** for mirquova, and confirm **Open**. See [Apple's instructions for opening an unnotarized app](https://support.apple.com/en-gb/102445).

As an alternative for this specific trusted preview, run in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/mirquova.app
open /Applications/mirquova.app
```

This removes download quarantine only from this app. It does not notarize the app or disable Gatekeeper globally. If you installed it elsewhere, substitute its exact path in both commands. Future downloads still need approval until the distribution workflow uses a Developer ID Application certificate and Apple notarization; see [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). No Developer ID credentials or notarization configuration are currently provided by this repository. The commands above are manual instructions, not an automatic action during download or installation.

## Local toolchains

This workstation has project-local Flutter 3.47.8 / Dart 3.13.7 and Rust 1.99.1 (Windows GNU) under .toolchains. Nothing was added to global PATH. A portable GNU linker is used for Rust. Microsoft C++ Build Tools and the Windows SDK are now installed for Flutter's Windows runner. The project-local Android SDK/NDK and JDK are also installed; both native builds succeed. See iteration-02.md for versions and evidence. Local SDK paths are ignored by version control.

On this host scripts are disabled by the persistent PowerShell policy. Use a new process with a process-only override:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass
cd D:\Mirquova
. .\scripts\Use-Toolchains.ps1
```

Use installed SDKs on other machines instead; Flutter and Dart must match the versions in the lockfile/CI. The temporary application ID dev.mirquova.mirquova is for development only; it is not a verified release identity.

## Foundation checks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Check.ps1
```

This runs Rust formatting, clippy, unit tests, the DLL build, Flutter dependency-lock verification, formatting, analysis and widget/native bridge tests. Golden references contain SDK-font renders generated on macOS. Exact pixel comparisons run on the macOS CI job; Windows/Linux run the complete functional and layout suite with `--exclude-tags golden`. Only the four image comparisons are tagged; large-text/reduced-motion layout checks remain active on every host. Run `flutter test --no-pub test/render_previews_test.dart` on macOS for visual comparisons. Do not regenerate references on Windows/Linux or loosen the comparator to hide cross-host raster differences. Failed visual comparisons are uploaded from CI as `visual-comparison-macOS`.

## Windows application

This workstation has the required Microsoft C++ tooling. On another host, install that prerequisite first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Windows.ps1
```

The build script sets MIRQUOVA_CORE_BUNDLE and CMake copies the Rust DLL next to the executable. Run the generated apps/mirquova_flutter/build/windows/x64/runner/Debug/mirquova.exe. Keep its complete bundle together; compiler/native runtime notices and runtime DLL needs require review before distribution.

For development, build the Rust core first, then from the Flutter app directory:

```powershell
flutter run -d windows --dart-define=MIRQUOVA_CORE_LIBRARY=D:/Mirquova/target/debug/mirquova_core.dll
```

The compile-time path override is for development/testing only. Normal packaged builds load the adjacent DLL. The UI opens in a setup state if the library is unavailable; it never fills the device list with fixtures.

## Discovery CLI

From the project root with the toolchain environment active:

```powershell
cargo run -p mirquova-core --bin discovery-spike -- browse
```

To exercise real multicast, build the CLI once, then in two terminals:

```powershell
# Terminal A: 15-second opt-in test advertisement, no transfer server
.\target\debug\discovery-spike.exe advertise
# Terminal B: bounded six-second scan
.\target\debug\discovery-spike.exe browse
```

For two-device testing, run the advertiser on a second authorized machine on the same trusted LAN. A same-host result proves only the local multicast path. Firewall/client isolation or interfaces without RFC1918 IPv4 can yield no results. Do not broadly disable a firewall to obtain a pass. Preview 03 adds explicit, consented presence for up to two minutes. It is hidden by default and has no transfer/pairing endpoint. Both apps must use the current protocol; see iteration-03.md.

## Android development build (built locally; device validation pending)

Install matching Flutter Android requirements and an Android NDK, then select real device ABI. Example ARM64 build:

```powershell
rustup target add aarch64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
# Set ANDROID_NDK_HOME to your installed NDK directory.
cargo ndk -t arm64-v8a --platform 24 -o apps/mirquova_flutter/android/app/src/main/jniLibs build --lib --release --locked
cd apps/mirquova_flutter
flutter build apk --debug --target-platform android-arm64
```

The app loads libmirquova_core.so from jniLibs. Android Activity code acquires a Wi-Fi multicast lock while a scan or opted-in presence session needs it, and releases it when idle or on background/destroy. Manifest network/multicast permissions do not guarantee access on all future Android versions; validate actual firmware permission behavior. No physical phone or TV installation/run has been tested here. A debug APK is not a signed production release and the generated phone target is not a TV app.

## Continuous integration

.github/workflows/ci.yml provides Windows Rust/Flutter checks and a separate ARM64 Android native/debug build job. It runs on pushes and pull requests in the GitHub repository. Inspect the Actions run for remote results; local verification is recorded separately in iteration-03.md.

## App update checks

Settings > System updates reads the installed app version locally. Check for updates asks permission to contact GitHub; no release request runs at startup. Development and automated verification use offline release fixtures unless a person explicitly opts into a live check. See [App updates](app-updates.md) for the release-tag contract and manual installation workflow. Production signing and installation QA remain outstanding.

The offline native bridge test can be run on Windows after loading the toolchain environment:

```powershell
cd apps/mirquova_flutter
flutter --suppress-analytics --no-version-check test integration_test/native_app_platform_test.dart -d windows --no-pub
```

It reads installed metadata, opens Settings, cancels update consent and rejects invalid browser URLs without contacting the release API or opening a browser.

## Notices

With dependencies resolved and FLUTTER_ROOT set:

```powershell
.\.toolchains\python\python.exe .\scripts\collect_notices.py
```

Review THIRD_PARTY_NOTICES.md and preserved originals before release. No project code license or brand clearance is implied.

## Verified native build workflow

The required tooling is now installed on this workstation. Microsoft Build Tools 2022 and Windows SDK are registered with the machine; the selected C++ tools live under .toolchains/vs-buildtools. Android SDK/NDK and Temurin JDK are project-local. Standard SDK licenses were accepted during authorized setup. Use-Toolchains.ps1 configures the environment for the current shell; no global PATH edit is required.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Windows.ps1 -Mode release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Android.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Windows.ps1
```

The native integration test opts into presence, completes a six-second scan, verifies self filtering, cancels another scan, and hides presence in the actual Windows runner. It saves a rendered view to local-evidence/windows-native.png. It does not require a discovered peer or establish two-device connectivity.

To verify/package the existing build outputs, enter a PowerShell process with the toolchain environment loaded, then run:

```powershell
.\.toolchains\python\python.exe .\scripts\verify_apk.py
.\.toolchains\python\python.exe .\scripts\package_preview.py
```

Packaging defaults to artifacts/iteration-03 and refuses to overwrite existing output. Use --iteration iteration-NN for a deliberate new iteration; previous packages remain unchanged. The Windows ZIP is a complete portable preview bundle, not an installer. The APK is debug signed for local ARM64 phone testing. No connected Android/TV run is implied.

The initial Gradle download stalled; a SHA-256 verified official distribution was seeded in the wrapper cache. The wrapper now pins the published Gradle 9.3.1 all-distribution checksum. Fresh hosts still use the original HTTPS distribution URL.

## Opt-in network tests

With the toolchain environment active, run `cargo test network_presence_ -- --ignored --test-threads=1` from the project root. These tests use actual multicast and a shortened test expiry, so they are excluded from default CI. Two tests passed on this host; they do not establish two-device connectivity.
