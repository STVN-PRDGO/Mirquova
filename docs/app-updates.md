# App updates

Settings > System updates has one Update button. Pressing it checks for a newer Mirquova release, downloads the compatible package, and opens that package for installation. Opening the app or Settings does not contact a release service. Cancelling an active check or download, backgrounding, or closing the app aborts it and discards late results.

The installed version and build number come from the native runner's generated build metadata or installed package information. If that metadata is unavailable or unsupported, checking is disabled and a retry is offered. No fallback version is invented.

## Release contract

The source is the repository's public latest stable release endpoint:

```text
https://api.github.com/repos/STVN-PRDGO/Mirquova/releases/latest
```

The request uses HTTPS, a Mirquova user agent, GitHub's JSON media type and API version `2026-03-10`. No account, access token, filenames, discovery candidates, or device identifier is supplied. GitHub receives the network connection information, including the public IP address. There are no periodic checks, saved opt-ins, or automatic retries.

The adapter follows the [GitHub latest release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release). A release must be published, have `draft: false` and `prerelease: false`, and use a stable numeric tag such as `v0.3.0` or `v0.3.0+3` (the `v` is optional). Numeric major/minor/patch components are compared first. An optional numeric build suffix is compared only when both installed and published builds are known and their version components match. Equal or older releases never offer an update. Prerelease tags are unsupported by this initial stable channel.

`html_url` must identify the same tag under `https://github.com/STVN-PRDGO/Mirquova/releases/tag/`. Other origins, repositories, routes, credentials, query strings and fragments are rejected. Native browser handlers independently enforce a canonical release URL. The adapter rejects redirects, bounds the response to 256 KiB and the whole check to 15 seconds, and displays at most 12,000 characters of release notes as plain text.

HTTP 404 means no public stable release is available to this unauthenticated check; it does not establish that the installed build is current. Rate limits, unavailable service, malformed metadata and connection failures have separate failure messages. The last-checked time records a successful response; errors never become an up-to-date result. Results and timestamps last only for the app session.

## Getting an update

Pressing Update is the opt-in. If the published release is newer and has one compatible package with a published SHA-256 digest, the app downloads it and opens it without another button. Settings shows the version, a progress line, and expandable release notes. No GitHub page or browser is opened. Android still shows the system install confirmation. Desktop archives open in the system archive handler; Mirquova does not replace its own files.

The adapter reads GitHub release asset `name`, `state`, `size`, `digest` and `browser_download_url` fields. See [GitHub's release asset contract](https://docs.github.com/en/rest/releases/assets). Assets must be uploaded, 1 byte–1 GiB, have a lowercase `sha256:` digest and a canonical URL bound to the same repository, tag and filename. Missing/ambiguous compatible assets produce an unavailable message instead of a browser fallback.

| Platform | Exact compatible asset | Final installation |
| --- | --- | --- |
| Windows x64 | `Mirquova-preview-windows-x64.zip` | System archive handler; close Mirquova and replace the complete portable app folder |
| macOS ARM64 | `Mirquova-preview-macos-arm64.zip` | System archive handler; close Mirquova and replace the app bundle; Gatekeeper/notarization rules still apply |
| Android ARM64 | `Mirquova-preview-android-arm64-debug.apk` | System APK installer after explicit user approval |
| Linux x64 / ARM64 | `Mirquova-preview-linux-x64.tar.gz` / `Mirquova-preview-linux-arm64.tar.gz` | System archive handler; replace the complete bundle; publishers must package these assets explicitly |
| iOS / other architectures | None in this preview | Use the installation provider; no unsupported IPA installation is offered |

Downloads accept at most three HTTPS redirects, only on `github.com`, `release-assets.githubusercontent.com` and `objects.githubusercontent.com`, with no credentials, fragments or alternate ports. Signed storage query strings are allowed but never logged. A 15-minute total deadline, 15-second connection deadline and 30-second body inactivity deadline bound the download. Both declared and actual sizes are checked; truncated, oversized, corrupt and cancelled files are discarded. Backgrounding cancels an active download and prevents late completion from becoming ready. Completed files remain in the system-managed cache so an installer can read them after the app closes. Cache eviction requires downloading again.

SHA-256 is supplied by Dart's maintained `crypto` package. It detects corruption relative to release metadata; it is not independent publisher authentication or a replacement for platform signing. Before opening, the file is checked again. Native handlers independently restrict handoff to expected package names in the app's update staging directory; they never execute shell command strings or open arbitrary paths. Desktop archives are opened, not silently applied. Android also checks the package ID, signing certificates and increasing version code, grants read access only through a restricted FileProvider, and uses the system's installation permission/confirmation screens. If installation permission is missing, grant it in Settings and press **Update** again. A verified package already on disk is opened without downloading it again. The `REQUEST_INSTALL_PACKAGES` permission is specific to this sideloaded preview; any future store distribution needs a separate policy/distribution review.

Publish compatible packages to the stable release with GitHub-generated digests. Android updates must retain the same application identity and signing key with an increasing package version code; independently generated debug keys will not update one another. A Windows/macOS/Linux package must contain the whole application bundle and its Rust library, Flutter runtime, data and notices. Existing previews and fixtures are not signed production releases. Production signing, automatic desktop replacement, rollback and physical installation QA remain open.

## Verification

### Local update review — 2026-10-30

The five focused offline suites (`app_updates`, `github_updates`,
`package_updates`, `settings_updates`, and `native_app_platform`) passed all 68
tests. They cover version comparison, no automatic requests, consent,
cancellation/late results, bounded downloads, redirect restrictions, digest and
size mismatches, tampering before handoff, errors/retry, and UI layouts. Flutter
analysis passed.

The new `integration_test/native_update_package_test.dart` passed on the local
Pixel 10a ARM64 emulator (Android API 37, app target API 36). It read installed
metadata and the actual native cache directory, then confirmed native rejection
of an invalid APK, an unexpected filename, a noncanonical path and a missing
file. Probe files were isolated and removed. No installer was launched, and no
live GitHub metadata or packages were fetched. This complements the earlier
native consent-cancellation smoke; it does not prove successful installation.

The review found two release-pipeline gaps that prevent treating Android updates
as verified end to end:

- `.github/workflows/release.yml` builds the Android asset with `--debug` but
  does not provision a stable signing key. A freshly generated runner debug key
  need not match an installed local or previous-run APK; the native updater
  correctly rejects a signature mismatch. A consistent signing identity must be
  supplied and retained across published builds.
- The workflow validates the release tag's syntax but does not check it against
  `pubspec.yaml` or override the packaged version/build. For example, a `v0.4.0`
  tag could advertise an update while packaging the current `0.3.0+3` app. An
  installed Android build with version code 3 rejects another code-3 APK. Release
  metadata must match package metadata, and Android version codes must increase.

These are source-review findings, not observations about any particular
published asset. Live release availability/digests, newer same-key installation,
unknown-source permission approval, and desktop archive handoff remain untested
in this review. The local UI and pairing edits are uncommitted and are not
themselves a published update. Production signing, automatic desktop replacement
and rollback remain outstanding.

### One authorized live check — 2026-10-30

After explicit user opt-in, exactly one GET to the configured latest-release
endpoint returned HTTP 200, using the app's user agent, media type and API-version
header. No redirect was followed and no asset was downloaded. GitHub confirmed
API version `2026-03-10` in its response headers.

The response identified [Mirquova Preview v0.3.4](https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.4),
published `2026-10-27T17:45:09Z`, with `draft: false` and `prerelease: false`.
The app's actual `GitHubUpdateSource.parseRelease` accepted the saved response in
a local Flutter test; `AppVersion` correctly identified it as newer than the
emulator's installed `0.3.0+3`. Compatible, unambiguous asset metadata with
published SHA-256 digests was accepted for Android ARM64, macOS ARM64, Windows
x64 and Linux x64.

The Android asset was listed as 79,811,644 bytes with digest
`9f22e5bb4ff0e9187146046a7830020bc48f3ea933d196894fed932327a0bfab`.
This verifies release discovery and metadata selection against the live service;
it does not verify package bytes, internal version code, signer compatibility or
installation. The release-pipeline risks above remain unresolved. The response
and headers are saved under ignored `local-evidence/update-check-2026-10-30/`.

Automated checks use offline metadata fixtures and fake transports; they never call the live release API or open a browser. The Windows native integration test reads installed metadata, opens Settings, cancels the consent prompt with zero release requests, and verifies native rejection of invalid release URLs. Those checks do not establish live release availability, successful package installation, Android device behavior or TV support.

Local verification on 2026-10-27:

| Check | Result |
| --- | --- |
| Rust formatting and clippy with warnings denied | Passed |
| Rust workspace tests with locked dependencies | 23 passed; 2 explicit network tests left ignored |
| Flutter/Dart formatting and full Flutter analysis | Passed |
| Flutter tests, including the compiled Rust bridge | 75 passed |
| Windows x64 release build | Passed |
| Windows native update integration test and debug runner build | 1 passed; real installed version `0.2.0+2` rendered |
| Android ARM64 native library and debug APK build | Passed; no physical Android device run |
| Android APK contents, debug signature and 16 KiB native-page ZIP alignment | Passed |

The Windows view was visually inspected from `local-evidence/windows-updates.png`. Widget tests additionally cover both themes, portrait/landscape and 375/768/1440 widths with 2x text and reduced motion. There were no dependency changes; lockfiles and notices remain unchanged.

For this restricted host, analyzer state was directed to ignored `.toolchains/appdata-local` and `.toolchains/appdata-roaming` using process-only `LOCALAPPDATA`/`APPDATA` values. Flutter checks used `--suppress-analytics --no-version-check --no-pub`. The first Windows build hit MSBuild file-tracker access denial in the sandbox; the approved retry and native integration test passed outside it. No global environment or execution policy was changed.

## Direct-download verification — 2026-10-27

- Flutter analysis and formatting passed; the complete offline Flutter suite, including the compiled Rust bridge, passed 96 tests.
- Download fixtures cover expected bytes/digest, truncation, overflow, HTTP failure, unsafe redirects, cancellation, late results, timeouts, duplicate starts, tampering before opening, and invalid/ambiguous asset metadata. Widget tests cover download consent/cancellation, explicit local package opening, no browser handoff, and responsive large-text layouts.
- Android ARM64 debug APK build passed, compiling the FileProvider and installer handoff. No physical installation or permission flow was exercised.
- macOS Swift syntax parsing passed. Full macOS build is unavailable because only Xcode Command Line Tools are installed. Windows/Linux native builds were not run on this host.
- Rust formatting, Clippy and tests passed (23 passed; 2 opt-in network tests ignored).
- Added `crypto 3.0.7` and its `typed_data 1.4.0` dependency, retained lockfiles, and regenerated notices. Original notices were preserved.
- No live release API call, release-package download, browser launch, package opening or installation was performed by verification. Offline fixtures are not proof of published-package availability or successful installation.

The older table above records the original browser-handoff implementation, not the new downloader's native installation coverage.
