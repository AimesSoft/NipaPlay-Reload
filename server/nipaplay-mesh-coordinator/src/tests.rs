//! End-to-end tests for the coordinator control plane.
//!
//! Every test uses a mock upstream; no request leaves the machine and no real
//! token appears in this file.

use std::{
    net::SocketAddr,
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
};

use axum::{
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use nipaplay_auth::{DandanplayUpstream, RateLimiter};
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
    store: Store,
    validation_calls: Arc<AtomicUsize>,
    lookup_calls: Arc<AtomicUsize>,
    gateway_base: String,
    tasks: Vec<tokio::task::JoinHandle<()>>,
}

impl Drop for Harness {
    fn drop(&mut self) {
        for task in &self.tasks {
            task.abort();
        }
    }
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
    let encoded = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))?;
    let payload = encoded.split('.').nth(1)?;
    let bytes = {
        use base64::Engine as _;
        base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(payload)
            .ok()?
    };
    let json: Value = serde_json::from_slice(&bytes).ok()?;
    let token = json["test_case"].as_str()?;
    match token {
        VALID_TOKEN => Some(ACCOUNT_ID),
        "test-same-account-token" => Some(ACCOUNT_ID),
        SECOND_TOKEN => Some(SECOND_ACCOUNT_ID),
        "test-zero-id"
        | "test-negative-id"
        | "test-string-id"
        | "test-missing-id"
        | "test-upstream-error"
        | "test-malformed-upstream" => Some(ACCOUNT_ID),
        _ => None,
    }
}

/// Mock play-history endpoint used for read-only token validation.
async fn mock_playhistory(headers: HeaderMap) -> Response {
    for name in ["x-appid", "x-timestamp", "x-signature"] {
        assert!(!headers.contains_key(name));
    }
    if nipaplay_auth::bearer_token(&headers) == Some("synthetic-upstream-accepted-opaque") {
        return Json(json!({"success":true})).into_response();
    }
    if let Some(encoded) = nipaplay_auth::bearer_token(&headers) {
        use base64::Engine as _;
        if let Some(part) = encoded.split('.').nth(1) {
            if let Ok(bytes) = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(part) {
                if let Ok(payload) = serde_json::from_slice::<Value>(&bytes) {
                    match payload["test_case"].as_str() {
                        Some("test-upstream-error") => {
                            return (StatusCode::INTERNAL_SERVER_ERROR, "test-secret-in-upstream")
                                .into_response()
                        }
                        Some("test-malformed-upstream") => {
                            return "test-secret-in-malformed".into_response()
                        }
                        _ => {}
                    }
                }
            }
        }
    }
    match account_for(&headers) {
        Some(_) => (StatusCode::OK, Json(json!({"success": true}))),
        None => (StatusCode::UNAUTHORIZED, Json(json!({"success": false}))),
    }
    .into_response()
}

async fn start_harness(label: &str, configure: impl FnOnce(&mut Config)) -> Harness {
    start_harness_with_methods(label, configure, true).await
}

async fn start_harness_with_methods(
    label: &str,
    configure: impl FnOnce(&mut Config),
    allow_post: bool,
) -> Harness {
    let dir = TempDir::new(label);

    let validation_calls = Arc::new(AtomicUsize::new(0));
    let lookup_calls = Arc::new(AtomicUsize::new(0));
    let validation_count = validation_calls.clone();
    let lookup_count = lookup_calls.clone();
    let _ = allow_post;
    let renewal = get(move || {
        lookup_count.fetch_add(1, Ordering::SeqCst);
        async {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "renew must never be called",
            )
        }
    })
    .post(|| async {
        panic!("renew must never be called");
        #[allow(unreachable_code)]
        StatusCode::INTERNAL_SERVER_ERROR
    });

    let upstream_router = Router::new()
        .route(
            "/dandanplay/api/v2/playhistory",
            get(move |headers: HeaderMap| {
                validation_count.fetch_add(1, Ordering::SeqCst);
                mock_playhistory(headers)
            }),
        )
        .route("/dandanplay/api/v2/login/renew", renewal);
    let upstream_listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let upstream_addr = upstream_listener.local_addr().unwrap();
    let upstream_task = tokio::spawn(async move {
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
        account_claim_pointer: "/userId".to_owned(),
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
        gateway_base: format!("http://{upstream_addr}/dandanplay/"),
        gateway_user_agent: "NipaPlay-Mesh-Test/1.0".to_owned(),
    };
    configure(&mut config);

    let store = Store::open(&config.database_path).unwrap();
    let ca = Arc::new(
        cert::CertificateAuthority::load(&config.ca_cert_file, &config.ca_key_file).unwrap(),
    );
    let upstream = DandanplayUpstream::via_gateway_with_client(
        config.gateway_base.clone(),
        config.gateway_user_agent.clone(),
        reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap(),
    )
    .unwrap();
    let claim_pointer = config.account_claim_pointer.clone();
    let gateway_base = config.gateway_base.clone();
    let state = api::AppState {
        config: Arc::new(config),
        store: store.clone(),
        ca,
        accounts: AccountResolver::new(upstream, claim_pointer),
        limiter: RateLimiter::new(),
    };

    let app = api::router(state);
    let server_task = tokio::spawn(async move {
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
        store,
        validation_calls,
        lookup_calls,
        gateway_base,
        tasks: vec![upstream_task, server_task],
    }
}

impl Harness {
    fn url(&self, path: &str) -> String {
        format!("{}{path}", self.base_url)
    }

    async fn register(&self, token: &str, public_key: &[u8], name: &str) -> reqwest::Response {
        self.client
            .post(self.url("/mesh/v1/devices/register"))
            .bearer_auth(test_token(token))
            .json(&json!({
                "device_public_key": base64url(public_key),
                "device_name": name,
                "platform": "macos",
                "app_version": "1.0.0",
                "proof": possession(public_key, vec!["register".into(), base64url(public_key), name.into(), "macos".into(), "1.0.0".into()]),
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

fn test_keys() -> &'static std::sync::Mutex<std::collections::HashMap<Vec<u8>, Vec<u8>>> {
    static KEYS: std::sync::OnceLock<
        std::sync::Mutex<std::collections::HashMap<Vec<u8>, Vec<u8>>>,
    > = std::sync::OnceLock::new();
    KEYS.get_or_init(Default::default)
}
fn new_device_key() -> Vec<u8> {
    use ring::signature::KeyPair as _;
    let private =
        ring::signature::Ed25519KeyPair::generate_pkcs8(&ring::rand::SystemRandom::new()).unwrap();
    let key = ring::signature::Ed25519KeyPair::from_pkcs8(private.as_ref()).unwrap();
    let public = key.public_key().as_ref().to_vec();
    test_keys()
        .lock()
        .unwrap()
        .insert(public.clone(), private.as_ref().to_vec());
    public
}
fn possession(public: &[u8], fields: Vec<String>) -> Value {
    static NONCE: AtomicUsize = AtomicUsize::new(0);
    let nonce = format!(
        "test-possession-nonce-{:016}",
        NONCE.fetch_add(1, Ordering::SeqCst)
    );
    let timestamp = nipaplay_auth::unix_timestamp();
    let mut message = vec![
        "nipaplay-mesh-possession-v1".to_owned(),
        timestamp.to_string(),
        nonce.clone(),
    ];
    message.extend(fields);
    let keys = test_keys().lock().unwrap();
    let Some(private) = keys.get(public) else {
        return json!({"timestamp":timestamp, "nonce":nonce, "signature":"invalid-test-signature"});
    };
    let key = ring::signature::Ed25519KeyPair::from_pkcs8(private).unwrap();
    json!({"timestamp":timestamp, "nonce":nonce, "signature":base64url(key.sign(&serde_json::to_vec(&message).unwrap()).as_ref())})
}
fn test_token(label: impl AsRef<str>) -> String {
    let label = label.as_ref();
    if !label.starts_with("test-") {
        return label.to_owned();
    }
    let id = if label == SECOND_TOKEN {
        SECOND_ACCOUNT_ID
    } else {
        ACCOUNT_ID
    };
    let mut payload = json!({"userId":id, "identity":{"uid":id}, "test_case":label});
    match label {
        "test-zero-id" => payload["userId"] = json!(0),
        "test-negative-id" => payload["userId"] = json!(-1),
        "test-string-id" => payload["userId"] = json!({}),
        "test-missing-id" => {
            payload.as_object_mut().unwrap().remove("userId");
        }
        _ => {}
    }
    format!(
        "{}.{}.test-signature",
        base64url(br#"{"alg":"EdDSA"}"#),
        base64url(&serde_json::to_vec(&payload).unwrap())
    )
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
        .bearer_auth(test_token(VALID_TOKEN))
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
        .bearer_auth(test_token(SECOND_TOKEN))
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
        .bearer_auth(test_token(VALID_TOKEN))
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
        .bearer_auth(test_token(VALID_TOKEN))
        .json(&json!({
            "device_id": device_id,
            "device_public_key": base64url(&public_key),
            "proof": possession(&public_key, vec!["renew".into(), base64url(&public_key), device_id.clone()]),
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
        .bearer_auth(test_token(VALID_TOKEN))
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
        .bearer_auth(test_token(SECOND_TOKEN))
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
        .bearer_auth(test_token(VALID_TOKEN))
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
        .bearer_auth(test_token(VALID_TOKEN))
        .json(&json!({ "device_id": device_id }))
        .send()
        .await
        .unwrap();
    assert_eq!(revoke.status(), StatusCode::OK);

    let fetched: Value = harness
        .client
        .get(harness.url(&format!("/mesh/v1/addresses?device_id={device_id}")))
        .bearer_auth(test_token(VALID_TOKEN))
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
        .bearer_auth(test_token(VALID_TOKEN))
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
        .bearer_auth(test_token(VALID_TOKEN))
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
        .bearer_auth(test_token(VALID_TOKEN))
        .json(&json!({
            "device_id": device_id,
            "device_public_key": base64url(&public_key),
            "proof": possession(&public_key, vec!["renew".into(), base64url(&public_key), device_id.clone()]),
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
        .bearer_auth(test_token(VALID_TOKEN))
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
        .bearer_auth(test_token(VALID_TOKEN))
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
        .bearer_auth(test_token(SECOND_TOKEN))
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
        .bearer_auth(test_token(VALID_TOKEN))
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
        .bearer_auth(test_token(VALID_TOKEN))
        .send()
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::OK);
    let second = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(test_token(VALID_TOKEN))
        .send()
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::OK);
    let third = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(test_token(VALID_TOKEN))
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

#[tokio::test]
async fn revoked_devices_cannot_register_again_or_restore_addresses() {
    let harness = start_harness("reregister-revoked", |_| {}).await;
    let key = new_device_key();
    let id = cert::device_id_from_public_key(&key);
    assert_eq!(
        harness.register(VALID_TOKEN, &key, "Mac").await.status(),
        StatusCode::OK
    );
    harness
        .client
        .post(harness.url(&format!("/mesh/v1/devices/{id}/revoke")))
        .bearer_auth(test_token(VALID_TOKEN))
        .json(&json!({"device_id": id}))
        .send()
        .await
        .unwrap();
    let response = harness.register(VALID_TOKEN, &key, "Mac").await;
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    let body: Value = response.json().await.unwrap();
    assert_eq!(body["error"], "device_revoked");
    assert!(body.get("certificate").is_none());
    let report = harness
        .client
        .post(harness.url("/mesh/v1/addresses"))
        .bearer_auth(test_token(VALID_TOKEN))
        .json(&json!({"device_id": id,
            "candidates": [{"kind":"lan", "host":"192.168.1.1", "port":1180}]}))
        .send()
        .await
        .unwrap();
    assert_eq!(report.status(), StatusCode::FORBIDDEN);
    assert!(harness
        .store
        .addresses(&id, nipaplay_auth::unix_timestamp())
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn account_is_verified_and_cross_account_operations_are_rejected() {
    let harness = start_harness("cross-account", |_| {}).await;
    let key = new_device_key();
    let id = cert::device_id_from_public_key(&key);
    let response = harness.client.post(harness.url("/mesh/v1/devices/register"))
        .bearer_auth(test_token(VALID_TOKEN)).json(&json!({"device_public_key":base64url(&key),
            "device_name":"Mac", "platform":"macos", "app_version":"1", "account_id":SECOND_ACCOUNT_ID.to_string(), "proof":possession(&key, vec!["register".into(),base64url(&key),"Mac".into(),"macos".into(),"1".into()])}))
        .send().await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response.json::<Value>().await.unwrap()["account_id"],
        ACCOUNT_ID.to_string()
    );
    assert_eq!(
        harness.register(SECOND_TOKEN, &key, "Other").await.status(),
        StatusCode::FORBIDDEN
    );
    for (path, body) in [
        (
            "/mesh/v1/devices/renew".to_owned(),
            json!({"device_id":id,"device_public_key":base64url(&key)}),
        ),
        (
            format!("/mesh/v1/devices/{id}/revoke"),
            json!({"device_id":id}),
        ),
        (
            "/mesh/v1/addresses".to_owned(),
            json!({"device_id":id,"candidates":[]}),
        ),
    ] {
        let response = harness
            .client
            .post(harness.url(&path))
            .bearer_auth(test_token(SECOND_TOKEN))
            .json(&body)
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::NOT_FOUND, "{path}");
    }
    let response = harness
        .client
        .get(harness.url(&format!("/mesh/v1/addresses?device_id={id}")))
        .bearer_auth(test_token(SECOND_TOKEN))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    assert!(harness
        .store
        .device(&id)
        .unwrap()
        .unwrap()
        .revoked_at
        .is_none());
}

#[tokio::test]
async fn revoke_requires_matching_path_and_body() {
    let harness = start_harness("revoke-path", |_| {}).await;
    let key = new_device_key();
    let id = cert::device_id_from_public_key(&key);
    harness.register(VALID_TOKEN, &key, "Mac").await;
    let response = harness
        .client
        .post(harness.url("/mesh/v1/devices/wrong-device/revoke"))
        .bearer_auth(test_token(VALID_TOKEN))
        .json(&json!({"device_id":id}))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert!(harness
        .store
        .device(&id)
        .unwrap()
        .unwrap()
        .revoked_at
        .is_none());
}

#[tokio::test]
async fn ip_and_token_limits_prevent_upstream_calls_including_rejected_renewals() {
    let harness = start_harness("upstream-ip-limit", |config| {
        config.ip_requests_per_minute = 1
    })
    .await;
    let first = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(test_token("test-invalid-a"))
        .send()
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::UNAUTHORIZED);
    let second = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(test_token("test-invalid-b"))
        .send()
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(harness.validation_calls.load(Ordering::SeqCst), 1);
    assert_eq!(harness.lookup_calls.load(Ordering::SeqCst), 0);
    let harness = start_harness("upstream-token-limit", |config| config.devices_per_hour = 1).await;
    for expected in [StatusCode::UNAUTHORIZED, StatusCode::TOO_MANY_REQUESTS] {
        let response = harness
            .client
            .get(harness.url("/mesh/v1/devices"))
            .bearer_auth(test_token("test-renew-rejected"))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), expected);
    }
    assert_eq!(harness.validation_calls.load(Ordering::SeqCst), 1);
    assert_eq!(harness.lookup_calls.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn malformed_identity_and_upstream_failures_never_issue_certificates_or_leak_details() {
    let harness = start_harness("bad-upstream", |_| {}).await;
    for token in [
        "test-zero-id",
        "test-negative-id",
        "test-string-id",
        "test-missing-id",
        "test-upstream-error",
        "test-malformed-upstream",
    ] {
        let response = harness.register(token, &new_device_key(), "Mac").await;
        assert_eq!(
            response.status(),
            if token == "test-upstream-error" || token == "test-malformed-upstream" {
                StatusCode::SERVICE_UNAVAILABLE
            } else {
                StatusCode::UNPROCESSABLE_ENTITY
            },
            "{token}"
        );
        let body: Value = response.json().await.unwrap();
        assert_eq!(
            body["error"],
            if token == "test-upstream-error" || token == "test-malformed-upstream" {
                "upstream_unavailable"
            } else {
                "invalid_identity"
            }
        );
        let text = body.to_string();
        assert!(!text.contains("test-secret"));
        assert!(!text.contains("127.0.0.1"));
        assert!(!text.contains("userId"));
        assert!(body.get("certificate").is_none());
    }
    assert!(harness
        .store
        .list_devices(&ACCOUNT_ID.to_string())
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn invalid_json_and_oversized_inputs_are_rejected_before_upstream_access() {
    let harness = start_harness("input-body", |_| {}).await;
    for (body, expected) in [
        ("{invalid".to_owned(), StatusCode::BAD_REQUEST),
        ("x".repeat(32 * 1024 + 1), StatusCode::PAYLOAD_TOO_LARGE),
    ] {
        let response = harness
            .client
            .post(harness.url("/mesh/v1/devices/register"))
            .bearer_auth(test_token(VALID_TOKEN))
            .header("content-type", "application/json")
            .body(body)
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), expected);
        let body: Value = response.json().await.unwrap();
        assert_eq!(body["error"], "invalid_input");
        assert_eq!(body["errorCode"], expected.as_u16());
    }
    assert_eq!(harness.validation_calls.load(Ordering::SeqCst), 0);
    let response = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth("x".repeat(4097))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert_eq!(harness.validation_calls.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn invalid_hosts_duplicates_and_sql_text_are_rejected_without_mutation() {
    let harness = start_harness("host-validation", |_| {}).await;
    let key = new_device_key();
    let id = cert::device_id_from_public_key(&key);
    harness.register(VALID_TOKEN, &key, "Mac").await;
    for host in [
        "https://example.com/path",
        "host:1180",
        "a b",
        "'; DROP TABLE devices;--",
        "-invalid.local",
        "a..b",
    ] {
        let response = harness
            .client
            .post(harness.url("/mesh/v1/addresses"))
            .bearer_auth(test_token(VALID_TOKEN))
            .json(&json!({"device_id":id,
                "candidates":[{"kind":"lan","host":host,"port":1180}]}))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST, "{host}");
    }
    let candidate = json!({"kind":"lan","host":"192.168.1.20","port":1180});
    let response = harness
        .client
        .post(harness.url("/mesh/v1/addresses"))
        .bearer_auth(test_token(VALID_TOKEN))
        .json(&json!({"device_id":id, "candidates":[candidate,candidate]}))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert!(harness
        .store
        .addresses(&id, nipaplay_auth::unix_timestamp())
        .unwrap()
        .is_empty());
    assert!(harness.store.device(&id).unwrap().is_some());
}

#[tokio::test]
async fn ttl_and_certificate_configuration_extremes_cannot_panic_or_issue_long_lived_certs() {
    for (label, ttl) in [("zero-ttl", 0), ("overflow-ttl", u64::MAX)] {
        let harness = start_harness(label, |config| {
            config.address_max_ttl_seconds = ttl;
            config.address_default_ttl_seconds = u64::MAX;
            config.cert_validity_seconds = u64::MAX;
        })
        .await;
        let key = new_device_key();
        let id = cert::device_id_from_public_key(&key);
        let response = harness.register(VALID_TOKEN, &key, "Mac").await;
        assert_eq!(response.status(), StatusCode::OK);
        let body: Value = response.json().await.unwrap();
        assert!(
            body["certificate"]["not_after"].as_i64().unwrap()
                <= nipaplay_auth::unix_timestamp() + 7 * 86_400
        );
        let response = harness
            .client
            .post(harness.url("/mesh/v1/addresses"))
            .bearer_auth(test_token(VALID_TOKEN))
            .json(&json!({"device_id":id,
                "candidates":[{"kind":"lan","host":"::1","port":1180,"expires_in":i64::MAX}]}))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let records = harness
            .store
            .addresses(&id, nipaplay_auth::unix_timestamp())
            .unwrap();
        assert_eq!(records.len(), 1);
        assert!(records[0].expires_at - records[0].updated_at <= 7200);
    }
}

#[tokio::test]
async fn database_failure_returns_generic_error_instead_of_a_false_zero_epoch() {
    let harness = start_harness("db-failure", |_| {}).await;
    let connection = rusqlite::Connection::open(harness._dir.0.join("mesh.db")).unwrap();
    connection.execute_batch("DROP TABLE accounts").unwrap();
    let response = harness
        .client
        .get(harness.url("/mesh/v1/devices"))
        .bearer_auth(test_token(VALID_TOKEN))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
    let body: Value = response.json().await.unwrap();
    assert_eq!(body["error"], "internal_error");
    assert!(!body.to_string().contains("accounts"));
    assert!(body.get("revocation_epoch").is_none());
}

#[tokio::test]
async fn account_lookup_never_calls_renew() {
    for (label, post) in [("renew-post", true), ("renew-get", false)] {
        let harness = start_harness_with_methods(label, |_| {}, post).await;
        let response = harness
            .register(VALID_TOKEN, &new_device_key(), "Mac")
            .await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            response.json::<Value>().await.unwrap()["account_id"],
            ACCOUNT_ID.to_string()
        );
        assert_eq!(harness.lookup_calls.load(Ordering::SeqCst), 0);
    }
}

#[tokio::test]
async fn different_tokens_share_the_verified_account_limit() {
    let harness = start_harness("same-account-limit", |config| config.register_per_hour = 1).await;
    assert_eq!(
        harness
            .register(VALID_TOKEN, &new_device_key(), "First")
            .await
            .status(),
        StatusCode::OK
    );
    let response = harness
        .register("test-same-account-token", &new_device_key(), "Second")
        .await;
    assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(
        harness
            .store
            .list_devices(&ACCOUNT_ID.to_string())
            .unwrap()
            .len(),
        1
    );
    assert_eq!(harness.validation_calls.load(Ordering::SeqCst), 2);
    assert_eq!(harness.lookup_calls.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn possession_proof_rejects_missing_forged_replayed_expired_and_modified_requests() {
    let harness = start_harness("proof", |c| c.register_per_hour = 100).await;
    let key = new_device_key();
    let mut body = json!({"device_public_key":base64url(&key), "device_name":"Mac",
        "platform":"macos", "app_version":"1"});
    async fn submit(harness: &Harness, body: &Value) -> StatusCode {
        harness
            .client
            .post(harness.url("/mesh/v1/devices/register"))
            .bearer_auth(test_token(VALID_TOKEN))
            .json(body)
            .send()
            .await
            .unwrap()
            .status()
    }
    assert_eq!(submit(&harness, &body).await, StatusCode::BAD_REQUEST);
    let proof = possession(
        &key,
        vec![
            "register".into(),
            base64url(&key),
            "Mac".into(),
            "macos".into(),
            "1".into(),
        ],
    );
    body["proof"] = proof.clone();
    body["device_name"] = json!("tampered");
    assert_eq!(submit(&harness, &body).await, StatusCode::BAD_REQUEST);
    body["device_name"] = json!("Mac");
    body["proof"]["signature"] = json!(base64url(&[0; 64]));
    assert_eq!(submit(&harness, &body).await, StatusCode::BAD_REQUEST);
    body["proof"] = proof.clone();
    body["proof"]["timestamp"] = json!(nipaplay_auth::unix_timestamp() - 301);
    assert_eq!(submit(&harness, &body).await, StatusCode::BAD_REQUEST);
    body["proof"] = proof;
    assert_eq!(submit(&harness, &body).await, StatusCode::OK);
    assert_eq!(submit(&harness, &body).await, StatusCode::BAD_REQUEST);
    assert_eq!(
        harness
            .store
            .list_devices(&ACCOUNT_ID.to_string())
            .unwrap()
            .len(),
        1
    );
}

#[tokio::test]
async fn jwt_claim_pointer_is_configurable_and_diagnostics_return_only_names_after_validation() {
    let harness = start_harness("claim-pointer", |c| {
        c.account_claim_pointer = "/identity/uid".into()
    })
    .await;
    assert_eq!(
        harness
            .register(VALID_TOKEN, &new_device_key(), "Mac")
            .await
            .status(),
        StatusCode::OK
    );
    let client = DandanplayUpstream::via_gateway_with_client(
        harness.gateway_base.clone(),
        "NipaPlay-Mesh-Test/1.0".to_owned(),
        reqwest::Client::builder().no_proxy().build().unwrap(),
    )
    .unwrap();
    let names = client
        .account_claim_names(&test_token(VALID_TOKEN))
        .await
        .unwrap();
    assert_eq!(
        names,
        vec!["/identity", "/identity/uid", "/test_case", "/userId"]
    );
    assert!(!serde_json::to_string(&names).unwrap().contains("424242"));
    assert_eq!(
        client
            .account_claim_names("forged-token")
            .await
            .unwrap_err(),
        nipaplay_auth::AccountLookupError::InvalidToken
    );
    assert!(matches!(
        client
            .resolve_account(&test_token(VALID_TOKEN), "/missing")
            .await,
        Err(nipaplay_auth::AccountLookupError::InvalidIdentity(_))
    ));
    assert!(matches!(
        client
            .resolve_account("synthetic-upstream-accepted-opaque", "/userId")
            .await,
        Err(nipaplay_auth::AccountLookupError::InvalidIdentity(_))
    ));
    assert_eq!(harness.lookup_calls.load(Ordering::SeqCst), 0);
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
