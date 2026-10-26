# Codex Command — Initialize and Implement Mirquova

Copy the following prompt into Codex from the Mirquova repository root after installing required SDKs and configuring REA on your own machine.

---

You are the lead engineer for a new cross-platform application, **Mirquova**. Read all documentation under `docs/` plus `README.md`, particularly `docs/06-tv-platforms-and-distribution.md`, `docs/08-ace-de1l-target.md`, and the V4 `docs/09-media-player.md` through `docs/12-player-test-matrix.md`. Implement the project incrementally. The product must support Windows and Android first; then Android TV/Google TV (targeting ACE 43-inch DE1L LED-909 advertised Android 14 / Google TV, with physical hardware validation pending), then tested TV web receivers, macOS, iOS, Linux and Tizen/webOS/tvOS adapters as warranted. Keep separate modules for secure file transfer, app-to-app screen casting, cross-platform media playback and optional online subtitles.

## Mission

Build a production-minded local-first application with Flutter/Dart for responsive desktop/mobile UI, Rust/Tokio for transfer/network IO, SQLite checkpoints/trust history, QUIC with authenticated identities plus an authenticated HTTPS/TCP fallback, mDNS discovery and QR pairing, and WebRTC + native OS screen capture for *app-to-app* casting. Preserve user consent and platform permission gates. Do not require a remote server or user account for a local-network transfer.

## Use REA correctly

REA (`https://github.com/morluto/rea`) is a research tool, not our transfer implementation. Check if an REA MCP server is actually connected and list its advertised capabilities; don't pretend to call tools that are not available. Review LocalSend, PairDrop, RustDesk, Sunshine/Moonlight and GNOME Network Displays through public source/docs first. If local compiled binaries/APKs are supplied, and permission to analyze them is established, use REA for targeted observations, record exact artifact versions and evidence, and distinguish actual findings from assumptions. Never bypass OS capture permissions, DRM/HDCP, trust mechanisms or unauthorized access. Do not copy third-party branded assets or code without required license compliance. Record findings in `docs/rea-findings.md`.

## TV implementation requirements

Build Mirquova TV as a proper installable receiver on supported Android TV / Google TV, with TV-specific Leanback launcher/banner, landscape 10-foot design, focusable D-pad navigation, optional QR pairing and numeric pairing code, sender approval, persistent screen-casting indicator, stop controls and protected playback. Probe hardware codecs. Do not assume a standard phone APK makes a usable TV app. The ACE model is already identified as **DE1L LED-909** from a listing; do not ask for its model again. Verify actual OS version, CPU ABI, and install permissions on the physical TV when available; until then record them as unknown. Implement the cross-platform Mirquova Web Receiver separately as a capability-tested fallback; not all browsers support local discovery, WebRTC media, file saving or secure contexts.

After Android TV tests, explore Samsung Tizen `.wgt`, LG webOS `.ipk`, recent Flutter-webOS compatible models, Apple tvOS and Roku with platform-native toolchains. Treat genuine Miracast / AirPlay / Google Cast as separate standards integration, not an automatic side effect of WebRTC. Never promise APK installation on non-Android TVs or bypass store/device signing policies. Update platform support matrix only from actual runs.

## Work order — Do not skip to Miracast

1. Verify actual installed Flutter, Dart, Rust, Android SDK, Windows build tools and REA capabilities. Create `docs/environment-check.md` with concrete commands, versions, failures and fallback steps; if something cannot run, state so plainly.
2. Initialize a Flutter multi-platform app, Rust workspace, clear typed FFI boundary, dependency licenses, reproducible build instructions, CI and test runner. Ensure desktop/mobile responsive navigation with `Nearby`, `Send`, `Receive`, `Cast`, `Media Library`, `Activity`, `Settings`. Use rich forest green, dark charcoal, restrained gold, optional maroon, and accessible contrast. No React.
3. Implement peer discovery behind a platform-neutral interface; cover multicast failure with QR/manual IP and fake-peer test fixtures. Never trust mDNS claims as authentication.
4. Implement reviewed authenticated pairing, visible verification, persistent pinned peer keys, revoke trust and a protocol version handshake. Do not implement your own crypto primitives.
5. Implement an end-to-end functional Rust file transfer vertical slice: Windows ↔ Android, consent, streaming disk IO, progress, retries, SHA-256 verification and safe destination path handling. Then add batch folders, checkpoint-resume, conflict handling and fallback transport.
6. Integrate native screen capture and WebRTC sender/receiver separately: Windows Graphics Capture, Android MediaProjection and native renderers. Enforce screen-capture consent and Android foreground service requirements; show persistent session status and stop control. Start with 720p/30 on an actual LAN and optimize based on evidence. Treat genuine Miracast TV interoperability as an independent research-only future milestone.
7. Add an **Android TV receiver** target and physical-TV demo, verifying source-to-TV WebRTC, remote control, codec support, consent/stop, APK packaging and device model. Do not assume ACE OS.
8. Prototype the **TV web receiver**, then evaluate Tizen/webOS/tvOS/Roku adapters by device ability. Maintain explicit capability and release matrices. Do not conflate proprietary cast standards with WebRTC.
9. Implement **Mirquova Media Player** in independently testable vertical slices: (a) player abstraction, Windows/Android local MP4; (b) ACE TV remote-first player and local SRT/embedded captions; (c) playback position and subtitle timing; (d) secure consent-scoped byte-range LAN stream for TV; (e) mocked OpenSubtitles.com provider; (f) optionally live integration through official `GET /subtitles`, `POST /download` with authorized API key/account and quota management. No web scraping, legacy .org API or hard-coded keys. Match by moviehash/IDs/filename where appropriate. Include local SRT fallback and privacy notice. Read docs 09–12 before coding.
10. Add automated unit, integration, protocol fuzz/property and threat-model tests, plus repeatable throughput/latency benchmarks against reference apps under equal conditions.
11. Document every feature implemented, every platform validated, outstanding risks, release packaging and requirements. Do not claim unsupported capabilities or benchmark wins.

## Deliverables per iteration

- Actual working code with clear module boundaries and no mock-only substitutions in accepted features.
- Current list of created/modified files, test output including pass/fail, real device tests vs emulated tests, and next blocking tasks.
- A checked-off acceptance checklist with working demo instructions.
- Architecture decisions with source and licensing references.

## Immediate first iteration

Complete only stages 1 and 2 and a small working discovery spike from stage 3. Create initial code and tests, run available checks, report exact outputs and blockers, and stop before claiming that the whole app or screen casting is finished.

---

To run locally after REA setup on a supported PC:

```powershell
npx rea-agents setup
# Select Codex, review approvals, restart Codex and paste the prompt above.
```

Source reference: https://github.com/morluto/rea

## ACE DE1L update

Treat `docs/08-ace-de1l-target.md` as the authoritative ACE model-specific acceptance plan. Add TV launcher manifest flags, D-pad focus acceptance and a legitimate signed APK installation workflow. The listing is not proof the APK has been tested or installed. Explicitly separate app-to-app WebRTC cast from native Google Cast and Miracast.

## V4 requirements — explicit player work queue

- Preserve all prior stages and the ACE DE1L physical-test gate. Introduce **Media Library**, **Play from PC**, **Continue Watching**, full-screen **Player**, and **Subtitles** to the application specification.
- Reuse the Flutter navigation shell and player facade, but implement native Kotlin AndroidX Media3 ExoPlayer adapter for Android TV if libmpv/media_kit does not meet ACE actual decoder, packaging or D-pad acceptance. Treat format/codec support as evidence-based.
- Implement caption Off, embedded subtitle selection, manual SRT/VTT and ASS/SSA where proven, adjustable font/position/timing, resume after restart, and user-selected offline sidecar loading.
- Separate user-approved network file **streaming** (authenticated HTTP byte ranges and per-file authorization) from WebRTC **screen casting**. No unapproved directory/file access.
- Build an optional OpenSubtitles.com provider using the current REST API. Never silently query private filenames; obtain opt-in. Require `Api-Key`/valid `User-Agent` and optional bearer login when applicable, handle dynamic rate limits, download quota and temporary URLs, validate subtitle files and safe cache names, and keep keys out of release apps and logs.
- New acceptance: `docs/12-player-test-matrix.md` P01–P22. If OpenSubtitles keys are missing, use recorded fixtures, isolate the integration behind a feature flag and report live checks BLOCKED, not PASS.
- The first Codex iteration is still infrastructure and transfer groundwork as requested above; do **not** falsely claim a completed player, OpenSubtitles connection or installed ACE APK.
