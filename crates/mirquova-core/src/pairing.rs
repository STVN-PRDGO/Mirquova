//! Certificate identity and standard Rustls configuration for pairing.
use rcgen::{
    BasicConstraints, CertificateParams, ExtendedKeyUsagePurpose, IsCa, Issuer, KeyPair,
    KeyUsagePurpose,
};
use rustls::{
    ClientConfig, RootCertStore, ServerConfig,
    pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer, ServerName},
    server::WebPkiClientVerifier,
};
use std::{fmt, sync::Arc};
use x509_parser::parse_x509_certificate;
use zeroize::Zeroizing;

const TLS_SERVER_NAME: &str = "mirquova.local";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PairingCryptoError {
    InvalidIdentityCertificate,
    InvalidIdentityKey,
    CertificateGeneration,
    TlsConfiguration,
}

/// An installation identity. The private key is held in a zeroizing buffer;
/// callers must persist it only in OS-backed storage and never log it.
pub struct PairingIdentity {
    certificate_der: Vec<u8>,
    private_key_pkcs8_der: Zeroizing<Vec<u8>>,
}

impl fmt::Debug for PairingIdentity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("PairingIdentity { redacted }")
    }
}

impl PairingIdentity {
    pub fn generate() -> Result<Self, PairingCryptoError> {
        let mut params = CertificateParams::default();
        params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        params.key_usages = vec![
            KeyUsagePurpose::DigitalSignature,
            KeyUsagePurpose::KeyCertSign,
            KeyUsagePurpose::CrlSign,
        ];
        params
            .distinguished_name
            .push(rcgen::DnType::CommonName, "Mirquova device identity");
        let key = KeyPair::generate().map_err(|_| PairingCryptoError::CertificateGeneration)?;
        let certificate = params
            .self_signed(&key)
            .map_err(|_| PairingCryptoError::CertificateGeneration)?;
        Self::from_stored(certificate.der().as_ref(), &key.serialize_der())
    }

    /// Loads key material returned by OS-backed storage and checks that it can
    /// issue certificates for this CA. No trust is established by loading it.
    pub fn from_stored(
        certificate_der: &[u8],
        private_key_pkcs8_der: &[u8],
    ) -> Result<Self, PairingCryptoError> {
        validate_ca(certificate_der)?;
        let private_key = Zeroizing::new(private_key_pkcs8_der.to_vec());
        let _issuer = issuer(certificate_der, &private_key)?;
        Ok(Self {
            certificate_der: certificate_der.to_vec(),
            private_key_pkcs8_der: private_key,
        })
    }

    pub fn certificate_der(&self) -> &[u8] {
        &self.certificate_der
    }

    /// Returns the PKCS#8 key for an OS secure-storage adapter. The returned
    /// copy is secret material and must be cleared promptly by its caller.
    pub fn private_key_pkcs8_der(&self) -> &[u8] {
        &self.private_key_pkcs8_der
    }

    pub fn bootstrap_server_config(&self) -> Result<Arc<ServerConfig>, PairingCryptoError> {
        let (certificate, key) = self.issue_leaf(true)?;
        let config = tls13_server_builder()
            .with_no_client_auth()
            .with_single_cert(certificate, key)
            .map_err(|_| PairingCryptoError::TlsConfiguration)?;
        Ok(Arc::new(config))
    }

    pub fn bootstrap_client_config(
        peer_ca_certificate_der: &[u8],
    ) -> Result<Arc<ClientConfig>, PairingCryptoError> {
        let roots = root_store(peer_ca_certificate_der)?;
        let config = tls13_client_builder()
            .with_root_certificates(roots)
            .with_no_client_auth();
        Ok(Arc::new(config))
    }

    pub fn mutual_server_config(
        &self,
        joining_ca_certificate_der: &[u8],
    ) -> Result<Arc<ServerConfig>, PairingCryptoError> {
        let roots = Arc::new(root_store(joining_ca_certificate_der)?);
        let verifier = WebPkiClientVerifier::builder(roots)
            .build()
            .map_err(|_| PairingCryptoError::TlsConfiguration)?;
        let (certificate, key) = self.issue_leaf(true)?;
        let config = tls13_server_builder()
            .with_client_cert_verifier(verifier)
            .with_single_cert(certificate, key)
            .map_err(|_| PairingCryptoError::TlsConfiguration)?;
        Ok(Arc::new(config))
    }

    pub fn mutual_client_config(
        &self,
        peer_ca_certificate_der: &[u8],
    ) -> Result<Arc<ClientConfig>, PairingCryptoError> {
        let roots = root_store(peer_ca_certificate_der)?;
        let (certificate, key) = self.issue_leaf(false)?;
        let config = tls13_client_builder()
            .with_root_certificates(roots)
            .with_client_auth_cert(certificate, key)
            .map_err(|_| PairingCryptoError::TlsConfiguration)?;
        Ok(Arc::new(config))
    }

    fn issue_leaf(
        &self,
        server: bool,
    ) -> Result<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>), PairingCryptoError> {
        let ca_der = CertificateDer::from(self.certificate_der.clone());
        let issuer = issuer(&ca_der, &self.private_key_pkcs8_der)?;
        let mut params = CertificateParams::new(vec![TLS_SERVER_NAME.to_owned()])
            .map_err(|_| PairingCryptoError::CertificateGeneration)?;
        params.is_ca = IsCa::NoCa;
        params.key_usages = vec![KeyUsagePurpose::DigitalSignature];
        params.extended_key_usages = vec![if server {
            ExtendedKeyUsagePurpose::ServerAuth
        } else {
            ExtendedKeyUsagePurpose::ClientAuth
        }];
        let leaf_key =
            KeyPair::generate().map_err(|_| PairingCryptoError::CertificateGeneration)?;
        let leaf_certificate = params
            .signed_by(&leaf_key, &issuer)
            .map_err(|_| PairingCryptoError::CertificateGeneration)?;
        let key = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(leaf_key.serialize_der()));
        Ok((vec![leaf_certificate.der().clone()], key))
    }
}

pub fn tls_server_name() -> ServerName<'static> {
    TLS_SERVER_NAME
        .try_into()
        .expect("the fixed TLS server name is valid")
}

pub fn validate_ca(certificate_der: &[u8]) -> Result<(), PairingCryptoError> {
    let (remaining, certificate) = parse_x509_certificate(certificate_der)
        .map_err(|_| PairingCryptoError::InvalidIdentityCertificate)?;
    let constraints = certificate
        .basic_constraints()
        .map_err(|_| PairingCryptoError::InvalidIdentityCertificate)?
        .ok_or(PairingCryptoError::InvalidIdentityCertificate)?;
    let usage = certificate
        .key_usage()
        .map_err(|_| PairingCryptoError::InvalidIdentityCertificate)?
        .ok_or(PairingCryptoError::InvalidIdentityCertificate)?;
    if !remaining.is_empty()
        || !constraints.value.ca
        || !usage.value.key_cert_sign()
        || certificate.tbs_certificate.subject != certificate.tbs_certificate.issuer
    {
        return Err(PairingCryptoError::InvalidIdentityCertificate);
    }
    Ok(())
}

fn root_store(certificate_der: &[u8]) -> Result<RootCertStore, PairingCryptoError> {
    validate_ca(certificate_der)?;
    let mut roots = RootCertStore::empty();
    roots
        .add(CertificateDer::from(certificate_der.to_vec()))
        .map_err(|_| PairingCryptoError::InvalidIdentityCertificate)?;
    Ok(roots)
}

fn issuer(
    certificate_der: &[u8],
    private_key_pkcs8_der: &[u8],
) -> Result<Issuer<'static, KeyPair>, PairingCryptoError> {
    validate_ca(certificate_der)?;
    let (_, certificate) = parse_x509_certificate(certificate_der)
        .map_err(|_| PairingCryptoError::InvalidIdentityCertificate)?;
    let key_der = PrivatePkcs8KeyDer::from(private_key_pkcs8_der.to_vec());
    let key = KeyPair::try_from(&key_der).map_err(|_| PairingCryptoError::InvalidIdentityKey)?;
    if key.public_key_raw() != certificate.public_key().subject_public_key.data.as_ref() {
        return Err(PairingCryptoError::InvalidIdentityKey);
    }
    Issuer::from_ca_cert_der(&CertificateDer::from(certificate_der.to_vec()), key)
        .map_err(|_| PairingCryptoError::InvalidIdentityCertificate)
}

fn tls13_client_builder() -> rustls::ConfigBuilder<ClientConfig, rustls::WantsVerifier> {
    ClientConfig::builder_with_protocol_versions(&[&rustls::version::TLS13])
}

fn tls13_server_builder() -> rustls::ConfigBuilder<ServerConfig, rustls::WantsVerifier> {
    ServerConfig::builder_with_protocol_versions(&[&rustls::version::TLS13])
}

#[cfg(test)]
mod tests {
    use super::*;
    use rcgen::generate_simple_self_signed;
    use std::{
        io::{Read, Write},
        net::{TcpListener, TcpStream},
        thread,
        time::Duration,
    };

    fn exchange(
        client_config: Arc<ClientConfig>,
        server_config: Arc<ServerConfig>,
    ) -> Result<(), String> {
        let listener = TcpListener::bind(("127.0.0.1", 0)).map_err(|error| error.to_string())?;
        let address = listener.local_addr().map_err(|error| error.to_string())?;
        let server = thread::spawn(move || -> Result<(), String> {
            let (socket, _) = listener.accept().map_err(|error| error.to_string())?;
            socket
                .set_read_timeout(Some(Duration::from_secs(2)))
                .map_err(|error| error.to_string())?;
            socket
                .set_write_timeout(Some(Duration::from_secs(2)))
                .map_err(|error| error.to_string())?;
            let connection =
                rustls::ServerConnection::new(server_config).map_err(|error| error.to_string())?;
            let mut stream = rustls::StreamOwned::new(connection, socket);
            let mut byte = [0];
            stream
                .read_exact(&mut byte)
                .map_err(|error| error.to_string())?;
            if byte != [7] {
                return Err("unexpected application data".to_owned());
            }
            stream.write_all(&[9]).map_err(|error| error.to_string())
        });

        let socket = TcpStream::connect(address).map_err(|error| error.to_string())?;
        socket
            .set_read_timeout(Some(Duration::from_secs(2)))
            .map_err(|error| error.to_string())?;
        socket
            .set_write_timeout(Some(Duration::from_secs(2)))
            .map_err(|error| error.to_string())?;
        let connection = rustls::ClientConnection::new(client_config, tls_server_name())
            .map_err(|error| error.to_string())?;
        let mut stream = rustls::StreamOwned::new(connection, socket);
        stream.write_all(&[7]).map_err(|error| error.to_string())?;
        let mut response = [0];
        stream
            .read_exact(&mut response)
            .map_err(|error| error.to_string())?;
        if response != [9] {
            return Err("unexpected server response".to_owned());
        }
        server
            .join()
            .map_err(|_| "TLS server task panicked".to_owned())?
    }

    fn plaintext_exchange(server_config: Arc<ServerConfig>) -> Result<(), String> {
        let listener = TcpListener::bind(("127.0.0.1", 0)).map_err(|error| error.to_string())?;
        let address = listener.local_addr().map_err(|error| error.to_string())?;
        let server = thread::spawn(move || -> Result<(), String> {
            let (socket, _) = listener.accept().map_err(|error| error.to_string())?;
            socket
                .set_read_timeout(Some(Duration::from_secs(2)))
                .map_err(|error| error.to_string())?;
            let connection =
                rustls::ServerConnection::new(server_config).map_err(|error| error.to_string())?;
            let mut stream = rustls::StreamOwned::new(connection, socket);
            let mut byte = [0];
            stream
                .read_exact(&mut byte)
                .map_err(|error| error.to_string())
        });

        let mut socket = TcpStream::connect(address).map_err(|error| error.to_string())?;
        socket
            .write_all(b"plain HTTP data is not a TLS handshake")
            .map_err(|error| error.to_string())?;
        socket
            .shutdown(std::net::Shutdown::Write)
            .map_err(|error| error.to_string())?;
        server
            .join()
            .map_err(|_| "TLS server task panicked".to_owned())?
    }

    #[test]
    fn creates_redacted_ca_identity_and_builds_tls13_configurations() {
        let host = PairingIdentity::generate().unwrap();
        let joiner = PairingIdentity::generate().unwrap();

        assert_eq!(validate_ca(host.certificate_der()), Ok(()));
        assert_eq!(validate_ca(joiner.certificate_der()), Ok(()));
        assert_eq!(format!("{host:?}"), "PairingIdentity { redacted }");
        assert!(host.bootstrap_server_config().is_ok());
        assert!(PairingIdentity::bootstrap_client_config(host.certificate_der()).is_ok());
        assert!(host.mutual_server_config(joiner.certificate_der()).is_ok());
        assert!(joiner.mutual_client_config(host.certificate_der()).is_ok());
    }

    #[test]
    fn rejects_end_entity_and_malformed_identity_certificates() {
        let end_entity = generate_simple_self_signed(vec![TLS_SERVER_NAME.to_owned()]).unwrap();
        assert_eq!(
            validate_ca(end_entity.cert.der().as_ref()),
            Err(PairingCryptoError::InvalidIdentityCertificate)
        );
        assert_eq!(
            validate_ca(b"not a certificate"),
            Err(PairingCryptoError::InvalidIdentityCertificate)
        );
    }

    #[test]
    fn rejects_a_private_key_that_does_not_match_the_identity_certificate() {
        let first = PairingIdentity::generate().unwrap();
        let second = PairingIdentity::generate().unwrap();
        assert_eq!(
            PairingIdentity::from_stored(first.certificate_der(), second.private_key_pkcs8_der())
                .unwrap_err(),
            PairingCryptoError::InvalidIdentityKey
        );
    }

    #[test]
    fn standard_tls13_verifier_accepts_pinned_ca_and_mtls_identity() {
        let host = PairingIdentity::generate().unwrap();
        let joiner = PairingIdentity::generate().unwrap();
        let client =
            PairingIdentity::mutual_client_config(&joiner, host.certificate_der()).unwrap();
        let server = host.mutual_server_config(joiner.certificate_der()).unwrap();
        assert_eq!(exchange(client, server), Ok(()));
    }

    #[test]
    fn standard_tls13_verifier_rejects_wrong_ca_before_application_data() {
        let host = PairingIdentity::generate().unwrap();
        let unrelated = PairingIdentity::generate().unwrap();
        let client = PairingIdentity::bootstrap_client_config(unrelated.certificate_der()).unwrap();
        let server = host.bootstrap_server_config().unwrap();
        assert!(exchange(client, server).is_err());
    }

    #[test]
    fn tls12_only_client_cannot_downgrade_the_tls13_pairing_server() {
        let host = PairingIdentity::generate().unwrap();
        let roots = root_store(host.certificate_der()).unwrap();
        let client = ClientConfig::builder_with_protocol_versions(&[&rustls::version::TLS12])
            .with_root_certificates(roots)
            .with_no_client_auth();
        assert!(exchange(client.into(), host.bootstrap_server_config().unwrap()).is_err());
    }

    #[test]
    fn plaintext_cannot_complete_the_tls13_pairing_handshake() {
        let host = PairingIdentity::generate().unwrap();
        assert!(plaintext_exchange(host.bootstrap_server_config().unwrap()).is_err());
    }
}
