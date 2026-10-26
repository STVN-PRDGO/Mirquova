# App updates

Settings > System updates provides a manual check for a newer Mirquova app version. Opening the app or Settings does not contact a release service. Each check asks permission before requesting public release information from GitHub. Cancelling the prompt makes no request; cancelling an active check, backgrounding, or closing the app aborts it and discards late results.

The installed version and build number come from the Windows runner's generated Flutter build metadata or Android's installed package information. If that metadata is unavailable or unsupported, checking is disabled and a retry is offered. No fallback version is invented.

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

For a newer release, Settings shows **New release available**, the published version, expandable release notes and **Open release page**. That explicit action opens the validated GitHub page through the operating system's browser handler. If no browser can open it, the page address remains selectable for manual use. The app does not download, execute or silently replace packages. Release metadata alone does not establish that a compatible package is attached; users check the release page for a package for their device.

Publish a compatible package and installation instructions with a release before marking it as the repository's latest stable release. A Windows update must contain the entire application bundle, including its Rust core, Flutter engine, runtime files and data; replacing an individual executable or DLL is insufficient. Close Mirquova before replacing the folder. Android updates must use the same application identity and signing key with an increasing package version code. ABI-specific version-code schemes require release planning; a plain version tag avoids treating ABI code offsets as build revisions.

Existing preview ZIPs, debug APKs, local packaging checksum manifests and test fixtures are not published or signed production releases. This feature does not finish the roadmap's Distribution milestone. Release signing, installers, artifact verification, rollback and physical installation QA remain open. No custom cryptography or package-install permissions are added.

## Verification

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
