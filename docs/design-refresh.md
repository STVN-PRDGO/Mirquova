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
