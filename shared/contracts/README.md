# Native discovery/presence ABI v2

The C signatures in mirquova_core.h are implemented by Rust and bound through dart:ffi. App state uses DiscoveryPort. ABI v1 is rejected; update the complete application bundle.

Scans remain explicit and bounded to six seconds, with at most 128 candidates and 16 private IPv4 addresses per record. The new presence-only DNS-SD service is _mirq-presence._tcp.local. with protocol=2, phase=presence and port=0. Port zero is a sentinel for no application transport endpoint. Other phases, versions or nonzero ports are rejected. The earlier _mirquova service is not silently accepted.

Make discoverable accepts 1-64 UTF-8 bytes of a user-chosen name. Controls, bidi overrides/isolates and blank names are rejected. A random per-process UUID forms the announcement instance/hostname, and does not authenticate identity. Presence lasts at most 120 seconds including startup. Status is hidden, starting, visible, stopping or error. Visible requires an actual daemon announcement event, not merely a queued registration.

mq_presence_start reads a caller-owned UTF-8 byte buffer with a supplied uint32 length; it returns 1 when a worker starts, 0 for rejection and -1 for an internal failure. It does not retain the buffer. mq_presence_stop requests cancellation. Both scan and presence work run off the Dart/UI thread. Sockets unregister and shut down on all managed exit paths, with bounded cleanup waits. Abrupt process termination cannot guarantee remote cache removal.

mq_discovery_snapshot returns owned NUL-terminated UTF-8 JSON. Free exactly once with mq_string_free. No callbacks cross native threads into Dart. The snapshot contains abi_version=2, status, peers, error and presence. Presence contains status, alias, remaining_seconds and error. Candidate fields remain id, name, addresses, port=0 and verified=false. The runtime suppresses its own announcement by full instance name. Other records remain untrusted, and last-scan candidates are not liveness proofs.

The Android multicast lock is shared by pending/active scan and visibility operations. Calls are serialized and demand is re-evaluated before acquire/release so one operation cannot release another operation's lock. Stop/dispose invalidates pending starts. App hidden/paused/detached stops both activities, and visibility never resumes automatically.

Manual IP/port entries are separate session-only candidates. They are not contacted, authenticated or used to bypass this presence-only contract. QR, IPv6, identity persistence, authenticated pairing, transfer and casting are not implemented. See docs/pairing-design-review.md for the proposed next stage.

## Later pairing implementation

The statement above records the original discovery/presence contract's scope. The subsequent authenticated pairing implementation has a separate versioned message contract in [pairing-protocol.md](pairing-protocol.md); it does not change the discovery ABI or authenticate discovery candidates.
