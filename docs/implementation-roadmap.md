# Implementation roadmap

This is a derived sequence, not proof of delivery or an instruction to execute every milestone immediately.

| Milestone | Deliverable | Exit evidence |
| --- | --- | --- |
| Preparation | Preserve input, analyze architecture, inventory tools | Workspace checks and explicit gaps |
| Infrastructure | Real Flutter Windows/Android shell, Rust workspace, typed bridge, CI and dependency notices | Analyze/test/build outputs on available hosts |
| Discovery spike | Platform-neutral discovery, fixture tests, real mDNS and manual fallback | Two-device discovery; malformed/stale record tests; peers remain unverified |
| Pairing | Reviewed authenticated identity flow, pinning, revoke, protocol negotiation | MITM/replay/wrong-code/revocation tests and explicit verification UX |
| Transfer slice | Windows to Android and reverse, disk streaming, consent, progress, cancellation, SHA-256 | Physical-device round trips including empty and 1 GiB files |
| Transfer hardening | Resume checkpoints, folders, conflict rules, retry and authenticated fallback | No traversal/corrupt resume; network loss and low-storage recovery |
| App casting | Windows/Android native capture with WebRTC | Physical LAN 720p30 measurements, permissions, visible stop, disconnect cleanup |
| ACE TV receiver | Signed TV package, remote UX, receiver/session state and decoder probes | Physical DE1L OS/ABI verification, install, D-pad, codec and stop tests |
| Player | Local MP4, offline captions, track controls, history, resume and timing | Windows/Android and TV playback evidence; seek/restart tests |
| LAN media | Per-peer/file-approved byte-range endpoint and playback | HEAD/GET/206/416, seek, expiry/revoke, unauthorized requests and bounded IO tests |
| Online subtitles | Disabled-by-default provider, fixtures, privacy and quota handling | Fixture tests, then separately authorized live API evidence |
| Wider platforms | Capability-tested web receiver; independent other TV/desktop adapters | Device-specific support and packaging records |
| Distribution | Installers, signing, updates and license notices | Reproducible builds and per-platform installation QA |

## First coding iteration

Limit initial implementation to infrastructure and discovery. Use source-plan color direction (forest green, charcoal, restrained gold) when actual UI work begins; validate accessibility rather than treating color names as finished design. Leave incomplete features visibly unavailable rather than simulating accepted transfers or playback.

## Cross-cutting gates

- Record exact dependency/tool versions and license obligations before release.
- Version transport and FFI schemas; test cancellation and resource ownership.
- Keep keys, tokens, private paths and filenames out of logs and commits.
- No remote account required for LAN discovery/transfer/casting/player.
- Maintain actual pass/fail/blocked evidence; never equate a fixture with a real device run.
- Request the original player domain contract and P01-P22 matrix before claiming conformity.

## Current progress

Preview 03 completes local infrastructure builds and adds opted-in, expiring LAN presence. Physical two-device discovery remains outstanding. The pairing slice now includes a TLS 1.3 one-use invitation handshake, a separate mutual-certificate authenticated approval handshake, fingerprint confirmation, explicit host approval, OS-backed identity/trust storage, and local revoke controls. Rust unit tests and Flutter parser/storage tests pass on the Windows development host; all seven opt-in same-host private-interface transport scenarios pass, covering approval, rejection, competing joiners, replay rejection after restart, request version/role rejection, and client rejection of mismatched host response version/role. A local Android pairing release APK now builds, but cross-platform native runtime checks and Windows-to-Android device acceptance remain outstanding; trusted pins are not yet consumed by a later data session because transfer/casting services are not implemented. See iteration-03.md, pairing-design-review.md, and platform-builds.md.

The pairing messages now use a fixed v1 application protocol with explicit host/joiner role checks, separate from invitation JSON v2. Unsupported versions and role mismatches are rejected before identity enrollment. See the [pairing message contract](../shared/contracts/pairing-protocol.md).

The 2026-10-30 [pairing persistence review](pairing-persistence-review.md) fixes overlapping-session trust saves and synchronous save failures. Local Rust checks and 134 Flutter functional/native-FFI tests pass; physical-device pairing acceptance remains outstanding.

The requested app-update slice adds consented stable-release checks, direct package downloads with published-digest checks, and a local system package handoff in Settings. It does not complete Distribution: production signing, automatic desktop replacement, rollback and installation QA remain pending. See app-updates.md for the release contract and verification limits.

The requested platform expansion adds Linux/iOS runners, Rust library packaging, Unix build scripts and CI jobs alongside the existing macOS/Windows/Android runners. See platform-builds.md for actual checks and unavailable build hosts. Wider-platform and Distribution milestones remain open pending native CI results, signing and physical-device acceptance.

Local playback, local SubRip loading, and an authenticated file-transfer listener are now in the app. Same-host transfer tests cover approval, rejection, an empty file, and a name conflict. A Windows-to-Android transfer, screen capture, and a live OpenSubtitles call have not been run. A discovered name is still not a trusted peer or a cast target.
