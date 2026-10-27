# Design refresh — 2026-10-27

The Flutter preview now uses forest green, charcoal and restrained gold in light and dark themes, with consistent cards, controls and responsive navigation. Nearby shows discovery and session-address counts, a visibility countdown from the core snapshot, and feedback for saved or duplicate addresses. Network controls are disabled when the native core is unavailable. Planned pages explain the pairing dependency and provide a route back to Nearby. Page changes reset the scroll position.

## Local verification

- Rust formatting check, workspace Clippy with warnings denied, and locked workspace tests passed: 23 passed, 2 explicit network tests ignored.
- Locked Rust library build passed.
- Dart formatting check and Flutter analysis passed.
- Complete offline Flutter suite passed: 78 passed, 1 native bridge test skipped in that invocation.
- The skipped native bridge test was then run separately with the compiled `target/debug/libmirquova_core.dylib`: 1 passed. It checks ABI loading without starting discovery.
- Reviewed and updated all four SDK-font golden images: phone (375 × 812) and desktop (1440 × 900), light and dark. Custom navigation and app-bar typography explicitly uses Roboto so these renders use the loaded reference font.
- Interaction checks include scan/stop, consent/cancellation, background cleanup, address validation/removal/deduplication, missing-core controls, countdown rendering, theme switching, planned-page navigation, and offline update checks. Existing tests cover phone, landscape, tablet and desktop layouts with large text; reduced-motion rendering also passed.

No dependencies or lockfiles changed. This work did not run a native app build or physical-device tests, multicast network tests, live release requests, or browser launches. Golden/widget checks do not establish native installation or TV support. Pairing, file transfer, casting and playback remain unavailable as described in the implementation roadmap; discovery records and saved addresses remain unverified.

## CI reference-host correction

The first Windows CI run after the refresh passed 92 tests but failed the four image comparisons, with 0.86–2.26% pixel differences against these macOS-generated references. Those failures are recorded in [the Windows job](https://github.com/STVN-PRDGO/Mirquova/actions/runs/40470189185/job/122075182948). The references were generated on a different raster host from the old Windows reference workflow.

The four image comparisons now carry the registered `golden` tag. macOS is the canonical reference host and runs the complete suite, including strict image comparisons. Windows/Linux exclude only that tag; the large-text/reduced-motion layout test remains untagged. Unix CI and the macOS build script now discover the complete test suite instead of enumerating test files, so the package-updater tests are included too. CI uploads failed visual comparisons for inspection. No comparator tolerance or baseline pixels were changed for this correction.

Local verification: Flutter analysis passed, the complete suite with the compiled Rust bridge passed 96 tests, the filtered functional suite passed 92 tests, workflow YAML parsed, and the macOS shell build script passed syntax validation. The updated GitHub Actions configuration has not been pushed or run remotely as part of this correction; Windows/Linux native reruns are not claimed.

## Hosted-render and case-sensitive font correction

[Run 40472537161](https://github.com/STVN-PRDGO/Mirquova/actions/runs/40472537161) exposed two independent remaining issues: Linux's case-sensitive filesystem rejected lowercase SDK font filenames, and the hosted macOS raster differed slightly at glyph/icon edges from the developer machine. Font paths now use the actual SDK filenames (`Roboto-Regular.ttf`, `Roboto-Bold.ttf`, `MaterialIcons-Regular.otf`). Font loading lives inside the screenshot-only group, so excluding `golden` also excludes its font setup while retaining the untagged accessibility test.

Four reviewed hosted renders were preserved as the explicit `macos-15` baseline profile, with their run/artifact provenance and SHA-256 checksums in `test/goldens/macos-15/README.md`. Existing local references and the exact comparator remain unchanged. CI and the packaging-script rerun select the same profile. This correction does not establish a fresh hosted CI pass until pushed and rerun.

The full local-profile suite passed 96 tests and the filtered suite passed 92 tests after this correction. Flutter analysis, formatting, workflow YAML checks and shell syntax checks passed. CI, release, and the manual macOS-preview workflow all explicitly select the hosted profile. All four imported hosted baselines were checked byte for byte against the downloaded artifact; a new hosted render was not run locally.
