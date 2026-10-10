//! End-to-end tests for the coordinator control plane.
//!
//! Every test uses a mock upstream; no request leaves the machine and no real
//! token appears in this file.

use std::{net::SocketAddr, path::PathBuf, sync::Arc};

use axum::{
    http::{header, HeaderMap, StatusCode},
    routing::get,
    Json, Router,
};
use nipaplay_auth::{DandanplayUpstream, RateLimiter, UpstreamConfig};
use rcgen::{KeyPair, PublicKeyData};
use serde_json::{json, Value};

use crate::{account::AccountResolver, api, cert, config::Config, store::Store};

const VALID_TOKEN: &str = "test-account-token";
const SECOND_TOKEN: &str = "test-second-token";
const ACCOUNT_ID: i64 = 424242;
const SECOND_ACCOUNT_ID: i64 = 515151;

struct Harness {
    base_url: String,
    client: reqwest::Client,
    _dir: TempDir,
}

struct TempDir(PathBuf);

impl TempDir {
    fn new(label: &str) -> Self {
        let path = std::env::temp_dir().join(format!(
            "nipaplay-mesh-test-{label}-{}-{}",
            std::process::id(),
            nipaplay_auth::unix_timestamp()
        ));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Account id recognized for a bearer token, if any.
fn account_for(headers: &HeaderMap) -> Option<i64> {
    let token = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))?;
    match token {
        VALID_TOKEN => Some(ACCOUNT_ID),
        SECOND_TOKEN => Some(SECOND_ACCOUNT_ID),
        _ => None,
    }
}

/// Mock play-history endpoint used for read-only token validation.
async fn mock_playhistory(headers: HeaderMap) -> (StatusCode, Json<Value>) {
    match account_for(&headers) {
        Some(_) => (StatusCode::OK, Json(json!({"success": true}))),
        None => (StatusCode::UNAUTHORIZED, Json(json!({"success": false}))),
    }
}

/// Mock renewal endpoint that also reports the stable numeric account id.
async fn mock_renew(headers: HeaderMap) -> (StatusCode, Json<Value>) {
    match account_for(&headers) {
        Some(account_id) => (
            StatusCode::OK,
            Json(json!({
                "success": true,
                "userId": account_id,
                "userName": format!("tester-{account_id}"),
                "token": "renewed-token",
            })),
        ),
        None => (StatusCode::UNAUTHORIZED, Json(json!({"success": false}))),
    }
}

async fn start_harness(label: &str, configure: impl FnOnce(&mut Config)) -> Harness {
    let dir = TempDir::new(label);

    let upstream_router = Router::new()
        .route("/api/v2/playhistory", get(mock_playhistory))
        .route("/api/v2/login/renew", get(mock_renew));
    let upstream_listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let upstream_addr = upstream_listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(upstream_listener, upstream_router)
            .await
            .unwrap();
    });

    let cert_path = dir.0.join("ca.crt.pem");
    let key_path = dir.0.join("ca.key.pem");
    cert::generate_ca(&cert_path, &key_path).unwrap();

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let listen_addr = listener.local_addr().unwrap();

    let mut config = Config {
        listen: listen_addr,
        database_path: dir.0.join("mesh.db"),
        ca_cert_file: cert_path,
        ca_key_file: key_path,
        cert_validity_seconds: 7 * 86_400,
        heartbeat_interval_seconds: 900,
        address_default_ttl_seconds: 3600,
        address_max_ttl_seconds: 86_400,
        register_per_hour: 10,
        renew_per_hour: 24,
        addresses_per_hour: 60,
        devices_per_hour: 120,
        ip_requests_per_minute: 300,
        trust_proxy_headers: true,
        upstream: UpstreamConfig {
            base_url: format!("http://{upstream_addr}"),
            app_id: "nipaplayv1".to_owned(),
            app_secret: "test-app-secret".to_owned(),
            user_agent: "NipaPlay-Mesh-Test/1.0".to_owned(),
        },
    };
    configure(&mut config);

    let store = Store::open(&config.database_path).unwrap();
    let ca = Arc::new(
        cert::CertificateAuthority::load(&config.ca_cert_file, &config.ca_key_file).unwrap(),
    );
    let upstream = DandanplayUpstream::new(config.upstream.clone()).unwrap();
    let state = api::AppState {
        config: Arc::new(config),
        store,
        ca,
        accounts: AccountResolver::new(upstream),
        limiter: RateLimiter::new(),
    };

    let app = api::router(state);
    tokio::spawn(async move {
        axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await
        .unwrap();
    });

    let client = reqwest::Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap();

    Harness {
        base_url: format!("http://{listen_addr}"),
        client,
        _dir: dir,
    }
}

impl Harness {
    fn url(&self, path: &str) -> String {
        format!("{}{path}", self.base_url)
    }

    async fn register(&self, token: &str, public_key: &[u8], name: &str) -> reqwest::Response {
        self.client
            .post(self.url("/mesh/v1/devices/register"))
            .bearer_auth(token)
            .json(&json!({
                "device_public_key": base64url(public_key),
                "device_name": name,
                "platform": "macos",
                "app_version": "1.0.0",
            }))
            .send()
            .await
            .unwrap()
    }
}

fn base64url(bytes: &[u8]) -> String {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
    URL_SAFE_NO_PAD.encode(bytes)
}

fn new_device_key() -> Vec<u8> {
    KeyPair::generate_for(&rcgen::PKCS_ED25519)
        .unwrap()
        .der_bytes()
        .to_vec()
}

fn config_with_mock_upstream(label: &str) -> impl FnOnce(&mut Config) {
    let _ = label;
    |_config: &mut Config| {}
}

#[tokio::test]
async fn rejects_missing_and_invalid_tokens() {
    let harness = start_harness("auth", config_with_mock_upstream("auth")).await;

    let missing = harness
        .client
        .post(harness.url("/mesh/v1/devices/register"))
        .json(&json!({
            "device_public_key": base64url(&new_device_key()),
            "device_name": "Mac",
            "platform": "macos",
            "app_version": "1.0.0",
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::UNAUTHORIZED);
    let body: Value = missing.json().await.unwrap();
    assert_eq!(body["error"], "missing_token");

    let invalid = harness
        .register("not-a-real-token", &new_device_key(), "Mac")
        .await;
    assert_eq!(invalid.status(), StatusCode::UNAUTHORIZED);
    let body: Value = invalid.json().await.unwrap();
    assert_eq!(body["error"], "invalid_token");
}

#[tokio::test]
async fn register_issues_a_certificate_and_lists_the_device() {
    let harness = start_harness("register", config_with_mock_upstream("register")).await;
    let public_key = new_device_key();
    let device_id = cert::device_id_from_public_key(&public_key);

    let response = harness.register(VALID_TOKEN, &public_key, "工位机").await;
    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = response.json().await.unwrap();
    assert_eq!(body["success"], true);
    assert_eq!(body["account_id"], ACCOUNT_ID.to_string());
    assert_eq!(body["device_id"], device_id);
    assert!(body["certificate"]["pem"]
        .as_str()
        .unwrap()
        .starts_with("-----BEGIN CERTIFICATE-----"));
    assert!(
        body["certificate"]["not_after"].as_i64().unwrap()
            > body["certificate"]["not_before"].as_i64().unwrap()
    );

    let listed: Value = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(VALID_TOKEN)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let devices = listed["devices"].as_array().unwrap();
    assert_eq!(devices.len(), 1);
    assert_eq!(devices[0]["device_id"], device_id);
    assert_eq!(devices[0]["device_name"], "工位机");
    assert_eq!(devices[0]["revoked"], false);
}

#[tokio::test]
async fn devices_are_scoped_to_their_account() {
    let harness = start_harness("scope", config_with_mock_upstream("scope")).await;
    harness
        .register(VALID_TOKEN, &new_device_key(), "Mac")
        .await;

    let listed: Value = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(SECOND_TOKEN)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(listed["devices"].as_array().unwrap().is_empty());
    assert_eq!(listed["account_id"], SECOND_ACCOUNT_ID.to_string());
}

#[tokio::test]
async fn registered_certificate_chains_to_the_coordinator_ca() {
    use x509_parser::prelude::*;

    let harness = start_harness("chain", config_with_mock_upstream("chain")).await;
    let public_key = new_device_key();
    let body: Value = harness
        .register(VALID_TOKEN, &public_key, "Mac")
        .await
        .json()
        .await
        .unwrap();
    let cert_pem = body["certificate"]["pem"].as_str().unwrap();

    let info: Value = harness
        .client
        .get(harness.url("/mesh/v1/server-info"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let ca_pem = info["serverCertificate"].as_str().unwrap();
    assert_eq!(info["addressMaxTtlSeconds"], 2 * 3600);

    let ca_der = x509_parser::pem::parse_x509_pem(ca_pem.as_bytes())
        .unwrap()
        .1
        .contents;
    let cert_der = x509_parser::pem::parse_x509_pem(cert_pem.as_bytes())
        .unwrap()
        .1
        .contents;
    let (_, ca) = X509Certificate::from_der(&ca_der).unwrap();
    let (_, leaf) = X509Certificate::from_der(&cert_der).unwrap();
    leaf.verify_signature(Some(ca.public_key())).unwrap();
    assert_eq!(
        info["serverPublicKey"].as_str().unwrap(),
        base64url(ca.public_key().subject_public_key.data.as_ref())
    );
}

#[tokio::test]
async fn revoke_blocks_renewal_and_bumps_the_epoch() {
    let harness = start_harness("revoke", config_with_mock_upstream("revoke")).await;
    let public_key = new_device_key();
    let body: Value = harness
        .register(VALID_TOKEN, &public_key, "Mac")
        .await
        .json()
        .await
        .unwrap();
    let device_id = body["device_id"].as_str().unwrap().to_owned();

    let revoked: Value = harness
        .client
        .post(harness.url(&format!("/mesh/v1/devices/{device_id}/revoke")))
        .bearer_auth(VALID_TOKEN)
        .json(&json!({ "device_id": device_id }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(revoked["revocation_epoch"], 1);

    let renew = harness
        .client
        .post(harness.url("/mesh/v1/devices/renew"))
        .bearer_auth(VALID_TOKEN)
        .json(&json!({
            "device_id": device_id,
            "device_public_key": base64url(&public_key),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(renew.status(), StatusCode::FORBIDDEN);
    let body: Value = renew.json().await.unwrap();
    assert_eq!(body["error"], "device_revoked");

    let listed: Value = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(VALID_TOKEN)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(listed["devices"][0]["revoked"], true);
    assert_eq!(listed["revocation_epoch"], 1);

    // The revocation epoch is account-scoped: another account is unaffected.
    let other: Value = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(SECOND_TOKEN)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(other["revocation_epoch"], 0);
}

#[tokio::test]
async fn revoking_a_device_drops_its_address_candidates() {
    let harness = start_harness("revoke-addr", config_with_mock_upstream("revoke-addr")).await;
    let public_key = new_device_key();
    let device_id = cert::device_id_from_public_key(&public_key);
    harness.register(VALID_TOKEN, &public_key, "Mac").await;

    let report = harness
        .client
        .post(harness.url("/mesh/v1/addresses"))
        .bearer_auth(VALID_TOKEN)
        .json(&json!({
            "device_id": device_id,
            "candidates": [{ "kind": "lan", "host": "192.168.1.30", "port": 1180 }],
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(report.status(), StatusCode::OK);

    let revoke = harness
        .client
        .post(harness.url(&format!("/mesh/v1/devices/{device_id}/revoke")))
        .bearer_auth(VALID_TOKEN)
        .json(&json!({ "device_id": device_id }))
        .send()
        .await
        .unwrap();
    assert_eq!(revoke.status(), StatusCode::OK);

    let fetched: Value = harness
        .client
        .get(harness.url(&format!("/mesh/v1/addresses?device_id={device_id}")))
        .bearer_auth(VALID_TOKEN)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(fetched["error"], "device_revoked");
}

#[tokio::test]
async fn address_candidates_are_capped_at_two_hours() {
    let harness = start_harness("address-ttl", |config| {
        // Even a deliberately huge configured cap is clamped by the server.
        config.address_max_ttl_seconds = 10 * 86_400;
    })
    .await;
    let public_key = new_device_key();
    let device_id = cert::device_id_from_public_key(&public_key);
    harness.register(VALID_TOKEN, &public_key, "Mac").await;

    let before = nipaplay_auth::unix_timestamp();
    harness
        .client
        .post(harness.url("/mesh/v1/addresses"))
        .bearer_auth(VALID_TOKEN)
        .json(&json!({
            "device_id": device_id,
            "candidates": [
                { "kind": "lan", "host": "192.168.1.31", "port": 1180, "expires_in": 7 * 86_400 },
            ],
        }))
        .send()
        .await
        .unwrap();

    let fetched: Value = harness
        .client
        .get(harness.url(&format!("/mesh/v1/addresses?device_id={device_id}")))
        .bearer_auth(VALID_TOKEN)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let expires_at = fetched["candidates"][0]["expires_at"].as_i64().unwrap();
    assert!(
        expires_at <= before + 2 * 3600 + 5,
        "expires_at {expires_at} exceeds the 2 hour cap"
    );
}

#[tokio::test]
async fn renewal_issues_a_fresh_certificate() {
    let harness = start_harness("renew", config_with_mock_upstream("renew")).await;
    let public_key = new_device_key();
    let device_id = cert::device_id_from_public_key(&public_key);
    harness.register(VALID_TOKEN, &public_key, "Mac").await;

    let response = harness
        .client
        .post(harness.url("/mesh/v1/devices/renew"))
        .bearer_auth(VALID_TOKEN)
        .json(&json!({
            "device_id": device_id,
            "device_public_key": base64url(&public_key),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = response.json().await.unwrap();
    assert!(body["certificate"]["pem"]
        .as_str()
        .unwrap()
        .starts_with("-----BEGIN CERTIFICATE-----"));
}

#[tokio::test]
async fn addresses_round_trip_and_are_visible_to_the_account() {
    let harness = start_harness("addresses", config_with_mock_upstream("addresses")).await;
    let public_key = new_device_key();
    let device_id = cert::device_id_from_public_key(&public_key);
    harness.register(VALID_TOKEN, &public_key, "Mac").await;

    let report = harness
        .client
        .post(harness.url("/mesh/v1/addresses"))
        .bearer_auth(VALID_TOKEN)
        .json(&json!({
            "device_id": device_id,
            "candidates": [
                { "kind": "lan", "host": "192.168.1.20", "port": 1180, "priority": 10, "expires_in": 600 },
                { "kind": "overlay", "host": "100.64.0.5", "port": 1180, "priority": 5 },
            ],
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(report.status(), StatusCode::OK);

    let fetched: Value = harness
        .client
        .get(harness.url(&format!("/mesh/v1/addresses?device_id={device_id}")))
        .bearer_auth(VALID_TOKEN)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let candidates = fetched["candidates"].as_array().unwrap();
    assert_eq!(candidates.len(), 2);
    assert_eq!(candidates[0]["kind"], "lan");
    assert_eq!(candidates[0]["host"], "192.168.1.20");
    assert!(candidates[0]["expires_at"].as_i64().unwrap() > 0);

    let other_account: Value = harness
        .client
        .get(harness.url(&format!("/mesh/v1/addresses?device_id={device_id}")))
        .bearer_auth(SECOND_TOKEN)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(other_account["error"], "device_not_found");
}

#[tokio::test]
async fn rejects_unknown_address_kinds_and_bad_public_keys() {
    let harness = start_harness("validate", config_with_mock_upstream("validate")).await;
    let public_key = new_device_key();
    let device_id = cert::device_id_from_public_key(&public_key);
    harness.register(VALID_TOKEN, &public_key, "Mac").await;

    let bad_kind = harness
        .client
        .post(harness.url("/mesh/v1/addresses"))
        .bearer_auth(VALID_TOKEN)
        .json(&json!({
            "device_id": device_id,
            "candidates": [{ "kind": "carrier-pigeon", "host": "example", "port": 1 }],
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(bad_kind.status(), StatusCode::BAD_REQUEST);

    let bad_key = harness.register(VALID_TOKEN, &[0u8; 8], "Mac").await;
    assert_eq!(bad_key.status(), StatusCode::BAD_REQUEST);
    let body: Value = bad_key.json().await.unwrap();
    assert_eq!(body["error"], "invalid_input");
}

#[tokio::test]
async fn per_ip_rate_limit_returns_429() {
    let harness = start_harness("ip-limit", |config| {
        config.ip_requests_per_minute = 2;
    })
    .await;

    let first = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(VALID_TOKEN)
        .send()
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::OK);
    let second = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(VALID_TOKEN)
        .send()
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::OK);
    let third = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(VALID_TOKEN)
        .send()
        .await
        .unwrap();
    assert_eq!(third.status(), StatusCode::TOO_MANY_REQUESTS);
    let body: Value = third.json().await.unwrap();
    assert_eq!(body["error"], "rate_limited");
}

#[tokio::test]
async fn per_account_register_limit_returns_429() {
    let harness = start_harness("account-limit", |config| {
        config.register_per_hour = 1;
    })
    .await;

    let first = harness
        .register(VALID_TOKEN, &new_device_key(), "Mac")
        .await;
    assert_eq!(first.status(), StatusCode::OK);
    let second = harness
        .register(VALID_TOKEN, &new_device_key(), "MacBook")
        .await;
    assert_eq!(second.status(), StatusCode::TOO_MANY_REQUESTS);
}

#[tokio::test]
async fn health_reports_the_service_name() {
    let harness = start_harness("health", config_with_mock_upstream("health")).await;
    let body: Value = harness
        .client
        .get(harness.url("/healthz"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(body["service"], "nipaplay-mesh-coordinator");
    assert_eq!(body["ok"], true);
}

/// Writes the CA and a leaf certificate from the same run to disk so their
/// structure can be inspected and verified with external tooling.
#[tokio::test]
#[ignore = "writes NIPAPLAY_MESH_DUMP_DIR/ca.pem and leaf.pem for manual inspection"]
async fn dump_certificates_for_manual_inspection() {
    let dir = std::env::var("NIPAPLAY_MESH_DUMP_DIR")
        .expect("set NIPAPLAY_MESH_DUMP_DIR to a writable directory");
    let harness = start_harness("dump", config_with_mock_upstream("dump")).await;
    let body: Value = harness
        .register(VALID_TOKEN, &new_device_key(), "Mac")
        .await
        .json()
        .await
        .unwrap();
    let info: Value = harness
        .client
        .get(harness.url("/mesh/v1/server-info"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    std::fs::write(
        format!("{dir}/leaf.pem"),
        body["certificate"]["pem"].as_str().unwrap(),
    )
    .unwrap();
    std::fs::write(
        format!("{dir}/ca.pem"),
        info["serverCertificate"].as_str().unwrap(),
    )
    .unwrap();
}
