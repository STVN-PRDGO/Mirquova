# App shell design decisions

Applied ui-ux-pro-max for native controls, responsive layout and accessibility. Two design-system searches returned website/marketing patterns rather than a verified native utility composition. Those patterns were not adopted or persisted. General skill guidance is the fallback; the verified Flutter stack search supports LayoutBuilder, semantics and screen-reader testing.

The approved UI is the dark navy Mirquova mockup in `design/MIRQUOVA_UI_UX_DESIGN_SPEC.md`. That spec replaces the earlier forest-green seed. Dark surfaces use `#080D18`, `#0E1728`, and `#142138`, with blue `#3478F6`, cyan `#22D3EE`, and violet `#8B5CF6`. Light mode keeps the same hues on pale surfaces. Roboto is the bundled sans; there are no remote font calls. Appearance stays session-only.

Desktop widths use a labeled sidebar: Home, Transfer, Cast, Media Player, Devices, Pair, and Settings. Phones use a bottom bar for Home, Transfer, Cast, Player, and Settings. Large text and short windows keep a drawer so labels remain reachable. Home is the landing page. Devices still runs real discovery. Pair and settings keep their existing behavior. Updates start from one Update button. Transfer sends only to a paired device after the receiver approves. Playback opens local files. The remote controls that local playback and does not address a TV. OpenSubtitles sends a request only after an in-memory API key and an explicit opt-in. Screen capture is not included, and starting a cast does not contact a device or pretend a session exists.

Primary controls are at least 48 logical pixels. Forms have labels and inline errors; scan status is a live region. Content scrolls within SafeArea. No custom animation is added. Widget checks cover portrait/landscape, 375/768/1440 widths, 2x text scale and reduced motion. Physical TalkBack and TV D-pad checks remain outstanding.

The navy redesign changes those compositions, so the checked-in local and macos-15 golden pixels are stale until they are regenerated on macOS. Do not refresh them from Windows.

Readable light/dark phone and desktop renders are in apps/mirquova_flutter/test/goldens. The tests load licensed SDK fonts rather than Ahem test placeholders. These are reference renders, not physical screenshots; The hosted macOS-15 CI renderer is the canonical CI profile for exact pixel comparisons (`MIRQUOVA_GOLDEN_PROFILE=macos-15`); the original developer-machine renders remain the default `local` profile. See `test/goldens/macos-15/README.md` for artifact provenance. CI runs those comparisons on macOS and the remaining layout/interaction tests on Windows and Linux. Only the four screenshot tests carry the `golden` tag; accessibility layout tests remain untagged. Cross-host raster differences require deliberate review, not a higher mismatch threshold. CI uploads failed comparisons for review.

Preview 03 uses native Material consent/name entry and a visible Hide now control. The visibility status announces updates, and name errors use plain language. Widget tests exercise consent, cancellation and background cleanup; the actual Windows runner checks the flow.

The 2026-10-30 pairing polish adds consistent icon-led section headers, quieter
form borders, full-width invitation actions, a separated scan/paste choice and a
visible fingerprint reminder. Errors use rounded containers, explicit error-text
contrast and live-region semantics. These styles are scoped to Pair; Nearby's
existing golden references were not regenerated. Nearby candidate copy now points
to invitation pairing while keeping discovery claims explicitly unverified.

Validation: Dart formatting and Flutter analysis passed; 138 non-golden tests
passed with the native Rust library, including four Pair layout checks at phone
and desktop widths with 2x text in light/dark themes. The ARM64 Android debug APK
built and was installed in the local Pixel 10a emulator for visual inspection.
Local screenshots are under `local-evidence/virtual-2026-10-30/` with the
`android-pair-polished` prefix. No dependencies or pairing protocol changed in
this UI pass; physical-device accessibility and camera checks remain pending.
