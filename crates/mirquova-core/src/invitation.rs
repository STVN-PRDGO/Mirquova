//! Bounded invitation generation and parsing, without trust or transport.
use crate::discovery::is_lan_address;
use serde::{
    Deserialize, Deserializer,
    de::{MapAccess, Visitor, value::MapAccessDeserializer},
};
use std::{
    borrow::Cow,
    fmt,
    fmt::Write as _,
    marker::PhantomData,
    net::{Ipv4Addr, SocketAddrV4},
    time::{Duration, Instant},
};
use subtle::ConstantTimeEq;
use zeroize::Zeroizing;

pub const MAX_INVITATION_BYTES: usize = 2048;
pub const MAX_IDENTITY_CA_CERTIFICATE_BYTES: usize = 512;
pub const MAX_INVITATION_TTL: Duration = Duration::from_secs(120);

/// Errors contain categories only; untrusted invitation contents are never retained.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InvitationError {
    TooLarge,
    MalformedJson,
    UnsupportedVersion,
    UnsupportedPurpose,
    InvalidEndpoint,
    InvalidIdentityCertificate,
    InvalidSecret,
    InvalidTtl,
    EntropyUnavailable,
    Expired,
    Consumed,
    AttemptsExceeded,
}

// Deliberately no Debug, Display, Serialize, Clone or public byte accessor.
// This is opaque input storage, not a secret generator or a zeroizing container.
struct InvitationSecret {
    _bytes: Zeroizing<[u8; 32]>,
}

/// Syntax-checked, untrusted bootstrap input. Parsing never authenticates a peer.
pub struct PairingInvitation {
    endpoint: SocketAddrV4,
    identity_ca_certificate_der: Vec<u8>,
    _secret: InvitationSecret,
    accepted_at: Instant,
    validity: Duration,
    attempts_remaining: u8,
    consumed: bool,
}

/// A newly generated invitation payload. Its debug output never includes the
/// one-time bearer secret. The payload is intentionally accessible only for
/// rendering or transferring the invitation to the invited device.
pub struct GeneratedInvitation {
    invitation: PairingInvitation,
    payload: Zeroizing<String>,
}

impl fmt::Debug for GeneratedInvitation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("GeneratedInvitation { redacted }")
    }
}

impl GeneratedInvitation {
    /// Returns the JSON payload for a QR code or an explicit copy/paste flow.
    /// Callers must not log or persist it outside the invitation lifetime.
    pub fn payload(&self) -> &str {
        self.payload.as_str()
    }

    /// Returns the server-side invitation state. This does not open a socket.
    pub fn invitation(&self) -> &PairingInvitation {
        &self.invitation
    }

    /// Returns mutable server-side one-use state. Only retain this object in
    /// the listener process; parsing a remote payload does not create authority.
    pub fn invitation_mut(&mut self) -> &mut PairingInvitation {
        &mut self.invitation
    }

    pub(crate) fn into_parts(mut self) -> (Zeroizing<String>, PairingInvitation) {
        (std::mem::take(&mut self.payload), self.invitation)
    }
}

impl fmt::Debug for PairingInvitation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("PairingInvitation { redacted }")
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct WireInvitation<'a> {
    version: u32,
    #[serde(borrow)]
    purpose: Cow<'a, str>,
    #[serde(borrow)]
    endpoint: JsonObject<WireEndpoint<'a>>,
    #[serde(borrow)]
    identity_ca_certificate_der_hex: Cow<'a, str>,
    #[serde(borrow)]
    secret: Cow<'a, str>,
    ttl_seconds: u64,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct WireEndpoint<'a> {
    #[serde(borrow)]
    ipv4: Cow<'a, str>,
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
    /// Generates a bounded invitation with a fresh 256-bit OS-random secret.
    /// This creates no listener, trust record, or authenticated peer.
    pub fn generate(
        endpoint: SocketAddrV4,
        identity_ca_certificate_der: &[u8],
        validity: Duration,
    ) -> Result<GeneratedInvitation, InvitationError> {
        if !is_lan_address(*endpoint.ip()) || endpoint.port() == 0 {
            return Err(InvitationError::InvalidEndpoint);
        }
        if identity_ca_certificate_der.is_empty()
            || identity_ca_certificate_der.len() > MAX_IDENTITY_CA_CERTIFICATE_BYTES
        {
            return Err(InvitationError::InvalidIdentityCertificate);
        }
        if validity.is_zero() || validity.subsec_nanos() != 0 || validity > MAX_INVITATION_TTL {
            return Err(InvitationError::InvalidTtl);
        }

        let mut secret = Zeroizing::new([0; 32]);
        getrandom::fill(&mut secret[..]).map_err(|_| InvitationError::EntropyUnavailable)?;
        if secret.iter().all(|byte| *byte == 0) {
            return Err(InvitationError::EntropyUnavailable);
        }

        let accepted_at = Instant::now();
        let secret_hex = Zeroizing::new(encode_hex(&secret[..]));
        let payload = Zeroizing::new(format!(
            r#"{{"version":2,"purpose":"pairing","endpoint":{{"ipv4":"{}","port":{}}},"identity_ca_certificate_der_hex":"{}","secret":"{}","ttl_seconds":{}}}"#,
            endpoint.ip(),
            endpoint.port(),
            encode_hex(identity_ca_certificate_der),
            secret_hex.as_str(),
            validity.as_secs(),
        ));
        Ok(GeneratedInvitation {
            invitation: Self {
                endpoint,
                identity_ca_certificate_der: identity_ca_certificate_der.to_vec(),
                _secret: InvitationSecret { _bytes: secret },
                accepted_at,
                validity,
                attempts_remaining: 5,
                consumed: false,
            },
            payload,
        })
    }

    /// Accepts a complete JSON object of at most 2048 bytes, including whitespace.
    /// The remote TTL is only a local input-lifetime bound, not authenticated expiry.
    pub fn parse(input: &[u8]) -> Result<Self, InvitationError> {
        if input.len() > MAX_INVITATION_BYTES {
            return Err(InvitationError::TooLarge);
        }
        let JsonObject(wire): JsonObject<WireInvitation> =
            serde_json::from_slice(input).map_err(|_| InvitationError::MalformedJson)?;
        if wire.version != 2 {
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
        let identity_ca_certificate_der = decode_hex(
            &wire.identity_ca_certificate_der_hex,
            MAX_IDENTITY_CA_CERTIFICATE_BYTES,
        )
        .ok_or(InvitationError::InvalidIdentityCertificate)?;
        let secret = decode_nonzero_hex(&wire.secret).ok_or(InvitationError::InvalidSecret)?;
        let validity = Duration::from_secs(wire.ttl_seconds);
        if validity.is_zero() || validity > MAX_INVITATION_TTL {
            return Err(InvitationError::InvalidTtl);
        }
        Ok(Self {
            endpoint: SocketAddrV4::new(ip, endpoint.port),
            identity_ca_certificate_der,
            _secret: InvitationSecret { _bytes: secret },
            accepted_at: Instant::now(),
            validity,
            attempts_remaining: 5,
            consumed: false,
        })
    }

    /// Untrusted destination data; this accessor does not initiate a connection.
    pub fn endpoint(&self) -> SocketAddrV4 {
        self.endpoint
    }

    /// Supplied CA certificate bytes; DER validity and trust are not established.
    pub fn identity_ca_certificate_der(&self) -> &[u8] {
        &self.identity_ca_certificate_der
    }

    pub fn remaining_validity(&self) -> Duration {
        self.remaining_validity_at(Instant::now())
    }

    pub fn is_expired(&self) -> bool {
        self.remaining_validity().is_zero()
    }

    /// Compares a candidate bearer secret in constant time and consumes this
    /// server-owned invitation on success. Rejected attempts are bounded.
    pub fn consume_secret(&mut self, candidate: &[u8]) -> Result<(), InvitationError> {
        if self.consumed {
            return Err(InvitationError::Consumed);
        }
        if self.is_expired() {
            self.consumed = true;
            return Err(InvitationError::Expired);
        }
        if self.attempts_remaining == 0 {
            self.consumed = true;
            return Err(InvitationError::AttemptsExceeded);
        }
        let matches = candidate.len() == self._secret._bytes.len()
            && candidate.ct_eq(self._secret._bytes.as_ref()).unwrap_u8() == 1;
        if matches {
            self.consumed = true;
            return Ok(());
        }
        self.record_failed_attempt()
    }

    /// Charges a malformed/unauthenticated bootstrap connection against the
    /// same server-owned budget as an incorrect bearer secret.
    pub(crate) fn record_failed_attempt(&mut self) -> Result<(), InvitationError> {
        if self.consumed {
            return Err(InvitationError::Consumed);
        }
        if self.is_expired() {
            self.consumed = true;
            return Err(InvitationError::Expired);
        }
        if self.attempts_remaining == 0 {
            self.consumed = true;
            return Err(InvitationError::AttemptsExceeded);
        }
        self.attempts_remaining -= 1;
        if self.attempts_remaining == 0 {
            self.consumed = true;
            Err(InvitationError::AttemptsExceeded)
        } else {
            Err(InvitationError::InvalidSecret)
        }
    }

    pub(crate) fn consume_secret_hex(&mut self, candidate: &str) -> Result<(), InvitationError> {
        let decoded = Zeroizing::new(decode_hex(candidate, 32).unwrap_or_default());
        self.consume_secret(&decoded)
    }

    pub(crate) fn secret_hex(&self) -> String {
        encode_hex(self._secret._bytes.as_ref())
    }

    fn remaining_validity_at(&self, now: Instant) -> Duration {
        self.validity
            .saturating_sub(now.saturating_duration_since(self.accepted_at))
    }
}

// Hex decoding is format validation, not a cryptographic primitive. Nonzero does
// not establish randomness, entropy, certificate validity or secret ownership.
fn decode_nonzero_hex(value: &str) -> Option<Zeroizing<[u8; 32]>> {
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
    let mut decoded = Zeroizing::new([0; 32]);
    for (index, pair) in value.as_bytes().as_chunks::<2>().0.iter().enumerate() {
        decoded[index] = (digit(pair[0])? << 4) | digit(pair[1])?;
    }
    decoded.iter().any(|byte| *byte != 0).then_some(decoded)
}

fn decode_hex(value: &str, max_bytes: usize) -> Option<Vec<u8>> {
    if value.is_empty() || !value.len().is_multiple_of(2) || value.len() / 2 > max_bytes {
        return None;
    }
    fn digit(byte: u8) -> Option<u8> {
        match byte {
            b'0'..=b'9' => Some(byte - b'0'),
            b'a'..=b'f' => Some(byte - b'a' + 10),
            _ => None,
        }
    }
    value
        .as_bytes()
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| Some((digit(pair[0])? << 4) | digit(pair[1])?))
        .collect()
}

fn encode_hex(value: &[u8]) -> String {
    let mut encoded = String::with_capacity(value.len() * 2);
    for byte in value {
        write!(&mut encoded, "{byte:02x}").expect("writing into a String cannot fail");
    }
    encoded
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Value, json};

    fn fixture() -> Value {
        json!({
            "version": 2,
            "purpose": "pairing",
            "endpoint": { "ipv4": "192.168.1.8", "port": 45833 },
            "identity_ca_certificate_der_hex": "3000",
            "secret": "b2".repeat(32),
            "ttl_seconds": 120,
        })
    }

    fn parse_value(value: &Value) -> Result<PairingInvitation, InvitationError> {
        PairingInvitation::parse(&serde_json::to_vec(value).unwrap())
    }

    #[test]
    fn accepts_bounded_private_endpoint_and_certificate_bytes_without_trust() {
        let invitation = parse_value(&fixture()).unwrap();
        assert_eq!(invitation.endpoint(), "192.168.1.8:45833".parse().unwrap());
        assert_eq!(invitation.identity_ca_certificate_der(), &[0x30, 0]);
        assert!(invitation.remaining_validity() <= MAX_INVITATION_TTL);
        assert!(!invitation.is_expired());
        for address in ["10.0.0.2", "172.16.0.2", "172.31.255.254"] {
            let mut value = fixture();
            value["endpoint"]["ipv4"] = json!(address);
            assert!(parse_value(&value).is_ok());
        }
    }

    #[test]
    fn generated_invitation_round_trips_with_redacted_debug_and_fresh_secret() {
        let endpoint = "192.168.1.8:45833".parse().unwrap();
        let ca_der = [0x30, 0];
        let first =
            PairingInvitation::generate(endpoint, &ca_der, Duration::from_secs(90)).unwrap();
        let second =
            PairingInvitation::generate(endpoint, &ca_der, Duration::from_secs(90)).unwrap();
        let parsed = PairingInvitation::parse(first.payload().as_bytes()).unwrap();

        assert_eq!(parsed.endpoint(), endpoint);
        assert_eq!(parsed.identity_ca_certificate_der(), &ca_der);
        assert!(parsed.remaining_validity() <= Duration::from_secs(90));
        assert!(
            first.payload() != second.payload(),
            "secrets must be independently generated"
        );
        assert_eq!(
            first.payload().len(),
            second.payload().len(),
            "secret generation does not change the bounded wire size",
        );
        assert_eq!(format!("{first:?}"), "GeneratedInvitation { redacted }");
        assert!(!format!("{parsed:?}").contains(first.payload()));
    }

    #[test]
    fn generated_invitation_rejects_invalid_endpoint_certificate_and_ttl() {
        let valid_endpoint = "192.168.1.8:45833".parse().unwrap();
        assert_eq!(
            PairingInvitation::generate(
                "8.8.8.8:45833".parse().unwrap(),
                &[0x30, 0],
                Duration::from_secs(90),
            )
            .unwrap_err(),
            InvitationError::InvalidEndpoint,
        );
        assert_eq!(
            PairingInvitation::generate(valid_endpoint, &[], Duration::from_secs(90)).unwrap_err(),
            InvitationError::InvalidIdentityCertificate,
        );
        for ttl in [
            Duration::ZERO,
            Duration::from_millis(1_500),
            Duration::from_secs(121),
        ] {
            assert_eq!(
                PairingInvitation::generate(valid_endpoint, &[0x30, 0], ttl).unwrap_err(),
                InvitationError::InvalidTtl,
            );
        }
    }

    #[test]
    fn certificate_byte_limit_is_inclusive_and_bounded_in_the_wire_payload() {
        let endpoint = "192.168.1.8:45833".parse().unwrap();
        let maximum_certificate = vec![0x30; MAX_IDENTITY_CA_CERTIFICATE_BYTES];
        let generated =
            PairingInvitation::generate(endpoint, &maximum_certificate, Duration::from_secs(120))
                .unwrap();
        assert!(generated.payload().len() <= MAX_INVITATION_BYTES);
        let parsed = PairingInvitation::parse(generated.payload().as_bytes()).unwrap();
        assert_eq!(
            parsed.identity_ca_certificate_der(),
            maximum_certificate.as_slice()
        );

        let too_large = vec![0x30; MAX_IDENTITY_CA_CERTIFICATE_BYTES + 1];
        assert_eq!(
            PairingInvitation::generate(endpoint, &too_large, Duration::from_secs(120))
                .unwrap_err(),
            InvitationError::InvalidIdentityCertificate
        );
    }

    #[test]
    fn generated_invitation_secret_is_single_use_and_attempt_limited() {
        let endpoint = "192.168.1.8:45833".parse().unwrap();
        let mut generated =
            PairingInvitation::generate(endpoint, &[0x30, 0], Duration::from_secs(90)).unwrap();
        let payload: Value = serde_json::from_str(generated.payload()).unwrap();
        let secret = decode_nonzero_hex(payload["secret"].as_str().unwrap()).unwrap();
        assert_eq!(
            generated.invitation_mut().consume_secret(&secret[..]),
            Ok(())
        );
        assert_eq!(
            generated.invitation_mut().consume_secret(&secret[..]),
            Err(InvitationError::Consumed)
        );

        let mut generated =
            PairingInvitation::generate(endpoint, &[0x30, 0], Duration::from_secs(90)).unwrap();
        for attempt in 0..4 {
            assert_eq!(
                generated.invitation_mut().consume_secret(&[0x22; 32]),
                Err(InvitationError::InvalidSecret),
                "attempt {attempt}"
            );
        }
        assert_eq!(
            generated.invitation_mut().consume_secret(&[0x22; 32]),
            Err(InvitationError::AttemptsExceeded)
        );
        assert_eq!(
            generated.invitation_mut().consume_secret(&[0x22; 32]),
            Err(InvitationError::Consumed)
        );
    }

    #[test]
    fn malformed_bootstrap_attempts_share_the_bounded_secret_budget() {
        let endpoint = "192.168.1.8:45833".parse().unwrap();
        let mut generated =
            PairingInvitation::generate(endpoint, &[0x30, 0], Duration::from_secs(90)).unwrap();
        for _ in 0..4 {
            assert_eq!(
                generated.invitation_mut().record_failed_attempt(),
                Err(InvitationError::InvalidSecret),
            );
        }
        assert_eq!(
            generated.invitation_mut().record_failed_attempt(),
            Err(InvitationError::AttemptsExceeded),
        );
        assert_eq!(
            generated.invitation_mut().record_failed_attempt(),
            Err(InvitationError::Consumed),
        );
    }

    #[test]
    fn server_owned_invitation_secret_expires_on_its_monotonic_deadline() {
        let endpoint = "192.168.1.8:45833".parse().unwrap();
        let mut generated =
            PairingInvitation::generate(endpoint, &[0x30, 0], Duration::from_secs(1)).unwrap();
        generated.invitation.accepted_at -= Duration::from_secs(1);
        assert_eq!(
            generated.invitation_mut().consume_secret(&[0x22; 32]),
            Err(InvitationError::Expired)
        );
        assert_eq!(
            generated.invitation_mut().consume_secret(&[0x22; 32]),
            Err(InvitationError::Consumed)
        );
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
            valid["identity_ca_certificate_der_hex"],
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
    fn escaped_json_string_values_remain_valid_after_borrowed_parsing() {
        let encoded = serde_json::to_string(&fixture()).unwrap();
        let escaped_purpose =
            encoded.replace("\"purpose\":\"pairing\"", "\"purpose\":\"pa\\u0069ring\"");
        assert!(PairingInvitation::parse(escaped_purpose.as_bytes()).is_ok());

        let secret = "b2".repeat(32);
        let marker = format!("\"secret\":\"{secret}\"");
        let escaped_secret = format!("\"secret\":\"\\u0062{}\"", &secret[1..]);
        let escaped_secret_json = encoded.replace(&marker, &escaped_secret);
        assert!(PairingInvitation::parse(escaped_secret_json.as_bytes()).is_ok());
    }

    #[test]
    fn unescaped_secret_and_certificate_borrow_from_the_input_buffer() {
        let encoded = serde_json::to_vec(&fixture()).unwrap();
        let JsonObject(wire): JsonObject<WireInvitation<'_>> =
            serde_json::from_slice(&encoded).unwrap();

        assert!(matches!(wire.secret, Cow::Borrowed(_)));
        assert!(matches!(
            wire.identity_ca_certificate_der_hex,
            Cow::Borrowed(_)
        ));
        assert!(matches!(wire.purpose, Cow::Borrowed(_)));
        assert!(matches!(wire.endpoint.0.ipv4, Cow::Borrowed(_)));
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
        for version in [0, 1, 3, 65536] {
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
            ("version", json!("2")),
            ("version", json!(2.0)),
            ("version", json!(-1)),
            ("version", json!(null)),
            ("purpose", json!(true)),
            ("endpoint", json!(["192.168.1.8", 45833])),
            ("identity_ca_certificate_der_hex", json!(null)),
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
    fn rejects_malformed_certificate_hex_and_all_zero_or_malformed_secrets() {
        for (field, error) in [
            (
                "identity_ca_certificate_der_hex",
                InvitationError::InvalidIdentityCertificate,
            ),
            ("secret", InvitationError::InvalidSecret),
        ] {
            for text in [
                String::new(),
                "0".repeat(1026),
                "a".repeat(63),
                "A".repeat(4),
                "g".repeat(4),
                format!("{} ", "a".repeat(63)),
                "\u{00e9}".repeat(32),
            ] {
                let mut value = fixture();
                value[field] = json!(text);
                assert_eq!(parse_value(&value).unwrap_err(), error);
            }
        }
        let mut value = fixture();
        value["identity_ca_certificate_der_hex"] = json!("AA");
        assert_eq!(
            parse_value(&value).unwrap_err(),
            InvitationError::InvalidIdentityCertificate
        );
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
        assert!(!rendered.contains(value["identity_ca_certificate_der_hex"].as_str().unwrap()));
        let mut value = value;
        value["secret"] = json!("sensitive-invalid-value");
        let rendered = format!("{:?}", parse_value(&value).unwrap_err());
        assert_eq!(rendered, "InvalidSecret");
        assert!(!rendered.contains("sensitive"));
    }
}
