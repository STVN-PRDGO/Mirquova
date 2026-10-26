# Proposed pairing invitation JSON v1

This is a proposed bootstrap input format and a Rust parser groundwork slice. It is not a recovered protocol, an authenticated pairing implementation, or an extension to discovery ABI v2. No UI, FFI entry point, server, connection, key storage, trust enrollment or secret generation is introduced.

## Exact fields

A complete UTF-8 JSON object may contain at most 1024 bytes, including surrounding whitespace. All fields below are required. Unknown and duplicate fields are rejected in both objects. JSON must end after the object, apart from whitespace; type coercion is not supported.

| Field | JSON type | Accepted value |
| --- | --- | --- |
| `version` | integer | Exactly `1` |
| `purpose` | string | Exactly `pairing`, case sensitive |
| `endpoint` | object | Exactly the two fields below |
| `endpoint.ipv4` | string | A literal RFC1918 private IPv4 address; no hostname, IPv6, URL or appended port |
| `endpoint.port` | integer | `1` through `65535` |
| `certificate_sha256` | string | Exactly 64 lowercase hexadecimal characters, decoded to 32 bytes; all zero is rejected |
| `secret` | string | Exactly 64 lowercase hexadecimal characters, decoded to 32 opaque bytes; all zero is rejected |
| `ttl_seconds` | integer | `1` through `120` |

The following values are parser examples only. Repeated bytes are not suitable generated invitation material:

```json
{
  "version": 1,
  "purpose": "pairing",
  "endpoint": { "ipv4": "192.168.1.8", "port": 45833 },
  "certificate_sha256": "1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a",
  "secret": "b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2",
  "ttl_seconds": 120
}
```

## Parser behavior and boundaries

`PairingInvitation::parse(&[u8])` rejects oversize input before JSON parsing. It returns categorical errors without retaining input text. Malformed UTF-8/JSON, trailing values, missing fields, unknown/duplicate fields and wrong JSON types are rejected. Format validation does not establish entropy or prove that the certificate digest corresponds to any actual certificate.

The returned invitation stores an `Instant` at local acceptance and bounds its local remaining validity to the supplied TTL. `remaining_validity()` reaches zero at that monotonic deadline; `is_expired()` reports that condition. A remote TTL is untrusted. This parser cannot determine an invitation's age before receipt. Re-parsing the same bytes starts a new local lifetime, so the local deadline does not implement server expiry, single use, attempt limits or replay protection.

The endpoint and supplied certificate pin have read accessors, but remain untrusted data. The parser opens no socket and creates no trust record. It neither hashes a certificate nor verifies a TLS handshake. A future transport must validate the out-of-band pin before disclosing the secret, bind the intended roles and version, and enforce server-owned expiry and replay controls independently. A pin learned only from an untrusted discovery record cannot establish identity.

The opaque secret type has no public byte accessor, `Debug`, `Display`, `Serialize` or `Clone` implementation. The invitation's custom `Debug` output is entirely redacted, and the invitation has no serialization implementation. This limits accidental logging through these APIs; it does not guarantee memory erasure. The caller still owns the original input, JSON parsing creates temporary allocations, and storage is not a zeroizing container. Do not log input buffers or place secrets in URLs. No secret-consuming transport API is exposed at this stage.

This schema is independently proposed and may change before authenticated transport implementation. See [pairing design review](../../docs/pairing-design-review.md) for the outstanding implementation and device-validation gates.
