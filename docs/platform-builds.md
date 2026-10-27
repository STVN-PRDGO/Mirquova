# Platform expansion evidence

Recorded on 2026-10-27 for source version 0.3.0+3. Historical Windows/Android results remain in iteration-02.md and iteration-03.md. This record covers the earlier platform expansion; authenticated pairing has since been added. Transfers, casting and playback remain unavailable.

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

## Pairing integration evidence (2026-10-28)

These results apply to the pairing changes and must not be conflated with the older APK/artifact above:

| Check | Result |
| --- | --- |
| Windows Rust workspace tests and Clippy | Passed; 42 tests passed and 6 network tests were intentionally ignored |
| Windows Flutter analysis and functional tests | 124 non-golden tests passed with the native Rust core loaded; macOS reference goldens excluded |
| Android ARM64 and x86_64 Rust pairing cores | Latest release builds passed with local cargo-ndk/NDK after the zeroizing payload changes; ELF AArch64 and x86-64 machines and pairing ABI symbols verified |
| Android release APK with pairing plugins | Passed locally after Google Maven access was approved; merged APK manifest confirms `android:allowBackup=false` |
| Windows Flutter plugin bundle | Retried locally, including elevated execution; Flutter still reports symlink support is disabled and asks for Windows Developer Mode |
| Local Android native integration | Not run: no emulator package or Android device is installed/connected; Flutter lists only Windows and Chrome |
| iOS device and simulator Rust/Xcode builds in the shown CI run | Reached completion before the simulator bridge test |
| iOS simulator bridge test | Earlier run timed out at its 600-second subprocess limit; `pumpAndSettle` now has a 30-second bound, verbose stage markers identify stalls, and CI jobs have a 45-minute cap. A passing CI rerun is still required |
| Linux/macOS pairing build and secure-storage runtime | No current pairing-specific evidence recorded |
| Windows/Linux/macOS transport test in CI | Explicit same-host approval/rejection tests added; remote results await next CI run. All four same-host Rust transport scenarios were rerun locally and passed |
| Physical Windows-to-Android pairing, restart and revoke | Not run |

The current Flutter functional suite has **124 passing non-golden tests** with the native Rust core loaded. The latest prescribed `scripts/Check.ps1` run passed Rust formatting, Clippy, all 42 Rust workspace tests (6 opt-in network tests ignored), Dart formatting, Flutter analysis, and all 124 non-golden Flutter tests. TLS tests reject a TLS-1.2-only client and plaintext data at the TLS-1.3 listener. Native FFI checks now cover starting and stopping a listener on a private IPv4 interface as well as rejecting wrong pins and public bind addresses. Invitation disposal, transferred-payload clearing, native snake-case status decoding, editing-confirmation reset, stopping during delayed secure-storage reads, oversized multibyte invitation rejection, clearing expired join invitations, stopping and clearing host and join invitations on app background, ordering revoke after an in-flight trust write, clearing loaded or created identity keys after validator errors, and using independent key copies across superseded requests are covered by tests. A full Windows Flutter run reached 113 passed, but the four platform-sensitive golden comparisons failed (Windows-rendered images differ from the checked-in macOS references); CI runs these exact image comparisons on macOS. The unit/widget suite still does not load the secure-storage platform plugin or connect two pairing peers.

The native application integration smoke test generates an identity, reloads and validates it from the OS store, persists and revokes its public peer pin using unique temporary storage keys, exercises wrong-pin and public-address rejection before network activity, starts and stops a one-use host listener on an available RFC1918 interface, and opens the Pair screen to load its transport ABI and platform-specific invitation entry point. It does not alter normal app identity/trust records, start the camera, or connect to a peer. CI is configured to invoke it on Windows, Android x86_64 emulator, Linux under a temporary GNOME Keyring, macOS and iOS simulator; the Android CI APK is configured to bundle ARM64 and x86_64 cores for that emulator run. The Linux release job now provisions the same keyring before its secure-storage smoke test. Release jobs are capped at 45 minutes (15 for publishing) to prevent an integration or packaging step from running indefinitely. These cross-platform integration results and artifacts are pending a workflow run. Linux users also need a running Secret Service keyring; Linux CI installs `libsecret` headers and starts GNOME Keyring for the check.

Android local-network permission coverage is not complete. This Flutter toolchain currently targets API 36. Android 16 offers opt-in local-network blocking, where LAN TCP and UDP can fail unless nearby-device access is granted; CI currently uses an API 35 emulator and does not exercise that opt-in. Android 17 requires apps targeting API 37 or later to declare and request `ACCESS_LOCAL_NETWORK`, which this app has not implemented. Before raising `targetSdkVersion` to 37, add and test the runtime permission flow for user-started pairing/discovery, including denial and later revocation. See the [Android local network permission guidance](https://developer.android.com/privacy-and-security/local-network-permission).

The Windows Flutter release build was retried on 2026-10-27 against this checkout. The Rust release library compiled, but Flutter stopped before compiling the app because plugin builds require Windows symlink support; Developer Mode is disabled on this workstation. Android ARM64 and x86_64 Rust release libraries both compile locally; the x86_64 output was verified as ELF machine 62. The pairing Android release APK now builds successfully after Google Maven dependencies resolved; its merged manifest sets `android:allowBackup=false`. Physical Android runtime pairing remains unverified.

The four opt-in same-host private-interface transport tests passed on this Windows host: TLS bootstrap, wrong-secret rejection followed by approval, host rejection, competing joiners (only one can pair), and restart/replay rejection. They use one host and do not establish cross-device network behavior, OS permission behavior, or physical TV support. They were run with `MIRQUOVA_PAIRING_TEST_IPV4=192.168.1.38` and the ignored `pairing_transport::tests::local_private_interface_pairing` tests. The older generated APK and its digest predate the pairing dependencies and are not a pairing build artifact.

## Generated Android APK

- Build output: `apps/mirquova_flutter/build/app/outputs/flutter-apk/app-release.apk` (pairing release build, 2026-10-27).
- SHA-256: `e4fb2c1f704fa606f63c6138c96c9e6565ff06a47a287cbcdaa70b042a6b1f87`.
- Size: 79083913 bytes. Flutter's release build is signed with the local development key; it is not a production/store release.
- `artifacts/platform-preview-2026-10-27/android-arm64/Mirquova-0.3.0+3-android-arm64-debug.apk` is an earlier debug artifact from before pairing and is not pairing-build evidence.

The first Gradle wrapper download was interrupted after making slow progress. An official `downloads.gradle.org` download was verified against the repository's pinned SHA-256 (`17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43`) and used to seed the wrapper cache. The subsequent build completed after resolving first-build dependencies. No Gradle repository URL, checksum, dependency version or lockfile was changed.
