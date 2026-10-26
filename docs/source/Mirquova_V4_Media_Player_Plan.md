# 09 — Mirquova Media Player: Cross-platform design specification

**Status:** Proposed functionality only. No video player or OpenSubtitles integration has been built/tested as part of this documentation.

## Product goal

Mirquova becomes a **receive, stream, cast, and watch** application. A user can open local media, received media in the Mirquova inbox, or media streamed from an authorized paired device. Subtitle selection must work with local/embedded tracks even without internet. Online OpenSubtitles lookup is an explicitly optional online feature; it never blocks playback, transfer, or local casting.

## Functional requirements

| ID | Function | MVP acceptance requirement |
| --- | --- | --- |
| MP-01 | Open video | Choose a local/SAF-selected file or accepted inbox video; show a useful error if unsupported. |
| MP-02 | Supported containers | Test MP4 (H.264/AAC) first; attempt MKV, MOV, AVI, WebM and others only via verified installed decoders. Never claim 'all codecs'. |
| MP-03 | Transport playback | Play remote file from paired device over authenticated LAN endpoint supporting HTTP `Range` and `206 Partial Content`, efficient seek and cancellation; never require downloading full movie. |
| MP-04 | Transport consent | Sender explicitly authorizes media-stream session; pairing alone is not blanket permission to access its disk. Stream URL/token is short-lived and bound to file + peer. |
| MP-05 | Player UI | Play/pause, ±seek, scrub, elapsed/duration, skip, volume, speed, aspect fit, fullscreen, error/retry; appropriate mobile/desktop/TV layouts. |
| MP-06 | Tracks | List/change embedded audio and subtitle tracks; allow subtitles Off; preserve current audio while switching subtitles. |
| MP-07 | External captions | Load `.srt`, `.vtt` and `.ass`/`.ssa` where selected native backend proves support. Recognize same-basename language sidecars. |
| MP-08 | Accessibility | Prefer hearing-impaired/SDH tracks when requested; optional forced-only subtitles, contrast, scalable subtitles, navigation focus. |
| MP-09 | Sync and styling | Adjustable subtitle offset (suggested ±10s in 100ms increments), size, foreground, outline/background, screen positioning; know which backend's features vary. |
| MP-10 | Online lookup | Optional OpenSubtitles search/preview/download/select, language preferences, ranked exact/hash matches; download quotas and errors in UI. See docs 10-11. |
| MP-11 | Playback history | Resume timestamp per user/device and stable content identity; auto-save on pause and periodically; 'Start over' action; opt-out/delete history. |
| MP-12 | Playlist | Received videos folder/library queue; Previous/Next, optional autoplay; never silently scan entire filesystem. |
| MP-13 | Privacy and offline | Local video metadata stays local by default; external API calls happen only after clearly enabled online subtitle discovery. No internet required for player core. |
| MP-14 | TV controls | 10-foot D-pad focus, Select/Pause, arrows seek, Back hides controls then exits, captions easily reachable, no touchscreen dependency. |

## Recommended playback architecture

Use an **adapter** (`MediaPlaybackPort`) instead of mixing playback, streaming, UI, and subtitle HTTP calls.

- **Windows/macOS/Linux and mobile Flutter:** evaluate `media_kit` (libmpv-based) and its video dependencies. It advertises local/remote playback, embedded audio/subtitle tracks, `SubtitleTrack.uri`, `SubtitleTrack.data`, style customization. Confirm current platform/plugin compatibility, decoder performance, packaging and FFmpeg/mpv/library licensing before committing. Documentation: https://pub.dev/packages/media_kit and https://pub.dev/documentation/media_kit/latest/ .
- **ACE Android TV / Google TV:** prefer a hardware-efficient **AndroidX Media3 ExoPlayer** native Kotlin player adapter if the Flutter adapter is insufficient for remote/D-pad/decoder/ABI reliability. Media3 officially supports standalone SubRip, WebVTT, SSA/ASS and TTML in current releases; individual embedded formats and codecs remain device dependent. Documentation: https://developer.android.com/media/media3/exoplayer/supported-formats and https://developer.android.com/media/media3/exoplayer/hello-world .
- **Web receiver, Tizen, webOS and tvOS:** use the platform native media stack and compatible formats rather than pretending the Flutter/mpv binary runs on every TV. Browser `<video>` + WebVTT where supported; some TV browsers cannot decode MKV/ASS. Playback/seek/status features are capability detected.
- **Rust core:** continues to handle paired transfer and authenticated range-stream delivery, not video decoding. New service `MediaCatalog` indexes only user-permitted media. User-selected URLs must be validated to prevent SSRF/loopback abuse.

### Module boundaries

```text
apps/mirquova_flutter/
  lib/features/player/             # shared UX, player state, caption UI
  lib/features/subtitles/          # local tracks + provider chooser
  lib/core/media_playback_port.dart
  lib/adapters/media_kit_player_adapter.dart
apps/mirquova_tv_android/         # optional Kotlin Android TV target/adapter
  media/Media3PlayerAdapter.kt
crates/mirquova-core/src/media/   # authenticated LAN streaming/session and range server
crates/mirquova-core/src/security/
shared/contracts/                  # generated/typed player & subtitle state
```

### Receiving vs streaming

- **Play after transfer:** accepted video is stored in app inbox, then opened from local file handle. Delete/rename operation updates history links.
- **Play without full transfer:** receiver requests `media.play` on approved paired sender; sender grants restricted stream access, implements `HEAD`, `GET` + `Range` with content size, type and non-guessable session token; TV player seeks by byte range. Reject unauthenticated browser/other LAN clients. Only serve previously approved files. Provide immediate Stop/Share Off, idle expiry and backpressure.
- **Casting vs direct media play:** if the receiver can decode a video, prioritize direct media stream to TV over re-encoding a PC's player as a screen cast. Screen casting remains a distinct real-time WebRTC mode for arbitrary desktop screens.

## Subtitle track behavior

1. Enumerate embedded caption tracks from the player adapter, preserving language/type and Off option.
2. Discover same-folder sidecars only when storage permission grants access: e.g. `Film.mkv`, `Film.en.srt`, `Film.en.sdh.srt`; never browse globally.
3. Provide **Load local subtitle** via system picker; accept untrusted text as data only, limit decompression/encoding/memory and reject malicious paths.
4. Provide **Find Online Subtitles** in a separate drawer/modal. Search occurs only after user selection or after separate per-device opt-in to auto-search. See `docs/10-opensubtitles-integration.md`.
5. Save the selected online subtitle in scoped app storage, keyed to video fingerprint and language; don't use movie name as a trusted filesystem path. Allow local re-use offline subject to OpenSubtitles rights/terms.
6. Support subtitle time shifting without modifying original file; store offset preference per video/track.

## ACE TV-specific UX

- From TV Home, add **Media Library**, **Continue Watching**, **Recent Transfers**, **Play from PC**, **Settings**.
- Player overlay: title/time progress, big Play/Pause, Seek, Audio, **Subtitles**, Find Online, Download status, subtitle offset/font, Back, Stop Stream.
- Make caption menu and result selection fully navigable using D-pad. Use 10-foot-scale text and preserve focus on dialog reopen.
- On TV, avoid asking users to type OpenSubtitles passwords with a remote. Option A: configure access with an explicit companion phone/desktop settings flow; option B: locally load subtitles on sender and forward as an authorized paired transfer. Do not assume OpenSubtitles offers OAuth/device-code login—verify API authentication contract first.
- Start with a known H.264/AAC 1080p sample and SRT subtitles; attempt 4K, 10-bit HDR, HEVC/AV1, TrueHD/DTS only after detecting supported chip/decoder/audio pipeline. Codec/container support must be measured on the real ACE DE1L device.
- During buffering/dropped LAN: player shows Recover/Stop; never expose sender disk filenames without permission. TV cache quota and cleanup policies required.

## UX acceptance story

1. Windows shares `Example.Movie.mp4` via approved media session to Mirquova ACE TV; player begins without full file transfer.
2. TV operator presses remote Select, chooses Subtitles → Load local `.srt` or Find Online (opted-in), chooses English, then adjusts timing.
3. Video remains playing while subtitle track changes; seek works; pause/resume persists across app restart.
4. Disconnect internet: local video + previously downloaded subtitle still work, and online action indicates offline state (not player failure).
5. Cancel media session on sender: receiver stops promptly; session token invalidated.

## Non-goals / constraints

- No copying or bypassing protected Netflix/Disney+/other DRM sources; no unauthorized media hosting, ripping, or DRM/HDCP circumvention.
- Do not bypass subscription, licensing, provider quotas, geo-blocking or app-store requirements.
- Player format support is **not** a promise that all media files decode on a low-cost TV.

## References

- https://pub.dev/documentation/media_kit/latest/
- https://developer.android.com/media/media3/exoplayer/supported-formats
- https://developer.android.com/training/tv/get-started/create
- https://developer.android.com/training/data-storage/shared/documents-files
