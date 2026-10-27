# App shell design decisions

Applied ui-ux-pro-max for native controls, responsive layout and accessibility. Two design-system searches returned website/marketing patterns rather than a verified native utility composition. Those patterns were not adopted or persisted. General skill guidance is the fallback; the verified Flutter stack search supports LayoutBuilder, semantics and screen-reader testing.

The supplied forest-green direction uses a Material 3 seeded ColorScheme; dark mode supplies charcoal surfaces. Gold is reserved for a later meaningful status. Use Flutter platform typography and Material icons, with no remote font calls. Light/dark/system appearance is session-only in this increment.

Use a labeled rail on large desktops, compact rail on tablets, and a drawer on phones, short windows or large text. Seven destinations do not fit a phone bottom bar. Nearby is the active feature page; future features use explanatory text rather than fake actions.

Primary controls are at least 48 logical pixels. Forms have labels and inline errors; scan status is a live region. Content scrolls within SafeArea. No custom animation is added. Widget checks cover portrait/landscape, 375/768/1440 widths, 2x text scale and reduced motion. Physical TalkBack and TV D-pad checks remain outstanding.

Readable light/dark phone and desktop renders are in apps/mirquova_flutter/test/goldens. The tests load licensed SDK fonts rather than Ahem test placeholders. These are reference renders, not physical screenshots; The hosted macOS-15 CI renderer is the canonical CI profile for exact pixel comparisons (`MIRQUOVA_GOLDEN_PROFILE=macos-15`); the original developer-machine renders remain the default `local` profile. See `test/goldens/macos-15/README.md` for artifact provenance. CI runs those comparisons on macOS and the remaining layout/interaction tests on Windows and Linux. Only the four screenshot tests carry the `golden` tag; accessibility layout tests remain untagged. Cross-host raster differences require deliberate review, not a higher mismatch threshold. CI uploads failed comparisons for review.

Preview 03 uses native Material consent/name entry and a visible Hide now control. The visibility status announces updates, and name errors use plain language. Widget tests exercise consent, cancellation and background cleanup; the actual Windows runner checks the flow.
