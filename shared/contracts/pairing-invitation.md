# Pairing invitation JSON v2

This document preserves the original format proposal and parser constraints. The format is now used by an implemented TLS 1.3 mutual-authenticated pairing flow with UI, FFI, a one-use listener, OS-backed identity/trust storage, and explicit approval. It is not a recovered protocol. The implementation and its validation limits are recorded in the [pairing design review](../../docs/pairing-design-review.md) and [platform build record](../../docs/platform-builds.md). Physical-device and complete cross-platform validation are still outstanding.

## Fields and limits

A complete UTF-8 JSON object may contain at most 2048 bytes, including whitespace. All fields are required; unknown and duplicate fields are rejected at both object levels. Trailing non-whitespace data and type coercion are rejected.

| Field | Type | Rule |
|---|---|---|
| `version` | integer | Exactly `2` |
| `purpose` | string | Exactly `pairing` |
| `endpoint` | object | Exactly `ipv4` and `port` |
| `endpoint.ipv4` | string | Private LAN IPv4 only; no DNS names, IPv6, loopback, link-local, multicast, unspecified, or broadcast |
| `endpoint.port` | integer | 1 through 65535 |
| `identity_ca_certificate_der_hex` | string | Lowercase hex of 1 to 512 supplied bytes; syntactic bytes only, not validated X.509 |
| `secret` | string | Exactly 64 lowercase hex characters; decoded secret must not be all zero |
| `ttl_seconds` | integer | 1 through 120 |

Example shape (the `3000` value is deliberately only a parser fixture, not a valid certificate):

```json
{"version":2,"purpose":"pairing","endpoint":{"ipv4":"192.168.1.8","port":45833},"identity_ca_certificate_der_hex":"3000","secret":"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2","ttl_seconds":120}
```

The Rust generator accepts an endpoint, already-provisioned CA certificate bytes, and a whole-second validity duration. It creates a 256-bit secret with `getrandom` and returns the bounded JSON payload plus opaque local invitation state. It does not create a certificate or start a listener. Generated and parsed invitations redact `Debug`; callers must treat payload access as secret-bearing and must not log it. Secret storage is not zeroizing.

Parsing retains the supplied CA bytes and starts a local monotonic lifetime when parsing completes. Neither the parser nor generator validates DER, computes a fingerprint, authenticates a peer, verifies a TLS handshake, or creates a trust record. The Flutter adapter must hash the certificate bytes with the existing SHA-256 implementation, show the fingerprint for comparison, and configure a standard TLS root store only after the user confirms. The TLS layer must validate the server chain before disclosing the invitation secret. Server-owned expiry, attempt limits, and replay protection remain required.

The public CA bytes are supplied by the invitation and therefore are not independently trustworthy until their fingerprint is explicitly compared through the intended out-of-band UX. Never use an accept-any certificate verifier or trust a pin learned only from discovery. No private key belongs in this payload.

This contract does not establish a working pairing path. See the [pairing design review](../../docs/pairing-design-review.md) for transport, trust, storage, UI, and device-validation work still outstanding.
