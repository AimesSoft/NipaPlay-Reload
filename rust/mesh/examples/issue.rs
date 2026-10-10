//! Offline certificates for the Mesh integration tests. Inputs and private
//! device keys stay in the test process; only public certificates are returned.
use base64::{engine::general_purpose::URL_SAFE_NO_PAD as B64, Engine as _};
use rcgen::{
    CertificateParams, ExtendedKeyUsagePurpose, IsCa, Issuer, KeyPair, KeyUsagePurpose, SanType,
    SubjectPublicKeyInfo,
};
use serde_json::Value;
use std::io::Read;
use time::{Duration, OffsetDateTime};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input)?;
    let json: Value = serde_json::from_str(&input)?;
    let ca = std::fs::read_to_string(json["ca"].as_str().ok_or("missing CA path")?)?;
    let key = KeyPair::from_pem(&std::fs::read_to_string(
        json["key"].as_str().ok_or("missing CA key path")?,
    )?)?;
    let issuer = Issuer::from_ca_cert_pem(&ca, key)?;
    let public = B64.decode(json["publicKey"].as_str().ok_or("missing public key")?)?;
    let device = nipaplay_mesh::device_id(&public);
    let account = json["account"].as_str().ok_or("missing account")?;
    let mut spki = vec![
        0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
    ];
    spki.extend_from_slice(&public);
    let public = SubjectPublicKeyInfo::from_der(&spki)?;
    let mut params = CertificateParams::new(vec![nipaplay_mesh::device_dns_name(&device)?])?;
    params.is_ca = IsCa::ExplicitNoCa;
    params.key_usages = vec![KeyUsagePurpose::DigitalSignature];
    params.extended_key_usages = vec![
        ExtendedKeyUsagePurpose::ServerAuth,
        ExtendedKeyUsagePurpose::ClientAuth,
    ];
    params.subject_alt_names.push(SanType::URI(
        format!("nipaplay-mesh://device?account={account}&device={device}").try_into()?,
    ));
    let now = OffsetDateTime::now_utc();
    params.not_before = now - Duration::days(2);
    params.not_after = now + Duration::seconds(json["validitySeconds"].as_i64().unwrap_or(3600));
    let cert = params.signed_by(&public, &issuer)?;
    print!("{}", cert.pem());
    Ok(())
}
