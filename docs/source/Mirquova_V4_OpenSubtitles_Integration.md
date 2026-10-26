# 10 — OpenSubtitles.com Subtitle Search/Download Integration

**Status:** Proposed integration; no API key was supplied, no live authenticated request was executed, and no downloaded subtitle has been verified yet.

**Current service:** Use **OpenSubtitles.com REST API v1** (`https://api.opensubtitles.com/api/v1`). **Do not implement legacy OpenSubtitles.org XML-RPC**, whose shutdown was announced in 2026. The **AI Transcribe/Translate** service is separate, potentially paid, and **not required** by this feature.

## Confirmed public API contract (as reviewed October 26, 2026)

| Flow | Endpoint | Required treatment |
| --- | --- | --- |
| Application registration | OpenSubtitles.com API Consumers | Register an authorized app; receive developer/application API key and review API consumer terms. |
| Search | `GET /subtitles` | `Api-Key` and non-empty `User-Agent` (`Mirquova vX.Y`); query parameters support `moviehash`, `query`, `languages`, `imdb_id`, and series/episode metadata. |
| Account login (optional) | `POST /login` | Returns user session bearer token and potentially alternate `base_url`; only offer when justified and secure; follow service docs. |
| Retrieve download link | `POST /download` | Use `file_id` from selected search result; authentication requirements depend on allowed mode; honor API key and valid user-token where required. |
| Fetch subtitle | **temporary URL returned by** `/download` | Download immediately over HTTPS, validate returned URL and size, cache subtitle file not the temporary URL. Temporary URLs have limited validity. |
| Language list | `GET /infos/languages` | Populate language picker from live provider capabilities; do not assume all languages/translations exist. |

Official documentation: https://ai.opensubtitles.com/api-docs and https://opensubtitles.stoplight.io/docs/opensubtitles-api and https://opensubtitles.tawk.help/article/getting-started .
Official 2026 tutorial (practical match strategies): https://blog.opensubtitles.com/opensubtitles/how-to-build-a-movie-subtitle-finder-cli-with-python-and-the-opensubtitles-api .
Legacy API shutdown notice: https://forum.opensubtitles.com/t/opensubtitles-org-api-final-shutdown-notice-for-non-vip-users/5045 .

## Secure integration approach

**Development / personal deployment:** Allow a user-provided permitted OpenSubtitles API key (BYOK) using OS secure storage, never logs or plaintext database. A personal app key should never be checked into source control, hard-coded into APK/EXE, or exposed in crash reports.

**Public application release:** Contact/review OpenSubtitles's API-consumer terms and subscription needs. An app developer may use a small authentication/proxy backend with quota enforcement so the developer API key isn't recoverable from distributed packages; this online helper is **optional only for online subtitle lookup**—Mirquova's local file transfer/casting/player remain local-first. If backend policies do not permit your planned use, use authorized per-user configuration or disable the feature gracefully. Do not use hidden scraping of the website or key rotation to circumvent limits.

**User accounts:** Don't collect passwords needlessly. If an account is genuinely required for a particular download allowance, handle login only through the official documented auth flow, encrypt tokens in secure storage, allow logout and revoke/erase local credentials. On TV, accept a user-controlled authorized pairing/access flow from a companion device; never claim that OpenSubtitles provides a device-code login without verification.

**Data sent online:** A lookup may disclose video filename, moviehash, selected language, IMDb/TMDb identifiers and request IP to OpenSubtitles. Present an explanation and offer an opt-out. Do not upload or proxy whole video files, never send filesystem paths or private file contents, and don't auto-query arbitrary personal filenames without consent.

## Exact search flow

1. Open a video from selected local or approved LAN share; parse known metadata (if available). Keep original path private.
2. When user selects **Find Online Subtitles**, default language from preferences; let user search different languages.
3. Prefer high-confidence `(imdb_id)` or `(moviehash + normalized title query)` where available. For episodes add show ID/season/episode, avoiding contradictory filters. Calculate OpenSubtitles moviehash efficiently on a file with random access; **do not confuse it with SHA-256**. With LAN stream, ask sender to provide a hash only with sender's permission. Some videos may not be hashable (remote stream not seekable, tiny file, permission limitations); fallback to cleaned title/year/episode.
4. Send `GET /subtitles` once with appropriate official parameters. Follow HTTPS redirects where valid, canonicalize case/query encoding. Never infer verified matches from filenames only.
5. Rank `moviehash_match == true` ahead of title-only candidates, then preferred language, matching season/episode and release/FPS, SDH/forced settings, trusted uploader metadata. Display search results with file language, result provenance and likely sync quality. Label 'possible match' rather than guaranteed.
6. On user selection, resolve candidate `file_id` from the API response. Request `POST /download` using the approved account/auth flow. Show download allowance errors without silent retry loops.
7. Fetch returned temporary HTTPS link promptly; **do not store/cache the expiring URL**. Validate redirect hosts against intended allowed destinations, max bytes, content type, decompression size and encoding. Save sanitized `.srt`/`.vtt`/`.ass` text in app-scoped cache with atomic write. Avoid path traversal from remote `file_name`.
8. Load the external track through active player adapter, immediately select it, preserve playback time, show a non-blocking confirmation. Expose subtitle offset/size/SDH controls.
9. Track local cache entry keyed by content identity, language, provider file ID and checksum. Offline replay should use downloaded file without a new call, subject to provider usage/retention conditions.
10. In Settings: language defaults, auto-search OFF by default, subtitles off/on, cache management, account/logout, 'OpenSubtitles' attribution and Open in browser option.

## Error and quota rules

| Condition | UI handling |
| --- | --- |
| No internet/host unreachable | 'Online subtitles unavailable; local subtitles still work.' |
| Missing or invalid API key | 'Configure OpenSubtitles access in Settings.' No repeated background calls. |
| Search has no match | Offer manual title/language search, open provider website, or local `.srt` picker. |
| Daily download quota reached | Show provider reset/allowance if supplied, otherwise general quota message; never create alternate accounts to bypass. |
| HTTP 401/403 | Show credentials/permissions error, offer reconnect; no destructive retries. |
| HTTP 429 | Honor `Retry-After` and documented rate-limit headers; capped exponential backoff; no parallel auto-download spam. |
| HTTP 5xx/timeouts | Cancel/retry with bounded attempts and jitter; resume video unaffected. |
| Download URL expired | Request a fresh URL via official endpoint only after user approval/allowance checks; do not replay expired URL. |
| Subtitle out of sync | Offer +/− timing and alternative release selection. |
| Unsafe or huge subtitle | Reject with clear reason; keep playing video. |

**Quotas and pricing change.** The OpenSubtitles help center mentions limited anonymous downloads and higher authenticated allowances, but plans, API subscription, eligibility and limits must be read from the live account/docs; do not promise unlimited/free downloads. Display allowance from actual API responses when present.

## Practical API example (illustrative: requires valid authorized API key)

```bash
curl --location --get 'https://api.opensubtitles.com/api/v1/subtitles' \
  -H 'Api-Key: YOUR_AUTHORIZED_API_KEY' \
  -H 'User-Agent: Mirquova v0.1' \
  -H 'Accept: application/json' \
  --data-urlencode 'query=sample movie' \
  --data-urlencode 'languages=en'
```

**This is not a live-tested query.** The user's app key and OpenSubtitles subscription/access rights are prerequisites for actual search and download validation.

## OpenSubtitles content and licensing

- Subtitle files are third-party content and can be copyright-protected; use only content users have rights to access and comply with provider licensing/redistribution rules.
- Avoid creating a shared subtitle mirror/repository. Save requested file to authorized user's device/cache, not to a public server.
- No scraping or unofficial download links; service integration remains optional and swappable. Preserve visible attribution as required by provider terms.
