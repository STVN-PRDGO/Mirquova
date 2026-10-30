# Local virtual testing, 2026-10-30

Tested the uncommitted pairing-persistence worktree on the local Apple Silicon
Mac using the installed Pixel_10a Android emulator. This supplements the earlier
unit/widget checks; it does not establish physical-device support.

## Android native runtime

The emulator ran an ARM64 Android API 37 system image with 16 KiB pages. The app
still targets API 36; this run does not validate the future API 37 target's
local-network permission flow. The emulator was started headlessly with software
graphics. The Android Rust release library was rebuilt with cargo-ndk and the
locked dependencies before running Flutter's native integration test:

```sh
source scripts/Use-Toolchains.sh
cargo ndk -t arm64-v8a --platform 24 \
  -o apps/mirquova_flutter/android/app/src/main/jniLibs \
  build -p mirquova-core --lib --release --locked
cd apps/mirquova_flutter
flutter test integration_test/native_app_platform_test.dart \
  -d emulator-5554 --no-pub
```

The test passed (one integration test, five seconds after startup). Its progress
markers confirmed all of the following:

- Installed package metadata loaded through the native platform bridge.
- A native identity was generated, saved to Android secure storage, reloaded and
  validated. Temporary keys were isolated from normal app pairing storage.
- A public peer pin was stored, reloaded, revoked and confirmed absent.
- The real Rust FFI rejected a wrong fingerprint and a public bind address.
- A listener on the emulator's private interface started and stopped cleanly.
- The Pair route loaded with the QR scanner entry point.
- Settings update consent was cancelled without requesting releases, and invalid
  release URLs were rejected by the native channel.

The normal `lib/main.dart` debug APK was then rebuilt, installed and opened.
Nearby started hidden with zero discovered peers and no automatic scan. Nearby
and Pair screenshots were inspected; no visible overflow or error banner was
observed. No pairing invitation or camera session was started during that UI
inspection. The emulator was left running on the Pair screen.

Local screenshots (ignored by Git):

- `local-evidence/virtual-2026-10-30/android-nearby.png`
- `local-evidence/virtual-2026-10-30/android-pair.png`

Normal APK: `apps/mirquova_flutter/build/app/outputs/flutter-apk/app-debug.apk`.
SHA-256: `6bd05d2159d37248155da2e04db452ba6f53624c430071e0fcfd64e5d5b4e362`.
This is a development-signed build, not a release package.

## Mac transport checks and limitations

Two loopback Rust TLS tests passed: pinned-CA mutual authentication and rejection
of an unrelated CA. These exercise actual local TLS sockets, not two devices.

The seven opt-in `local_private_interface_` scenarios initially returned success
while explicitly printing that no connectable RFC1918 interface was available.
Those were skipped scenario bodies, not successful pairing runs. Rerunning with
the Mac's actual private Wi-Fi address explicitly selected exposed failures:

- The mismatched-host-role case received `bootstrap_write` instead of the
  expected `protocol_mismatch` error.
- That failure poisoned the test serialization mutex, so the remaining six
  scenarios failed on the poisoned lock and were not independently evaluated.
- An isolated approval scenario failed with `WouldBlock` (OS error 35) while
  reading the initial protocol-rejection response, after about three seconds.

The root cause of private-interface transport failure is unresolved. The Android
listener smoke and Mac loopback TLS pass do not resolve or override it. No
firewall, privacy or network configuration was changed.

Native macOS and iOS runner tests are unavailable on this host: only Apple
Command Line Tools are installed, without full Xcode or the simulator tools.

The separate Android discovery integration test was not executed. Automatic
approval review rejected its short LAN presence advertisement because the user
had requested virtual testing without explicitly authorizing disclosure to
nearby LAN devices. It remains pending explicit approval. No live release or
subtitle API requests were made. Cross-device pairing, discovery round trips,
camera scanning, transfers, casting, playback and TV operation remain untested.
