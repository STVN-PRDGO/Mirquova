# Pairing design review - proposed, not implemented

Reviewed 2026-10-27. This document records architecture research, not a completed or independently audited authentication protocol. No private key, pairing server, trust grant or file access is introduced by this iteration.

## Source findings

- LocalSend's public protocol documents multicast discovery, a certificate fingerprint and transfer request/approval stages. This supports keeping discovery, identity and per-action permission separate. It does not prove that a name or an advertised fingerprint is independently trustworthy. Source: https://github.com/localsend/protocol (v2.2 README reviewed).
- The RustCrypto spake2 0.4.0 documentation says its implementation has not received an independent third-party security/correctness audit. It also explains that PAKE must be bound to the protected channel. Therefore, a short numeric code plus this crate is not being presented as audited pairing. Source: https://docs.rs/spake2/0.4.0/spake2/ . The crate is not a dependency.
- UUID v4 provides a random process-local announcement identifier. Here it is only a discovery/privacy aid, never a public-key identity, authentication secret or trust pin. Source: https://docs.rs/uuid/1.29.0/uuid/ .
- RFC 2782 permits the 16-bit SRV port range including zero. Our dedicated prototype presence service explicitly uses zero and exposes no application endpoint. That is a local presence convention, not an interoperable transport standard. Source: https://www.rfc-editor.org/rfc/rfc2782.html .

No third-party source code, interface composition or branded asset was copied. REA is not needed to inspect these public specifications and was not installed or invoked.

## Threat model for the current presence feature

Assume another LAN participant can forge names, addresses, TXT metadata and service IDs; replay records; induce collisions; and flood announcements. A LAN is not an authentication boundary. Every candidate remains unverified. The native/Flutter contract rejects transport endpoints in this presence-only version and offers no connect/transfer action.

A user-approved announcement discloses the chosen name and interface addresses on multicast-capable local networks. It contains no account name, OS hostname, file list, key or token. The identifier is random for each app process and never persisted. Hiding cannot erase a name already observed by another device. Scan results are explicitly observations from the last scan, not proof a peer remains online.

Visibility is off by default, capped at 120 seconds including startup, and cancelled on hidden/paused/detached lifecycle events or disposal. Native cleanup unregisters and shuts down on normal exit, failure or unwind. An abrupt process/OS termination cannot guarantee delivery of multicast goodbye packets. Scan result refresh and authenticated liveness must remain separate concerns.

## Proposed authenticated pairing path

Evaluate an established TLS 1.3 implementation with OS-backed identity protection and a high-entropy, short-lived QR/bootstrap invitation. The receiver must verify an out-of-band certificate/public-key pin before sending an invitation secret. Never trust a pin learned only from mDNS, silently accept any certificate, or downgrade to cleartext when QUIC is blocked.

A bootstrap invitation would require at least 128 bits of library-generated entropy, explicit host approval, one use, short expiry, bounded attempts, strict message sizes and no URL/log leakage. Peer key enrollment must occur inside the authenticated channel and bind roles, protocol version, invitation and both peer identities. This remains a design candidate requiring a concrete implementation review; QR appearance alone is not authentication.

After enrollment, future sessions must prove possession of the pinned identity using the transport's standard handshake. Windows key material should be protected with an appropriate OS facility; Android should use Keystore-backed protection. SQLite would store trust records/public identity and revocation state, not unprotected private keys. Reinstall/key change/revocation require explicit user handling rather than transparent trust replacement.

A short numeric pairing mode remains deferred until a reviewed PAKE/channel-binding design and suitable implementation are chosen. No home-made key exchange, MAC, cipher, SAS derivation or custom certificate bypass is authorized by this document.

## Gates before a transfer endpoint

- Rejected/missing/wrong pin, invalid certificate and downgrade tests.
- Expired/replayed invitation, attempt limiting, role/version mismatch and duplicate enrollment tests.
- Identity storage, restart, key change, revoke and interrupted-enrollment recovery tests on Windows and Android.
- Explicit per-transfer and per-cast consent after pairing; pinned trust never grants filesystem access.
- Two-process and then two-physical-device tests; no live device support claims from fixtures.

The original protocol specification was not supplied. This is an independently derived proposal, not a recovered specification or a security clearance. Implement and review the smallest authenticated pairing slice before opening any file/capture/media service.

## Input-validation groundwork

The Rust core now includes a [bounded invitation parser](../shared/contracts/pairing-invitation.md) for an independently proposed bootstrap JSON format. Ten tests cover malformed/oversized input, duplicate and unknown fields, unsupported versions/purposes, endpoint restrictions, pin/secret encoding, local TTL boundaries, and diagnostic redaction. This does not add a pairing endpoint or trusted peer. Client-local lifetime cannot establish invitation age, server expiry, or replay protection.
