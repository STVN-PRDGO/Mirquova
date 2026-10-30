# Pairing persistence review

Reviewed and checked locally on 2026-10-30 (Asia/Manila).

The implementation already contains discovery, invitation pairing, OS-backed
identity/trust storage and consented update checks. The next roadmap work remains
pairing validation and hardening. Physical two-device discovery and
Windows-to-Android pairing acceptance remain outstanding; authenticated data
sessions and file transfers are not implemented.

## Findings and changes

- A pending trusted-peer save blocked persistence for a later pairing. If the
  second pairing completed before the first write finished, its terminal snapshot
  stopped polling without queuing its peer. Each successfully started pairing now
  has separate save state; the trust repository continues to serialize writes.
- A previous save could overwrite the current session's saved fingerprint or
  failure state. Save completions now update controller state only for the session
  that produced them. An approved earlier pairing still finishes its queued write.
- Synchronous validation errors from the trust repository escaped the existing
  future error handler and left the saving flag set. The save now runs inside an
  async try/catch/finally so it exposes a retryable failure and clears that flag.

Regression tests cover a second completed pairing during a delayed successful or
failed first save, persistence of the appropriate peers, duplicate-save prevention,
and synchronous rejection of an invalid peer. These are controller fixtures, not
authenticated peers or device acceptance evidence. An existing formatting issue
in the pairing page was also corrected without changing its behavior.

## Local verification

Toolchains: Flutter 3.47.8, Dart 3.13.7, Rust/Cargo 1.99.1.

| Check | Result |
| --- | --- |
| Cargo format | Passed |
| Cargo Clippy, workspace/all targets, warnings denied, locked | Passed |
| Cargo workspace tests, locked | 43 passed; 9 opt-in tests ignored |
| Rust debug native library | Built on this macOS host |
| Flutter dependencies | Restored with `pub get --enforce-lockfile`; lockfiles unchanged |
| Dart format, app lib/test | Passed after correcting existing pairing-page formatting |
| Flutter analyze, no pub resolution | Passed |
| Flutter functional suite with compiled macOS Rust library | 134 passed; four golden comparisons excluded |

No dependencies were changed. Golden images were not regenerated. No native app
runner build, OS secure-storage runtime test, private-interface network test,
physical-device test or live app-update/subtitle API check was performed in this
review. The Flutter suite includes native FFI checks but does not establish a
native application build or TV support.

Subsequent user-requested [local virtual testing](virtual-testing-2026-10-30.md)
passed the Android emulator native identity/trust/Pair route smoke and normal APK
launch. Mac private-interface TLS scenarios failed; see that record for the
skipped automatic probe, isolated failure and unresolved limitations.

Continue with the existing native pairing smoke checks and physical
host/join/reject/restart/revoke acceptance from pairing-design-review.md before
enabling authenticated data sessions. Keep later transfer, casting and TV
milestones visibly unavailable until their implementation and exit evidence exist.
