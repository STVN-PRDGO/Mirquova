//! Bounded parsing for a proposed pairing invitation, without trust or transport.
use crate::discovery::is_lan_address;
use serde::{
    Deserialize, Deserializer,
    de::{MapAccess, Visitor, value::MapAccessDeserializer},
};
use std::{
    fmt,
    marker::PhantomData,
    net::{Ipv4Addr, SocketAddrV4},
    time::{Duration, Instant},
};

pub const MAX_INVITATION_BYTES: usize = 1024;
pub const MAX_INVITATION_TTL: Duration = Duration::from_secs(120);

/// Errors contain categories only; untrusted invitation contents are never retained.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InvitationError {
    TooLarge,
    MalformedJson,
    UnsupportedVersion,
    UnsupportedPurpose,
    InvalidEndpoint,
    InvalidCertificatePin,
    InvalidSecret,
    InvalidTtl,
}

// Deliberately no Debug, Display, Serialize, Clone or public byte accessor.
// This is opaque input storage, not a secret generator or a zeroizing container.
struct InvitationSecret {
    _bytes: [u8; 32],
}

/// Syntax-checked, untrusted bootstrap input. Parsing never authenticates a peer.
pub struct PairingInvitation {
    endpoint: SocketAddrV4,
    certificate_sha256: [u8; 32],
    _secret: InvitationSecret,
    accepted_at: Instant,
    validity: Duration,
}

impl fmt::Debug for PairingInvitation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("PairingInvitation { redacted }")
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct WireInvitation {
    version: u32,
    purpose: String,
    endpoint: JsonObject<WireEndpoint>,
    certificate_sha256: String,
    secret: String,
    ttl_seconds: u64,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct WireEndpoint {
    ipv4: String,
    port: u16,
}

// Derived struct deserializers also accept positional sequences. Require JSON
// maps first, then let derive enforce required, duplicate and unknown fields.
struct JsonObject<T>(T);
impl<'de, T: Deserialize<'de>> Deserialize<'de> for JsonObject<T> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct ObjectVisitor<T>(PhantomData<T>);
        impl<'de, T: Deserialize<'de>> Visitor<'de> for ObjectVisitor<T> {
            type Value = JsonObject<T>;
            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("a JSON object")
            }
            fn visit_map<A: MapAccess<'de>>(self, map: A) -> Result<Self::Value, A::Error> {
                T::deserialize(MapAccessDeserializer::new(map)).map(JsonObject)
            }
        }
        deserializer.deserialize_map(ObjectVisitor(PhantomData))
    }
}

impl PairingInvitation {
    /// Accepts a complete JSON object of at most 1024 bytes, including whitespace.
    /// The remote TTL is only a local input-lifetime bound, not authenticated expiry.
    pub fn parse(input: &[u8]) -> Result<Self, InvitationError> {
        if input.len() > MAX_INVITATION_BYTES {
            return Err(InvitationError::TooLarge);
        }
        let JsonObject(wire): JsonObject<WireInvitation> =
            serde_json::from_slice(input).map_err(|_| InvitationError::MalformedJson)?;
        if wire.version != 1 {
            return Err(InvitationError::UnsupportedVersion);
        }
        if wire.purpose != "pairing" {
            return Err(InvitationError::UnsupportedPurpose);
        }
        let endpoint = wire.endpoint.0;
        let ip: Ipv4Addr = endpoint
            .ipv4
            .parse()
            .map_err(|_| InvitationError::InvalidEndpoint)?;
        if !is_lan_address(ip) || endpoint.port == 0 {
            return Err(InvitationError::InvalidEndpoint);
        }
        let certificate_sha256 = decode_nonzero_hex(&wire.certificate_sha256)
            .ok_or(InvitationError::InvalidCertificatePin)?;
        let secret = decode_nonzero_hex(&wire.secret).ok_or(InvitationError::InvalidSecret)?;
        let validity = Duration::from_secs(wire.ttl_seconds);
        if validity.is_zero() || validity > MAX_INVITATION_TTL {
            return Err(InvitationError::InvalidTtl);
        }
        Ok(Self {
            endpoint: SocketAddrV4::new(ip, endpoint.port),
            certificate_sha256,
            _secret: InvitationSecret { _bytes: secret },
            accepted_at: Instant::now(),
            validity,
        })
    }

    /// Untrusted destination data; this accessor does not initiate a connection.
    pub fn endpoint(&self) -> SocketAddrV4 {
        self.endpoint
    }

    /// Supplied pin bytes; no certificate or possession proof has been verified.
    pub fn certificate_sha256(&self) -> &[u8; 32] {
        &self.certificate_sha256
    }

    pub fn remaining_validity(&self) -> Duration {
        self.remaining_validity_at(Instant::now())
    }

    pub fn is_expired(&self) -> bool {
        self.remaining_validity().is_zero()
    }

    fn remaining_validity_at(&self, now: Instant) -> Duration {
        self.validity
            .saturating_sub(now.saturating_duration_since(self.accepted_at))
    }
}

// Hex decoding is format validation, not a cryptographic primitive. Nonzero does
// not establish randomness, entropy, certificate validity or secret ownership.
fn decode_nonzero_hex(value: &str) -> Option<[u8; 32]> {
    if value.len() != 64 {
        return None;
    }
    fn digit(byte: u8) -> Option<u8> {
        match byte {
            b'0'..=b'9' => Some(byte - b'0'),
            b'a'..=b'f' => Some(byte - b'a' + 10),
            _ => None,
        }
    }
    let mut decoded = [0; 32];
    for (index, pair) in value.as_bytes().as_chunks::<2>().0.iter().enumerate() {
        decoded[index] = (digit(pair[0])? << 4) | digit(pair[1])?;
    }
    decoded.iter().any(|byte| *byte != 0).then_some(decoded)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Value, json};

    fn fixture() -> Value {
        json!({
            "version": 1,
            "purpose": "pairing",
            "endpoint": { "ipv4": "192.168.1.8", "port": 45833 },
            "certificate_sha256": "1a".repeat(32),
            "secret": "b2".repeat(32),
            "ttl_seconds": 120,
        })
    }

    fn parse_value(value: &Value) -> Result<PairingInvitation, InvitationError> {
        PairingInvitation::parse(&serde_json::to_vec(value).unwrap())
    }

    #[test]
    fn accepts_bounded_private_endpoint_and_decodes_pin_without_trust() {
        let invitation = parse_value(&fixture()).unwrap();
        assert_eq!(invitation.endpoint(), "192.168.1.8:45833".parse().unwrap());
        assert_eq!(invitation.certificate_sha256(), &[0x1a; 32]);
        assert!(invitation.remaining_validity() <= MAX_INVITATION_TTL);
        assert!(!invitation.is_expired());
        for address in ["10.0.0.2", "172.16.0.2", "172.31.255.254"] {
            let mut value = fixture();
            value["endpoint"]["ipv4"] = json!(address);
            assert!(parse_value(&value).is_ok());
        }
    }

    #[test]
    fn rejects_oversized_input_before_parsing_and_accepts_exact_byte_limit() {
        let mut encoded = serde_json::to_vec(&fixture()).unwrap();
        encoded.resize(MAX_INVITATION_BYTES, b' ');
        assert!(PairingInvitation::parse(&encoded).is_ok());
        encoded.push(b' ');
        assert_eq!(
            PairingInvitation::parse(&encoded).unwrap_err(),
            InvitationError::TooLarge
        );
    }

    #[test]
    fn rejects_malformed_json_utf8_trailing_values_and_missing_fields() {
        for input in [
            b"".as_slice(),
            b"{",
            b"null",
            b"[]",
            b"\xff",
            b"{\"version\":1}",
            b"{} {}",
        ] {
            assert_eq!(
                PairingInvitation::parse(input).unwrap_err(),
                InvitationError::MalformedJson
            );
        }
        let valid = fixture();
        let sequence = json!([
            valid["version"],
            valid["purpose"],
            valid["endpoint"],
            valid["certificate_sha256"],
            valid["secret"],
            valid["ttl_seconds"],
        ]);
        assert_eq!(
            parse_value(&sequence).unwrap_err(),
            InvitationError::MalformedJson
        );
        let mut encoded = serde_json::to_vec(&fixture()).unwrap();
        encoded.extend_from_slice(b" null");
        assert_eq!(
            PairingInvitation::parse(&encoded).unwrap_err(),
            InvitationError::MalformedJson
        );
        let mut encoded = serde_json::to_vec(&fixture()).unwrap();
        let offset = encoded
            .windows(b"pairing".len())
            .position(|part| part == b"pairing")
            .unwrap();
        encoded[offset] = 0xff;
        assert_eq!(
            PairingInvitation::parse(&encoded).unwrap_err(),
            InvitationError::MalformedJson
        );
    }

    #[test]
    fn rejects_duplicate_and_unknown_fields_at_both_object_levels() {
        let encoded = serde_json::to_string(&fixture()).unwrap();
        for input in [
            encoded.replacen('{', "{\"version\":1,", 1),
            encoded.replace(
                "\"secret\":",
                &format!("\"secret\":\"{}\",\"secret\":", "a".repeat(64)),
            ),
            encoded.replace("\"port\":45833", "\"port\":45833,\"port\":45833"),
            encoded.replacen('{', "{\"extra\":true,", 1),
            encoded.replace("\"port\":45833", "\"port\":45833,\"extra\":true"),
            encoded.replacen('{', "{\"vers\\u0069on\":1,", 1),
        ] {
            assert_eq!(
                PairingInvitation::parse(input.as_bytes()).unwrap_err(),
                InvitationError::MalformedJson
            );
        }
    }

    #[test]
    fn rejects_unsupported_version_and_purpose_without_case_folding() {
        for version in [0, 2, 65536] {
            let mut value = fixture();
            value["version"] = json!(version);
            assert_eq!(
                parse_value(&value).unwrap_err(),
                InvitationError::UnsupportedVersion
            );
        }
        for purpose in ["", "transfer", "Pairing", "pairing "] {
            let mut value = fixture();
            value["purpose"] = json!(purpose);
            assert_eq!(
                parse_value(&value).unwrap_err(),
                InvitationError::UnsupportedPurpose
            );
        }
    }

    #[test]
    fn rejects_public_loopback_multicast_unspecified_link_local_and_ipv6() {
        for address in [
            "8.8.8.8",
            "127.0.0.1",
            "224.0.0.251",
            "0.0.0.0",
            "169.254.1.2",
            "255.255.255.255",
            "172.32.0.1",
            "::1",
            "::ffff:192.168.1.8",
            "192.168.1.8.example.com",
            "192.168.1.8:45833",
        ] {
            let mut value = fixture();
            value["endpoint"]["ipv4"] = json!(address);
            assert_eq!(
                parse_value(&value).unwrap_err(),
                InvitationError::InvalidEndpoint
            );
        }
    }

    #[test]
    fn rejects_zero_and_out_of_range_ports_and_invalid_field_types() {
        let mut value = fixture();
        value["endpoint"]["port"] = json!(0);
        assert_eq!(
            parse_value(&value).unwrap_err(),
            InvitationError::InvalidEndpoint
        );
        for port in [json!(-1), json!(65536), json!("45833"), json!(null)] {
            let mut value = fixture();
            value["endpoint"]["port"] = port;
            assert_eq!(
                parse_value(&value).unwrap_err(),
                InvitationError::MalformedJson
            );
        }
        let mut value = fixture();
        value["endpoint"]["port"] = json!(65535);
        assert!(parse_value(&value).is_ok());
    }

    #[test]
    fn rejects_json_type_coercion_for_protocol_fields() {
        for (field, malformed) in [
            ("version", json!("1")),
            ("version", json!(1.0)),
            ("version", json!(-1)),
            ("version", json!(null)),
            ("purpose", json!(true)),
            ("endpoint", json!(["192.168.1.8", 45833])),
            ("certificate_sha256", json!(null)),
            ("secret", json!(vec![178; 32])),
            ("ttl_seconds", json!("120")),
            ("ttl_seconds", json!(-1)),
            ("ttl_seconds", json!(1.5)),
            ("ttl_seconds", json!(null)),
        ] {
            let mut value = fixture();
            value[field] = malformed;
            assert_eq!(
                parse_value(&value).expect_err(field),
                InvitationError::MalformedJson
            );
        }
    }

    #[test]
    fn rejects_malformed_uppercase_and_all_zero_pins_and_secrets() {
        for (field, error) in [
            ("certificate_sha256", InvitationError::InvalidCertificatePin),
            ("secret", InvitationError::InvalidSecret),
        ] {
            for text in [
                String::new(),
                "0".repeat(64),
                "a".repeat(63),
                "a".repeat(65),
                "A".repeat(64),
                "g".repeat(64),
                format!("{} ", "a".repeat(63)),
                "\u{00e9}".repeat(32),
            ] {
                let mut value = fixture();
                value[field] = json!(text);
                assert_eq!(parse_value(&value).unwrap_err(), error);
            }
        }
    }

    #[test]
    fn ttl_boundaries_expire_at_the_monotonic_acceptance_deadline() {
        for ttl in [0, 121, u64::MAX] {
            let mut value = fixture();
            value["ttl_seconds"] = json!(ttl);
            assert_eq!(
                parse_value(&value).unwrap_err(),
                InvitationError::InvalidTtl
            );
        }
        for ttl in [1, 120] {
            let mut value = fixture();
            value["ttl_seconds"] = json!(ttl);
            let invitation = parse_value(&value).unwrap();
            let duration = Duration::from_secs(ttl);
            assert_eq!(
                invitation.remaining_validity_at(invitation.accepted_at),
                duration
            );
            assert_eq!(
                invitation.remaining_validity_at(
                    invitation.accepted_at + duration - Duration::from_nanos(1)
                ),
                Duration::from_nanos(1)
            );
            assert_eq!(
                invitation.remaining_validity_at(invitation.accepted_at + duration),
                Duration::ZERO
            );
            assert_eq!(
                invitation.remaining_validity_at(invitation.accepted_at + duration + duration),
                Duration::ZERO
            );
        }
    }

    #[test]
    fn debug_output_redacts_bootstrap_data_and_error_categories_do_not_echo_input() {
        let value = fixture();
        let invitation = parse_value(&value).unwrap();
        let rendered = format!("{invitation:?}");
        assert_eq!(rendered, "PairingInvitation { redacted }");
        assert!(!rendered.contains(value["secret"].as_str().unwrap()));
        assert!(!rendered.contains(value["certificate_sha256"].as_str().unwrap()));
        let mut value = value;
        value["secret"] = json!("sensitive-invalid-value");
        let rendered = format!("{:?}", parse_value(&value).unwrap_err());
        assert_eq!(rendered, "InvalidSecret");
        assert!(!rendered.contains("sensitive"));
    }
}
