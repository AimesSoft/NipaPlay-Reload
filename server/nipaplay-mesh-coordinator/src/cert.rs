//! X.509 device certificate issuance.
//!
//! The coordinator is the single issuer: it holds an Ed25519 CA key loaded from
//! deployment configuration and signs short-lived device certificates that bind
//! `(account_id, device_id, device_public_key, validity)`.

use std::{fs, path::Path, sync::Arc};

use base64::{engine::general_purpose::URL_SAFE_NO_PAD as B64URL, Engine as _};
use rcgen::{
    BasicConstraints, CertificateParams, CustomExtension, DistinguishedName, DnType,
    ExtendedKeyUsagePurpose, IsCa, Issuer, KeyPair, KeyUsagePurpose, PublicKeyData, SanType,
    SerialNumber, SigningKey, SubjectPublicKeyInfo,
};
use ring::rand::{SecureRandom, SystemRandom};
use sha2::{Digest, Sha256};
use time::{Duration, OffsetDateTime};
#[cfg(test)]
use x509_parser::prelude::FromDer;

/// Private extension carrying the structured device metadata.
///
/// OID `1.3.6.1.4.1.61086.1.1` (unregistered NipaPlay private arc). Content is a
/// DER `UTF8String` holding the JSON document described in the README.
pub const DEVICE_METADATA_OID: &[u64] = &[1, 3, 6, 1, 4, 1, 61086, 1, 1];

/// Length of a raw Ed25519 public key.
pub const ED25519_PUBLIC_KEY_LEN: usize = 32;

/// Fixed DER prefix of an Ed25519 SubjectPublicKeyInfo.
const ED25519_SPKI_PREFIX: [u8; 12] = [
    0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
];

/// Signing key shared across request handlers.
///
/// `rcgen::KeyPair` is not `Clone`, so the CA key is reference-counted and the
/// signing traits are forwarded through this wrapper.
pub struct SharedSigningKey(Arc<KeyPair>);

impl PublicKeyData for SharedSigningKey {
    fn der_bytes(&self) -> &[u8] {
        self.0.der_bytes()
    }

    fn algorithm(&self) -> &'static rcgen::SignatureAlgorithm {
        self.0.algorithm()
    }
}

impl SigningKey for SharedSigningKey {
    fn sign(&self, msg: &[u8]) -> Result<Vec<u8>, rcgen::Error> {
        self.0.sign(msg)
    }
}

/// Certificate authority loaded from deployment configuration.
pub struct CertificateAuthority {
    issuer: Issuer<'static, SharedSigningKey>,
    ca_pem: String,
    public_key_raw: Vec<u8>,
}

impl CertificateAuthority {
    /// Loads an existing CA certificate and private key from PEM files.
    pub fn load(cert_file: &Path, key_file: &Path) -> Result<Self, String> {
        let ca_pem = fs::read_to_string(cert_file)
            .map_err(|error| format!("failed to read {}: {error}", cert_file.display()))?;
        let key_pem = fs::read_to_string(key_file)
            .map_err(|error| format!("failed to read {}: {error}", key_file.display()))?;
        let key = KeyPair::from_pem(&key_pem)
            .map_err(|error| format!("failed to parse {}: {error}", key_file.display()))?;
        if key.algorithm() != &rcgen::PKCS_ED25519 {
            return Err(format!(
                "{} is not an Ed25519 key (found {:?})",
                key_file.display(),
                key.algorithm()
            ));
        }

        let ca_der = pem_certificate_der(&ca_pem)?;
        let issuer =
            Issuer::from_ca_cert_der(&ca_der.as_slice().into(), SharedSigningKey(Arc::new(key)))
                .map_err(|error| format!("failed to parse {}: {error}", cert_file.display()))?;

        // Confirm the configured key actually signs the configured certificate,
        // so a mismatched pair fails at startup instead of at first registration.
        let (_, parsed) = x509_parser::parse_x509_certificate(&ca_der)
            .map_err(|error| format!("failed to parse {}: {error}", cert_file.display()))?;
        parsed
            .verify_signature(None)
            .map_err(|error| format!("{} is not self-signed: {error}", cert_file.display()))?;
        let spki = parsed.public_key();
        let raw = spki.subject_public_key.data.as_ref();
        if raw.len() != ED25519_PUBLIC_KEY_LEN {
            return Err(format!(
                "{} does not hold a raw Ed25519 public key",
                cert_file.display()
            ));
        }

        let authority = Self {
            issuer,
            ca_pem,
            public_key_raw: raw.to_vec(),
        };
        authority.verify_signing_key()?;
        Ok(authority)
    }

    /// Issues and verifies a throwaway certificate so a mismatched key/cert pair
    /// fails at startup rather than at the first real registration.
    fn verify_signing_key(&self) -> Result<(), String> {
        let probe_key = KeyPair::generate_for(&rcgen::PKCS_ED25519)
            .map_err(|error| format!("failed to generate probe key: {error}"))?;
        let probe_public = probe_key.der_bytes().to_vec();
        let issued = self.issue_device_certificate(
            "self-check",
            "self-check",
            &probe_public,
            Duration::minutes(1),
        )?;
        let der = pem_certificate_der(&issued.pem)?;
        let (_, cert) = x509_parser::parse_x509_certificate(&der)
            .map_err(|error| format!("failed to parse self-check certificate: {error}"))?;
        let ca_der = pem_certificate_der(&self.ca_pem)?;
        let (_, ca_cert) = x509_parser::parse_x509_certificate(&ca_der)
            .map_err(|error| format!("failed to parse CA certificate: {error}"))?;
        cert.verify_signature(Some(ca_cert.public_key()))
            .map_err(|_| "CA key does not match the CA certificate".to_owned())
    }

    /// Base64url (no padding) of the CA's raw Ed25519 public key.
    pub fn public_key_base64url(&self) -> String {
        B64URL.encode(&self.public_key_raw)
    }

    /// CA certificate in PEM form, as clients should pin it.
    pub fn certificate_pem(&self) -> &str {
        &self.ca_pem
    }

    fn issuer(&self) -> &Issuer<'static, SharedSigningKey> {
        &self.issuer
    }

    /// Issues a device certificate for the given account and device key.
    pub fn issue_device_certificate(
        &self,
        account_id: &str,
        device_id: &str,
        device_public_key: &[u8],
        validity: Duration,
    ) -> Result<IssuedCertificate, String> {
        let device_spki = ed25519_spki(device_public_key)?;

        let now = OffsetDateTime::now_utc();
        let mut params =
            CertificateParams::new(Vec::<String>::new()).map_err(|error| error.to_string())?;
        params.distinguished_name = DistinguishedName::new();
        params
            .distinguished_name
            .push(DnType::CommonName, format!("device-{device_id}"));
        params
            .distinguished_name
            .push(DnType::OrganizationName, "NipaPlay Mesh");
        params.is_ca = IsCa::ExplicitNoCa;
        params.not_before = now - Duration::minutes(5);
        params.not_after = now + validity;
        params.serial_number = Some(random_serial()?);
        params.use_authority_key_identifier_extension = true;
        params.key_usages.push(KeyUsagePurpose::DigitalSignature);
        params
            .extended_key_usages
            .push(ExtendedKeyUsagePurpose::ClientAuth);
        params
            .extended_key_usages
            .push(ExtendedKeyUsagePurpose::ServerAuth);
        params.subject_alt_names.push(SanType::URI(
            format!("nipaplay-mesh://device?account={account_id}&device={device_id}")
                .try_into()
                .map_err(|error| format!("invalid SAN URI: {error}"))?,
        ));
        let metadata = serde_json::json!({
            "v": 1,
            "accountId": account_id,
            "deviceId": device_id,
            "publicKey": B64URL.encode(device_public_key),
        });
        params
            .custom_extensions
            .push(CustomExtension::from_oid_content(
                DEVICE_METADATA_OID,
                der_utf8_string(metadata.to_string().as_bytes()),
            ));

        let certificate = params
            .signed_by(&device_spki, self.issuer())
            .map_err(|error| format!("failed to sign device certificate: {error}"))?;

        Ok(IssuedCertificate {
            pem: certificate.pem(),
            not_before: params.not_before.unix_timestamp(),
            not_after: params.not_after.unix_timestamp(),
        })
    }
}

pub struct IssuedCertificate {
    pub pem: String,
    pub not_before: i64,
    pub not_after: i64,
}

/// Derives the stable device id from a raw Ed25519 public key.
pub fn device_id_from_public_key(public_key: &[u8]) -> String {
    B64URL.encode(Sha256::digest(public_key))
}

/// Decodes a base64url (unpadded) raw Ed25519 public key.
pub fn decode_device_public_key(encoded: &str) -> Result<Vec<u8>, String> {
    let bytes = B64URL
        .decode(encoded.trim())
        .map_err(|_| "device_public_key is not valid base64url".to_owned())?;
    if bytes.len() != ED25519_PUBLIC_KEY_LEN {
        return Err(format!(
            "device_public_key must be {ED25519_PUBLIC_KEY_LEN} raw bytes, got {}",
            bytes.len()
        ));
    }
    Ok(bytes)
}

/// Decodes a DER `UTF8String` (tag 0x0c) with short or long form length.
#[cfg(test)]
fn decode_utf8_string(der: &[u8]) -> String {
    assert_eq!(der[0], 0x0c, "expected a DER UTF8String");
    let (length, offset) = if der[1] & 0x80 == 0 {
        (der[1] as usize, 2)
    } else {
        let count = (der[1] & 0x7f) as usize;
        let mut length = 0usize;
        for byte in &der[2..2 + count] {
            length = (length << 8) | *byte as usize;
        }
        (length, 2 + count)
    };
    String::from_utf8(der[offset..offset + length].to_vec()).unwrap()
}

fn ed25519_spki(public_key: &[u8]) -> Result<SubjectPublicKeyInfo, String> {
    if public_key.len() != ED25519_PUBLIC_KEY_LEN {
        return Err(format!(
            "device public key must be {ED25519_PUBLIC_KEY_LEN} raw bytes"
        ));
    }
    let mut der = Vec::with_capacity(ED25519_SPKI_PREFIX.len() + public_key.len());
    der.extend_from_slice(&ED25519_SPKI_PREFIX);
    der.extend_from_slice(public_key);
    SubjectPublicKeyInfo::from_der(&der)
        .map_err(|error| format!("invalid device public key: {error}"))
}

fn random_serial() -> Result<SerialNumber, String> {
    let rng = SystemRandom::new();
    let mut bytes = [0u8; 16];
    rng.fill(&mut bytes)
        .map_err(|_| "failed to gather randomness for serial".to_owned())?;
    bytes[0] &= 0x7f;
    if bytes[0] == 0 {
        bytes[0] = 1;
    }
    Ok(SerialNumber::from_slice(&bytes))
}

fn der_utf8_string(value: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(value.len() + 4);
    out.push(0x0c);
    if value.len() < 128 {
        out.push(value.len() as u8);
    } else {
        let mut length = value.len();
        let mut length_bytes = Vec::new();
        while length > 0 {
            length_bytes.push((length & 0xff) as u8);
            length >>= 8;
        }
        length_bytes.reverse();
        out.push(0x80 | length_bytes.len() as u8);
        out.extend_from_slice(&length_bytes);
    }
    out.extend_from_slice(value);
    out
}

fn pem_certificate_der(pem: &str) -> Result<Vec<u8>, String> {
    let (_, parsed) = x509_parser::pem::parse_x509_pem(pem.as_bytes())
        .map_err(|error| format!("failed to parse CA PEM: {error}"))?;
    Ok(parsed.contents)
}

/// Generates a fresh development CA and writes the certificate and key PEMs.
///
/// The private key file is created with owner-only permissions.
pub fn generate_ca(cert_file: &Path, key_file: &Path) -> Result<(), String> {
    let key_pair = KeyPair::generate_for(&rcgen::PKCS_ED25519)
        .map_err(|error| format!("failed to generate CA key: {error}"))?;

    let mut params =
        CertificateParams::new(Vec::<String>::new()).map_err(|error| error.to_string())?;
    params.distinguished_name = DistinguishedName::new();
    params
        .distinguished_name
        .push(DnType::CommonName, "NipaPlay Mesh Coordinator CA");
    params
        .distinguished_name
        .push(DnType::OrganizationName, "NipaPlay Mesh");
    params.is_ca = IsCa::Ca(BasicConstraints::Constrained(0));
    params.key_usages.push(KeyUsagePurpose::KeyCertSign);
    params.key_usages.push(KeyUsagePurpose::CrlSign);
    params.key_usages.push(KeyUsagePurpose::DigitalSignature);
    params.not_before = OffsetDateTime::now_utc() - Duration::minutes(5);
    params.not_after = OffsetDateTime::now_utc() + Duration::days(3650);
    params.serial_number = Some(random_serial()?);

    let certificate = params
        .self_signed(&key_pair)
        .map_err(|error| format!("failed to self-sign CA: {error}"))?;

    write_file(cert_file, certificate.pem().as_bytes(), false)?;
    write_file(key_file, key_pair.serialize_pem().as_bytes(), true)?;
    Ok(())
}

fn write_file(path: &Path, contents: &[u8], private: bool) -> Result<(), String> {
    if path.exists() {
        return Err(format!("{} already exists", path.display()));
    }
    fs::write(path, contents)
        .map_err(|error| format!("failed to write {}: {error}", path.display()))?;
    #[cfg(unix)]
    if private {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))
            .map_err(|error| format!("failed to chmod {}: {error}", path.display()))?;
    }
    #[cfg(not(unix))]
    let _ = private;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_ca() -> CertificateAuthority {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let unique = COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir =
            std::env::temp_dir().join(format!("nipaplay-mesh-ca-{}-{unique}", std::process::id()));
        let cert = dir.join("ca.crt.pem");
        let key = dir.join("ca.key.pem");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        generate_ca(&cert, &key).unwrap();
        CertificateAuthority::load(&cert, &key).unwrap()
    }

    #[test]
    fn issues_a_device_certificate_that_verifies_against_the_ca() {
        let ca = test_ca();
        let device_key = KeyPair::generate_for(&rcgen::PKCS_ED25519).unwrap();
        let raw = device_key.der_bytes().to_vec();
        let device_id = device_id_from_public_key(&raw);

        let issued = ca
            .issue_device_certificate("acct-1", &device_id, &raw, Duration::days(7))
            .unwrap();

        let der = pem_certificate_der(&issued.pem).unwrap();
        let (_, cert) = x509_parser::parse_x509_certificate(&der).unwrap();

        let ca_der = pem_certificate_der(ca.certificate_pem()).unwrap();
        let (_, ca_cert) = x509_parser::parse_x509_certificate(&ca_der).unwrap();
        cert.verify_signature(Some(ca_cert.public_key())).unwrap();

        let san = cert
            .subject_alternative_name()
            .unwrap()
            .expect("device certificate has a SAN");
        let uri = san.value.general_names.iter().find_map(|name| match name {
            x509_parser::extensions::GeneralName::URI(uri) => Some(*uri),
            _ => None,
        });
        assert_eq!(
            uri,
            Some(format!("nipaplay-mesh://device?account=acct-1&device={device_id}").as_str())
        );

        let metadata = cert
            .extensions()
            .iter()
            .find(|ext| {
                ext.oid
                    .iter()
                    .map(|components| components.collect::<Vec<_>>())
                    .is_some_and(|components| components == DEVICE_METADATA_OID)
            })
            .expect("metadata extension present");
        assert!(!metadata.critical);
        let payload: serde_json::Value =
            serde_json::from_str(&decode_utf8_string(metadata.value)).unwrap();
        assert_eq!(payload["accountId"], "acct-1");
        assert_eq!(payload["deviceId"], device_id);
        assert_eq!(payload["publicKey"], B64URL.encode(&raw));

        assert!(!cert.is_ca());
        assert_eq!(
            issued.not_after - issued.not_before,
            Duration::days(7).whole_seconds() + 300
        );
    }

    #[test]
    fn a_client_can_verify_with_only_the_pinned_issuer_public_key() {
        let ca = test_ca();
        let device_key = KeyPair::generate_for(&rcgen::PKCS_ED25519).unwrap();
        let raw = device_key.der_bytes().to_vec();
        let device_id = device_id_from_public_key(&raw);
        let issued = ca
            .issue_device_certificate("acct-7", &device_id, &raw, Duration::days(7))
            .unwrap();

        // The client only has the base64url issuer key from `server-info`.
        let pinned = ca.public_key_base64url();
        let pinned_raw = B64URL.decode(pinned).unwrap();
        assert_eq!(pinned_raw.len(), ED25519_PUBLIC_KEY_LEN);

        let der = pem_certificate_der(&issued.pem).unwrap();
        let (_, cert) = x509_parser::parse_x509_certificate(&der).unwrap();

        // Build the issuer's SubjectPublicKeyInfo DER exactly as a client would
        // from the pinned raw key.
        let mut spki_der = ED25519_SPKI_PREFIX.to_vec();
        spki_der.extend_from_slice(&pinned_raw);
        let (_, spki) = x509_parser::x509::SubjectPublicKeyInfo::from_der(&spki_der).unwrap();
        cert.verify_signature(Some(&spki)).unwrap();

        // The certificate must not be usable as a CA and must not be revoked
        // by construction: the issuer only signs after the store check.
        assert!(!cert.is_ca());
        let san = cert.subject_alternative_name().unwrap().unwrap();
        let uri = san.value.general_names.iter().find_map(|name| match name {
            x509_parser::extensions::GeneralName::URI(uri) => Some(*uri),
            _ => None,
        });
        assert!(uri.unwrap().contains("account=acct-7"));
    }

    #[test]
    fn rejects_public_keys_of_the_wrong_length() {
        assert!(decode_device_public_key("AAAA").is_err());
        assert!(decode_device_public_key("not base64!!").is_err());
    }

    #[test]
    fn device_id_is_derived_from_the_public_key() {
        let key = KeyPair::generate_for(&rcgen::PKCS_ED25519).unwrap();
        let raw = key.der_bytes().to_vec();
        let id = device_id_from_public_key(&raw);
        assert_eq!(id.len(), 43); // 32-byte digest in base64url without padding
        assert_eq!(id, device_id_from_public_key(&raw));
    }
}
