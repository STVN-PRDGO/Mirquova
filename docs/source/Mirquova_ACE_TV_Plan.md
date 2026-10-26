# 08 — ACE 43-inch Smart Google TV DE1L LED-909: device-specific delivery and test plan

Status: **Target model identified from a product listing; NOT hardware-verified or installed yet.**

## Identification and evidence

User-provided Shopee screenshot shows: "ACE 43" Smart Google TV DE1L LED-909 (Android 14, Netflix, Youtube, Chromecast, BT, ISDB, Soundbar)". Listings corroborate this product/advertised configuration: https://shopee.ph/ACE-43-Smart-Google-TV-DE1L-LED-909-%28Android-14-Netflix-Youtube-Chromecast-BT-ISDB-Soundbar%29-i.71024418.21928550023 .

**Working hypothesis:** Android TV / Google TV environment, Android 14 as advertised, with Chromecast capability as advertised. This is sufficient to target a dedicated Android TV APK; it does **not** prove the exact firmware version, CPU architecture/ABI, Play Store distribution eligibility, sideloading access, hardware AV1/H.265 decoding, Miracast receiver mode, wireless debugging access, or Google Cast SDK interoperability.

## Release target / platform strategy

- Package name suggestion: `com.mirquova.tv` (confirm availability, signing identity and branding before release).
- Build a **TV-specific receiver** with landscape layout, overscan-safe spacing, remote D-pad focus, Back handling, home screen icon, banner, permissions and visible connection state. Reuse Rust transfer/session layers shared with Windows/Android; do not reuse touch-first phone screens unchanged.
- Android TV app manifest: TV launcher activity `android.intent.category.LEANBACK_LAUNCHER`, `android.software.leanback`, `android.hardware.touchscreen required=false`, TV banner and leanback icon. Adjust main vs TV launchers for multi-target app design.
- Flutter may work for the TV UI with Android-specific work, but is not guaranteed to provide every native TV feature by default. If focus/accessibility/media playback fail, use a native Android Kotlin/Compose for TV receiver UI connected to the same Rust core via JNI/FFI.
- APK must be signed and built for actual TV CPU architecture; test installed architecture via `adb shell getprop ro.product.cpu.abilist` when debugging access is enabled.
- Ship an independent APK for testing/sideload, and pursue the Google Play TV track after meeting Google's current TV quality, icon, banner, launcher and remote navigation requirements. A phone APK need not appear on TV Play Store.

## Proposed TV features (implement, don't assume shipped)

**P0 receiver:** LAN discovery QR/manual IP fallback; pairing PIN/QR and human-readable trust prompt; explicit sender approval; receive photos/videos/music/documents or arbitrary binary file into private app storage; progress, size, free-space check, checksum and reject; stream media with seek where possible; show PC/Android app-to-app WebRTC mirror; always-visible Stop Cast.

**P1 sender/media:** TV to PC file selection where provider permissions permit, resume, USB/selected folder destinations, compatible subtitle and container playback, network quality overlay, throughput analytics.

**P2 standards:** Google Cast sender-to-receiver via Cast Connect / appropriate Google SDK pathway if justified by product goals; true Miracast receiver/device compatibility as separate feasibility and driver/hardware verification effort. Built-in Chromecast support does not turn our app into a generic Miracast receiver. Generic Mirquova WebRTC mirroring requires Mirquova on sender and receiver. DRM/HDCP-protected content may be unavailable for capture.

## Storage and permission strategy

On Android 14, plan around scoped storage. Use app-specific external/internal files for initial receiver inbox (quotas/free-space monitoring). For user-selected persistent shared folders, use Android Storage Access Framework where available, and persist granted URI permission correctly. Don't claim unrestricted TV file system access or silently save to protected folders. Modern Android restricts `ACTION_OPEN_DOCUMENT_TREE` for storage roots and Downloads root. Some TV firmware may not ship a useful file picker. Do not request broad `MANAGE_EXTERNAL_STORAGE` by default. Check external USB storage support, SAF provider presence, decoding and removable-drive access on the physical device.

References: https://developer.android.com/training/data-storage/shared/documents-files and https://developer.android.com/about/versions/11/privacy/storage

## Test setup on the actual ACE TV

1. On TV: Settings → System → About. Record actual Android version, build number, device name, total/available storage, Google Play availability and Wi-Fi network. Paths may vary by vendor firmware.
2. Verify TV and sender are on the same trusted LAN. Confirm multicast/mDNS behavior; test manual IP/QR fallback if discovery fails (especially if AP isolation or client isolation is on).
3. Build a TV-compatible release APK. Try installation via a legitimate file manager/TV installer if firmware allows it, or use developer/ADB installation when authorized and available. On newer Android TV builds, ADB pairing/setup behavior varies; do not assume port 5555 or Wi-Fi debugging exists on this model.
4. If ADB enabled and authorized, examples: `adb devices`, `adb install -r path/to/mirquova-tv.apk`, `adb shell getprop ro.build.version.release`, `adb shell getprop ro.product.cpu.abilist`. If install fails, record the exact Android error and fix ABI, signing or manifest issues instead of circumventing device security.
5. Test controller: Up/Down/Left/Right/Select/Back; no touch or mouse required. Test dialogs, QR code legibility, TV sleep/wake, interruptions, orientation and overscan.
6. Transfer phone ↔ TV 100 MB file, 1 GB file if storage permits, multiple-file batch and a zero-byte item; compare SHA-256, retry on LAN disconnection, test low-storage rejection and concurrent incoming offers.
7. Stream H.264/AAC MP4 1080p and measure start time, A/V sync, sustained playback, seeking and overheating. Codec support is to be measured rather than assumed; allow player/streaming fallback where possible.
8. Cast Android → TV and Windows → TV via Mirquova WebRTC at a conservative 720p/30 target before trying 1080p/60. Validate latency on the same LAN, device CPU/temperature, orientation, audio routing, permissions, disconnect and stop behavior. Do not promise 60 FPS on this TV until benchmarked.
9. Record build/install/playback success in the test matrix and attach logs/screenshots only from authorized devices.

## Minimum acceptance criteria

- [ ] Actual model/OS/ABI verified on device (not listing only)
- [ ] APK installs, opens from Google TV home, survives restart
- [ ] Full remote-only navigation and accessible status
- [ ] PC/phone finds TV via discovery or QR/manual IP fallback
- [ ] Pairing requires user approval; untrusted senders rejected
- [ ] File transfer works with SHA-256 match, interruption handling and space checks
- [ ] Media playback works for a tested H.264/AAC file
- [ ] Mirquova screen mirroring works with explicit consent and stop control
- [ ] No unsupported native Miracast/Chromecast compatibility claims
- [ ] Firmware, CPU ABI, storage, codec/latency/performance and failure logs documented

## Codex task (ACE-specific)

> Read `README.md`, all existing `docs/` and this `docs/08-ace-de1l-target.md`. Update the compatibility matrix with the ACE DE1L LED-909 as **advertised Google TV / Android 14, untested hardware**. Implement a dedicated TV entry point, Leanback manifest metadata, remote D-pad focus paths, 10-foot home screen, paired receiver state machine, explicit send approval and media session UX. Provide ADB install instructions and physical-device smoke test script. Reuse the transport and casting engines; do not stub them and claim they work. Do not claim device validation until the actual TV has been tested. After Android TV acceptance, continue to other platforms.

## Primary standards documentation

- Android TV app creation: https://developer.android.com/training/tv/get-started/create
- Google TV guidance: https://developer.android.com/training/tv/get-started/google-tv
- Cast Connect receiver overview: https://developers.google.com/cast/docs/android_tv_receiver

## V4 ACE DE1L media-player requirement

Implement local H.264/AAC MP4 + SRT playback in a TV-focused UI, then optional approved Windows→TV streaming with byte-range seeks; resume playback and adjust subtitle timing using **remote-only** D-pad controls. Query embedded tracks where supported, handle AV sync and low storage, and log actual decoder hardware capability. For OpenSubtitles use modern `.com` API only after authorized application access has been configured; a remote control should never force users to type provider passwords if companion setup is possible. Provide manual local SRT import even if online API is unavailable. Follow docs 09–12 and add all P01–P22 checks to the ACE signoff. No full video playback or OpenSubtitles flow has been tested on the user's physical ACE TV.
