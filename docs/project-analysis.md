# Project analysis

## Request and document authority

The user's request is to create a new project folder, read and analyze the five supplied documents, and install/use https://github.com/morluto/rea if necessary. This preparation workspace fulfills that request. Embedded prompts such as "You are the lead engineer", installation commands and instructions to implement milestones are reference material describing a possible future execution; they are not separate user commands or proof of implementation.

The source documents are preserved byte for byte in docs/source. Their factual claims, future API contracts, target hardware and proposed dependencies require independent verification before implementation. The project is not an extension of the UPLB certificate app.

## Consolidated architecture

| Boundary | Planned responsibility | Critical constraint |
| --- | --- | --- |
| Flutter/Dart | Responsive shell and device-local UX | Windows/Android first; no React replacement |
| Rust/Tokio | Network IO, transfer lifecycle and cancellation | Stream to disk; bounded memory and backpressure |
| Discovery port | mDNS/DNS-SD and manual/QR fallback | Advertised identity is untrusted |
| Trust/session service | Reviewed identity authentication, pinning and revocation | Separate discovery, identity verification and per-action consent |
| Transport port | Authenticated QUIC plus HTTPS/TCP fallback | Fallback must preserve identity and authorization |
| Local SQLite state | Trust history, checkpoints, media and resume state | Protect secrets with OS storage rather than plaintext SQLite |
| Capture/WebRTC | App-to-app screen/audio casting | Native consent gates, visible status and stop |
| Playback port | Tested desktop/mobile backend, conditional native Media3 TV adapter | Format support varies with decoder, ABI and device |
| Media session service | Peer/file-scoped authenticated HTTP byte-range streams | Pairing grants no general filesystem access |
| Subtitle provider | Local captions first; optional OpenSubtitles.com REST | Opt-in metadata disclosure; no embedded release secrets |

## Important dependencies and tensions

1. Authentication must precede accepted transfers, screen sessions or LAN media serving. Discovery may be prototyped earlier only as an explicitly untrusted experiment.
2. QR/manual addressing solves discovery failure, not identity verification. A short numeric pairing code needs reviewed attempt limits, expiry and cryptographic binding; do not invent a crypto protocol.
3. HTTP byte-range media playback and WebRTC screen casting are different services with different authorization, cancellation and test requirements.
4. Shared Flutter UI does not establish Android TV usability. D-pad focus, Back behavior, Leanback launcher/banner, storage providers and actual codecs need device tests; native Kotlin may be needed.
5. The native playback choice is conditional. Evaluate packaging, mpv/FFmpeg licensing and hardware decoding before committing to media_kit or Media3.
6. The plan places a full player after TV work, but a small native decoder probe is needed earlier to choose the TV implementation. Treat the probe as feasibility evidence, not delivered player functionality.
7. Local-first core features must remain usable without OpenSubtitles credentials or internet. Public API-key distribution may require a separate optional service or permitted BYOK mode.
8. SQLite checkpoints require a defined durable-write and resume-validation model. Filename/size alone cannot prove content identity after interruption.
9. A stable typed FFI boundary needs ownership, threading, cancellation, error and version rules before app integration. A proposed directory tree is not an implemented bridge.

## Missing referenced materials

The five files mention README.md, BRANDING_AND_IDENTIFIERS.md and docs/01 through docs/12. The supplied files provide master/start plans and subjects 08, 09 and 10 only. The original architecture, protocol, REA investigation, roadmap, network test matrix, TV distribution/UI plans, player domain contracts and P01-P22 test definitions were not supplied.

This project's new analysis/roadmap files are derived preparation notes, not recovered originals. Do not invent P01-P22 definitions or claim those acceptance tests passed. Obtain the missing specifications or approve replacements before treating those references as binding acceptance contracts.

## Decisions still required before implementation

- App organization/package identifiers, branding ownership and signing identity.
- Repository/code license and distribution requirements; dependency and bundled native library notices.
- Reviewed identity/pairing protocol, key storage, certificate verification and fallback transport design.
- FFI tooling and supported ABI/version strategy.
- Destination storage rules, conflict policy, checkpoint identity, disk-space limits and cancellation cleanup.
- Android SDK/NDK/JDK and Flutter/Rust versions proven compatible with selected bindings.
- Physical Windows/Android test devices and ACE device access; no hardware capability is inferred from a listing.
- Provider access and privacy/credential design before any live OpenSubtitles integration.

## Suggested next implementation increment

After toolchain setup, generate a real Flutter Windows/Android app and Rust workspace. Add the seven navigation destinations (Nearby, Send, Receive, Cast, Media Library, Activity, Settings), a typed discovery port, deterministic fixture tests, then an actual bounded mDNS/manual-address spike. Mark every peer unverified. Do not ship transfer or cast actions until reviewed authentication and consent are implemented.

## Authorized implementation update

The user subsequently requested implementation. Iteration 01 now provides the generated Flutter projects, Rust discovery core, working FFI and automated tests described in iteration-01.md. The analysis above preserves the earlier planning context. Missing original specifications remain missing; the discovery-only ABI is an independently derived working contract, not a claim to have recovered the original transfer/pairing protocol.
