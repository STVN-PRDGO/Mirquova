# Authenticated pairing messages v1

This contract describes the application messages carried by the Rust pairing transport. It is separate from the invitation JSON v2 contract and the native FFI ABI. The invitation schema and message protocol are versioned independently.

## Transport and framing

- Both connections use TLS 1.3 only. The bootstrap connection authenticates the host against the CA certificate supplied in the invitation, after the joiner has confirmed its SHA-256 fingerprint. The bootstrap connection has no client certificate.
- After the host accepts the one-use invitation secret and the joiner's public CA certificate, the peers open a second TLS 1.3 connection. The host requests a client certificate and trusts only the CA submitted for this pending invitation. The joiner authenticates the host using the invitation CA pin.
- Each application message is UTF-8 JSON preceded by an unsigned 32-bit big-endian byte length. The frame length must be 1 through 2048 bytes. Unknown JSON fields are rejected.
- The host's expiry and attempt counters are authoritative. An invitation can enroll at most one joiner.

## Bootstrap connection

The joiner sends this exact field set inside the pinned bootstrap TLS connection:

```json
{
  "protocol_version": 1,
  "role": "joiner",
  "secret": "<64 lowercase hexadecimal characters>",
  "identity_ca_certificate_der_hex": "<lowercase hexadecimal DER>"
}
```

The host accepts only protocol version `1` and role `joiner`. It validates the secret, the CA certificate and the server-owned invitation state before responding. A wrong version or role consumes a bounded failed attempt and does not consume a valid invitation secret.

The host responds with `protocol_version: 1`, `role: "host"`, `status: "continue"`, and its `peer_alias`. Invalid or consumed invitations may receive `status: "rejected"` and a null `peer_alias`.

## Mutual-authentication connection

After the bootstrap response, the joiner authenticates the host's server certificate and presents a client certificate issued by its own CA. It sends:

```json
{
  "protocol_version": 1,
  "role": "joiner",
  "alias": "Joining device"
}
```

The host validates the TLS client chain against only the candidate CA, then validates protocol version, role and alias before showing the explicit approval prompt. The host responds with protocol version `1`, role `host`, and status `accepted` or `rejected`. An accepted response contains the host `peer_alias`; a rejected response contains null. The joiner enrolls the host CA only after a valid accepted response.

Both peers reject an unsupported protocol version or an unexpected role. Version `1` is exact-version selection; it does not negotiate optional capabilities. Any future incompatible message changes require a new protocol version and corresponding interoperability tests.

## Security boundary

Pairing stores public CA pins and user-visible aliases in OS-backed secure storage; private identity keys remain in OS-backed storage. Pairing does not authorize file, screen-capture or media access. Revocation removes the locally stored pin. No transfer or casting session is established by this protocol.

Same-host transport tests exercise approval, rejection, wrong-secret handling, incompatible-version/role rejection, competing joiners and restart/replay rejection. They are not a substitute for Windows-to-Android physical-device acceptance. See the [pairing design review](../../docs/pairing-design-review.md) and [platform build record](../../docs/platform-builds.md) for current validation evidence and gaps.
