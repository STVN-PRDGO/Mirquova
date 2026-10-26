# Mirquova — Master Implementation Plan (V4)

**Product:** Mirquova — Every screen. One connection.  
**Documentation status:** Architecture plan (not a completed app).  
**Initial platforms:** Windows + Android; then **ACE 43-inch DE1L LED-909** Google TV-targeted APK, with hardware/firmware verification required.  
**Core features:** secure file/folder transfer, screen casting, TV receivers, built-in media player, subtitle support, OpenSubtitles.com lookup.

## 1. Purpose and scope

Mirquova is a single cross-device software ecosystem with platform-specific builds. Users should be able to discover nearby devices, approve a secure connection, send arbitrary file types without compulsory cloud accounts, cast their screens between Mirquova apps, and watch local or approved remotely streamed videos with selectable captions.

Cross-platform does **not** mean one APK works on every Smart TV. Android TV/Google TV uses an Android TV-compatible signed APK; Samsung Tizen, LG webOS and Apple tvOS need independently tested packages/adapters or a restricted browser receiver.

## 2. Architecture

| Layer | Planned technology | Responsibility |
|---|---|---|
| UI / app shell | Flutter + Dart | Desktop/mobile UI, navigation, history, settings |
| Network + transfers | Rust + Tokio + QUIC | Stream file chunks to disk, retries/resume, hashes, rate statistics |
| Discovery | mDNS / DNS-SD + manual QR/IP fallback | Discover peers; **not** proof of identity |
| Pairing / trust | Audited cryptographic identities and verified pairing | Authenticated sessions and peer revocation |
| Screen casting | WebRTC + OS screen capture | Mirquova-to-Mirquova stream; separate from Miracast |
| Android TV receiver | Android TV package, native Media3 as needed | D-pad-first cast receiver + player |
| Media playback | Platform-tested Flutter `media_kit`, and/or Android Media3 | Local video, caption tracks, seek/resume |
| Local state | SQLite | Trusted peers, resumable jobs, local library, watch progress |
| Subtitles online | Official OpenSubtitles.com REST API | Opt-in matching, search and authorized download |
| Reverse-engineering research | [REA](https://github.com/morluto/rea) + lawful source study | Inspect behavior/architecture; not the transfer engine |

**System security:** user approval for transfers and casts; protect session keys; safe destination paths; stream without buffering entire files; never bypass DRM, device permissions, signing, or pairing checks. No embedded OpenSubtitles API secrets in released apps.

## 3. Functional modules

### 3.1 Mirquova Connect

- Find nearby supported devices with mDNS; fall back to QR code / PIN or manual IP on networks that block multicast.
- Verify identities and pair; display sender/receiver identity and consent prompts.
- Support explicit trusted-device revocation.

### 3.2 Mirquova Transfer

- Send files of arbitrary type or folders; handle duplicates, cancellation, queued jobs and resume from validated checkpoints.
- Authenticate senders, stream transfers, verify integrity via SHA-256 and sanitize file paths.
- Compare performance to alternatives under identical network/hardware conditions; no unsupported speed promises.

### 3.3 Mirquova Cast

- Implement Windows capture with OS APIs and Android capture via MediaProjection, transported via WebRTC to a Mirquova receiver.
- Require visible consent and always-accessible stop control.
- Optimize progressively for 720p30, then higher profiles where device measurements support them.
- Real **Miracast**, Google Cast and AirPlay compatibility are **separate** research and standards integration work, not implied by WebRTC.

### 3.4 Mirquova TV (ACE target)

- Create a 10-foot, landscape Android TV experience with D-pad focus, legible typography and launcher metadata.
- Receive approved files or streams, mirror accepted casts, play compatible media, show pairing code and QR.
- Benchmark on the user's ACE DE1L LED-909 after verifying actual OS, ABI, codecs and third-party APK install permissions.
- Plan a Web Receiver as a fallback on non-Android TV browsers, with browser capability checks instead of universal compatibility claims.

### 3.5 Mirquova Media Player

- Support local media, received media, and consent-scoped authenticated byte-range streams from paired devices (no need to transfer full video first).
- Expose embedded/external subtitles, track selection and subtitle Off; validate `.srt`, `.vtt` and advanced formats `.ass/.ssa` based on playback backend evidence.
- Include audio track selection, playback position/resume, subtitle delay and readable TV remote controls.

### 3.6 OpenSubtitles.com integration

- Keep offline local subtitle handling fully functional independently.
- Ask permission before sending filename/hash/movie metadata online; match via supported hash/ID/title language criteria.
- Search the current official `.com` REST API; download through authorized API endpoints with rate-limit, quota and failure handling.
- Do not scrape the website or evade account limits; protect API credentials with a permitted server-side proxy or other authorized credential mode as required.

## 4. Build order and acceptance milestones

| Milestone | Build deliverable | Acceptance gate |
|---|---|---|
| M0 Research/setup | Environment check, REA research notes, repo structure | Accurate inventory and license review |
| M1 Discovery/pairing | Windows ↔ Android discovery and secure peer pairing | Local/QR fallback; peer identity check |
| M2 Transfer MVP | Bidirectional file transfer and progress | Verified integrity; permission prompts; 1 GiB test |
| M3 Transfer hardening | Resume, folders, retry/cancel, conflict UI | No corrupted resumes or unsafe paths |
| M4 App-to-app cast | Windows/Android WebRTC mirroring | Approved, stoppable session on physical LAN |
| M5 ACE Android TV | Mirquova TV APK + cast/file inbox | Test on **physical ACE model**, D-pad and codec QA |
| M6 Media player | Local/received/LAN video + offline captions | Playback, seeking, resume and subtitles pass |
| M7 OpenSubtitles | Opt-in search/download + quota handling | Fixture tests and live API test only when authorized |
| M8 Wider platforms | macOS/iOS/Linux; optional Samsung/LG/tvOS and Web Receiver | Each platform marked supported only after testing |
| M9 Distribution | Signed installers, packaging, store compliance | Per-platform installation and update QA |

Note: build steps can be decomposed in parallel after secure transfer and stable protocol foundations. Detailed criteria: `docs/04-implementation-roadmap.md`, `docs/05-test-matrix.md`, and `docs/12-player-test-matrix.md`.

## 5. First Codex execution

1. Read `README.md`, `BRANDING_AND_IDENTIFIERS.md`, `docs/01-architecture.md` through `docs/12-player-test-matrix.md` and `CODEX_START_PROMPT.md`.
2. Check actually installed tools, SDKs and REA configuration; document what is missing.
3. Scaffold a working Flutter/Rust cross-platform shell using the name **Mirquova** and identifiers from the brand policy (subject to verification).
4. Write tests and implement a minimal discovery demo; do **not** claim a working file transfer, cast or subtitle search before end-to-end tests.
5. Follow the milestone gates, logging actual test evidence for desktop/mobile and real ACE TV when available.

## 6. Where to read next

- `README.md` — project summary and reference links
- `docs/01-architecture.md` — full design
- `docs/02-protocol.md` — discovery/security/transfer contract
- `docs/03-rea-investigation.md` — REA research workflow
- `docs/04-implementation-roadmap.md` — phases in detail
- `docs/05-test-matrix.md` — network/casting/security tests
- `docs/06-tv-platforms-and-distribution.md` — TV operating systems, build routes
- `docs/07-tv-ui-and-acceptance.md` — TV interface requirements
- `docs/08-ace-de1l-target.md` — ACE hardware validation checklist
- `docs/09-media-player.md` — player feature design
- `docs/10-opensubtitles-integration.md` — APIs, permissions, quotas
- `docs/11-player-api-and-domain-contract.md` — module/API contracts
- `docs/12-player-test-matrix.md` — player/subtitle acceptance cases
- `BRANDING_AND_IDENTIFIERS.md` — name, package and migration notes
- `CODEX_START_PROMPT.md` — actual code-generation workflow

**No application binaries are included in this documentation package.**
