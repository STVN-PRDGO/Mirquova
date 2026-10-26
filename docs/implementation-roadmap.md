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

Preview 03 completes local infrastructure builds and adds opted-in, expiring LAN presence. Physical two-device discovery remains outstanding. Pairing has a design review but no implementation; see iteration-03.md and pairing-design-review.md.
