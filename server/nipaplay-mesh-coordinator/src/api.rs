//! Mesh control-plane HTTP API.
//!
//! See `README.md` for the full contract. Only control-plane operations live
//! here: device registration and renewal, device listing, address candidates,
//! and revocation. No media or task traffic is proxied.

use std::{net::SocketAddr, sync::Arc, time::Duration};

use axum::{
    extract::rejection::{JsonRejection, QueryRejection},
    extract::{ConnectInfo, DefaultBodyLimit, Path, Query, Request, State},
    http::HeaderMap,
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use nipaplay_auth::{bearer_token, RateLimiter};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use time::Duration as TimeDuration;
use tower_http::trace::TraceLayer;
use tracing::{info, warn};

use crate::{
    account::AccountResolver,
    cert::{self, CertificateAuthority},
    config::Config,
    error::{ApiError, ErrorCode},
    store::{AddressRecord, DeviceRecord, DeviceUpsert, Store},
};

const MAX_ADDRESS_CANDIDATES: usize = 32;
const MAX_NAME_LEN: usize = 128;
const MAX_PLATFORM_LEN: usize = 32;
const MAX_APP_VERSION_LEN: usize = 32;
const MAX_HOST_LEN: usize = 255;
const ALLOWED_ADDRESS_KINDS: [&str; 5] = ["lan", "public", "overlay", "relay", "manual"];

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<Config>,
    pub store: Store,
    pub ca: Arc<CertificateAuthority>,
    pub accounts: AccountResolver,
    pub limiter: RateLimiter,
}

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/healthz", get(health))
        .route("/mesh/v1/server-info", get(server_info))
        .route("/mesh/v1/devices/register", post(register))
        .route("/mesh/v1/devices/renew", post(renew))
        .route("/mesh/v1/devices", get(list_devices))
        .route("/mesh/v1/devices/{device_id}/revoke", post(revoke))
        .route(
            "/mesh/v1/addresses",
            post(report_addresses).get(get_addresses),
        )
        .fallback(not_found)
        .layer(DefaultBodyLimit::max(32 * 1024))
        .layer(middleware::from_fn_with_state(state.clone(), admission))
        .layer(TraceLayer::new_for_http().make_span_with(|request: &Request| {
            tracing::info_span!("http", method = %request.method(), path = request.uri().path())
        }))
        .with_state(state)
}

async fn health() -> impl IntoResponse {
    Json(json!({ "ok": true, "service": "nipaplay-mesh-coordinator" }))
}

/// Advertises the issuer; clients verify it against their built-in trust root.
async fn server_info(State(state): State<AppState>) -> impl IntoResponse {
    // Unauthenticated: the account-scoped revocation epoch is only returned by
    // the authenticated endpoints.
    Json(json!({
        "success": true,
        "serverPublicKey": state.ca.public_key_base64url(),
        "serverCertificate": state.ca.certificate_pem(),
        "heartbeatIntervalSeconds": state.config.heartbeat_interval_seconds,
        "certificateValiditySeconds": effective_certificate_validity(&state.config),
        "addressMaxTtlSeconds": effective_address_max_ttl(&state.config),
    }))
    .into_response()
}

#[derive(Deserialize)]
struct RegisterRequest {
    device_public_key: String,
    device_name: String,
    platform: String,
    app_version: String,
}

#[derive(Serialize)]
struct CertificatePayload {
    pem: String,
    not_before: i64,
    not_after: i64,
}

#[derive(Serialize)]
struct RegisterResponse {
    success: bool,
    account_id: String,
    device_id: String,
    certificate: CertificatePayload,
    server_public_key: String,
    revocation_epoch: i64,
    heartbeat_interval_seconds: u64,
}

async fn register(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    body: Result<Json<RegisterRequest>, JsonRejection>,
) -> Response {
    let body = match input_json(body) {
        Ok(body) => body,
        Err(error) => return error.into_response(),
    };
    let auth = match authenticate(&state, &headers, peer, RateKind::Register).await {
        Ok(auth) => auth,
        Err(error) => return error.into_response(),
    };

    let public_key = match cert::decode_device_public_key(&body.device_public_key) {
        Ok(key) => key,
        Err(message) => return ApiError::new(ErrorCode::InvalidInput, message).into_response(),
    };
    if let Err(message) = validate_device_metadata(&body) {
        return ApiError::new(ErrorCode::InvalidInput, message).into_response();
    }
    let device_id = cert::device_id_from_public_key(&public_key);

    // A device id is derived from the public key, so a mismatched key under an
    // existing id can only be a client bug; surface it instead of silently
    // replacing the stored key.
    match state.store.device(&device_id) {
        Ok(Some(existing)) if existing.account_id != auth.account_id => {
            return ApiError::new(ErrorCode::DeviceConflict, "该设备已属于其他账号")
                .into_response();
        }
        Ok(Some(existing)) if existing.revoked_at.is_some() => {
            return ApiError::new(ErrorCode::DeviceRevoked, "设备已被吊销").into_response();
        }
        Ok(_) => {}
        Err(error) => {
            return ApiError::internal(format!("读取设备失败：{error}")).into_response();
        }
    }

    let now = nipaplay_auth::unix_timestamp();
    let validity = TimeDuration::seconds(effective_certificate_validity(&state.config));
    let issued =
        match state
            .ca
            .issue_device_certificate(&auth.account_id, &device_id, &public_key, validity)
        {
            Ok(issued) => issued,
            Err(error) => return ApiError::internal(error).into_response(),
        };

    if let Err(error) = state.store.upsert_device(DeviceUpsert {
        account_id: &auth.account_id,
        device_id: &device_id,
        public_key: &public_key,
        name: body.device_name.trim(),
        platform: body.platform.trim(),
        app_version: body.app_version.trim(),
        now,
        cert_expires_at: issued.not_after,
    }) {
        return error.into_response();
    }

    info!(account_id = %auth.account_id, device_id = %device_id, "registered mesh device");
    let revocation_epoch = match state.store.revocation_epoch(&auth.account_id) {
        Ok(epoch) => epoch,
        Err(error) => return ApiError::internal(error).into_response(),
    };
    Json(RegisterResponse {
        success: true,
        account_id: auth.account_id,
        device_id,
        certificate: CertificatePayload {
            pem: issued.pem,
            not_before: issued.not_before,
            not_after: issued.not_after,
        },
        server_public_key: state.ca.public_key_base64url(),
        revocation_epoch,
        heartbeat_interval_seconds: state.config.heartbeat_interval_seconds,
    })
    .into_response()
}

#[derive(Deserialize)]
struct RenewRequest {
    device_id: String,
    device_public_key: String,
}

async fn renew(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    body: Result<Json<RenewRequest>, JsonRejection>,
) -> Response {
    let body = match input_json(body) {
        Ok(body) => body,
        Err(error) => return error.into_response(),
    };
    let auth = match authenticate(&state, &headers, peer, RateKind::Renew).await {
        Ok(auth) => auth,
        Err(error) => return error.into_response(),
    };

    let public_key = match cert::decode_device_public_key(&body.device_public_key) {
        Ok(key) => key,
        Err(message) => return ApiError::new(ErrorCode::InvalidInput, message).into_response(),
    };
    let device_id = match normalize_device_id(&body.device_id) {
        Ok(device_id) => device_id,
        Err(message) => return ApiError::new(ErrorCode::InvalidInput, message).into_response(),
    };
    if cert::device_id_from_public_key(&public_key) != device_id {
        return ApiError::new(ErrorCode::InvalidInput, "device_id 与公钥不匹配").into_response();
    }

    let device = match state.store.device(&device_id) {
        Ok(Some(device)) => device,
        Ok(None) => return ApiError::new(ErrorCode::DeviceNotFound, "设备未注册").into_response(),
        Err(error) => {
            return ApiError::internal(format!("读取设备失败：{error}")).into_response();
        }
    };
    if device.account_id != auth.account_id {
        return ApiError::new(ErrorCode::DeviceNotFound, "设备未注册").into_response();
    }
    if device.revoked_at.is_some() {
        return ApiError::new(ErrorCode::DeviceRevoked, "设备已被吊销").into_response();
    }
    if device.public_key != public_key {
        return ApiError::new(ErrorCode::InvalidInput, "device_public_key 与注册时不一致")
            .into_response();
    }

    let now = nipaplay_auth::unix_timestamp();
    let validity = TimeDuration::seconds(effective_certificate_validity(&state.config));
    let issued =
        match state
            .ca
            .issue_device_certificate(&auth.account_id, &device_id, &public_key, validity)
        {
            Ok(issued) => issued,
            Err(error) => return ApiError::internal(error).into_response(),
        };

    if let Err(error) =
        state
            .store
            .record_renewal(&auth.account_id, &device_id, now, issued.not_after)
    {
        return error.into_response();
    }

    let epoch = match state.store.revocation_epoch(&auth.account_id) {
        Ok(epoch) => epoch,
        Err(error) => return ApiError::internal(error).into_response(),
    };
    Json(json!({
        "success": true,
        "account_id": auth.account_id,
        "device_id": device_id,
        "certificate": {
            "pem": issued.pem,
            "not_before": issued.not_before,
            "not_after": issued.not_after,
        },
        "revocation_epoch": epoch,
    }))
    .into_response()
}

#[derive(Serialize)]
struct DeviceView {
    device_id: String,
    device_name: String,
    platform: String,
    created_at: i64,
    last_seen_at: i64,
    revoked: bool,
}

async fn list_devices(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
) -> Response {
    let auth = match authenticate(&state, &headers, peer, RateKind::Devices).await {
        Ok(auth) => auth,
        Err(error) => return error.into_response(),
    };

    let (devices, epoch) = match state.store.device_snapshot(&auth.account_id) {
        Ok(snapshot) => snapshot,
        Err(error) => {
            return error.into_response();
        }
    };
    let devices: Vec<DeviceView> = devices.into_iter().map(device_view).collect();
    Json(json!({
        "success": true,
        "account_id": auth.account_id,
        "devices": devices,
        "revocation_epoch": epoch,
    }))
    .into_response()
}

fn device_view(device: DeviceRecord) -> DeviceView {
    DeviceView {
        device_id: device.device_id,
        device_name: device.name,
        platform: device.platform,
        created_at: device.created_at,
        last_seen_at: device.last_seen_at,
        revoked: device.revoked_at.is_some(),
    }
}

#[derive(Deserialize)]
struct RevokeRequest {
    device_id: String,
}

async fn revoke(
    State(state): State<AppState>,
    Path(path_device_id): Path<String>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    body: Result<Json<RevokeRequest>, JsonRejection>,
) -> Response {
    let body = match input_json(body) {
        Ok(body) => body,
        Err(error) => return error.into_response(),
    };
    let auth = match authenticate(&state, &headers, peer, RateKind::Devices).await {
        Ok(auth) => auth,
        Err(error) => return error.into_response(),
    };

    let device_id = match normalize_device_id(&body.device_id) {
        Ok(device_id) => device_id,
        Err(message) => return ApiError::new(ErrorCode::InvalidInput, message).into_response(),
    };
    if path_device_id != device_id {
        return ApiError::new(ErrorCode::InvalidInput, "路径与请求体的 device_id 不一致")
            .into_response();
    }
    let device = match state.store.device(&device_id) {
        Ok(Some(device)) => device,
        Ok(None) => return ApiError::new(ErrorCode::DeviceNotFound, "设备未注册").into_response(),
        Err(error) => {
            return ApiError::internal(format!("读取设备失败：{error}")).into_response();
        }
    };
    if device.account_id != auth.account_id {
        return ApiError::new(ErrorCode::DeviceNotFound, "设备未注册").into_response();
    }

    let now = nipaplay_auth::unix_timestamp();
    let epoch = match state.store.revoke_device(&auth.account_id, &device_id, now) {
        Ok(epoch) => epoch,
        Err(error) => {
            return error.into_response();
        }
    };
    info!(account_id = %auth.account_id, device_id = %device_id, "revoked mesh device");
    Json(json!({ "success": true, "revocation_epoch": epoch })).into_response()
}

#[derive(Deserialize)]
struct AddressCandidate {
    kind: String,
    host: String,
    port: u16,
    #[serde(default)]
    priority: Option<i64>,
    #[serde(default)]
    expires_in: Option<i64>,
}

#[derive(Deserialize)]
struct ReportAddressesRequest {
    device_id: String,
    candidates: Vec<AddressCandidate>,
}

async fn report_addresses(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    body: Result<Json<ReportAddressesRequest>, JsonRejection>,
) -> Response {
    let body = match input_json(body) {
        Ok(body) => body,
        Err(error) => return error.into_response(),
    };
    let auth = match authenticate(&state, &headers, peer, RateKind::Addresses).await {
        Ok(auth) => auth,
        Err(error) => return error.into_response(),
    };

    if body.candidates.len() > MAX_ADDRESS_CANDIDATES {
        return ApiError::new(
            ErrorCode::InvalidInput,
            format!("地址候选最多 {MAX_ADDRESS_CANDIDATES} 条"),
        )
        .into_response();
    }
    let device_id = match normalize_device_id(&body.device_id) {
        Ok(device_id) => device_id,
        Err(message) => return ApiError::new(ErrorCode::InvalidInput, message).into_response(),
    };
    let device = match state.store.device(&device_id) {
        Ok(Some(device)) => device,
        Ok(None) => return ApiError::new(ErrorCode::DeviceNotFound, "设备未注册").into_response(),
        Err(error) => {
            return ApiError::internal(format!("读取设备失败：{error}")).into_response();
        }
    };
    if device.account_id != auth.account_id {
        return ApiError::new(ErrorCode::DeviceNotFound, "设备未注册").into_response();
    }
    if device.revoked_at.is_some() {
        return ApiError::new(ErrorCode::DeviceRevoked, "设备已被吊销").into_response();
    }

    let now = nipaplay_auth::unix_timestamp();
    let max_ttl = effective_address_max_ttl(&state.config);
    let default_ttl = state
        .config
        .address_default_ttl_seconds
        .clamp(60, max_ttl as u64) as i64;
    let mut records = Vec::with_capacity(body.candidates.len());
    for candidate in &body.candidates {
        let kind = candidate.kind.trim();
        if !ALLOWED_ADDRESS_KINDS.contains(&kind) {
            return ApiError::new(
                ErrorCode::InvalidInput,
                format!("未知的地址类型：{}", candidate.kind),
            )
            .into_response();
        }
        let host = candidate.host.trim();
        if !valid_host(host) {
            return ApiError::new(ErrorCode::InvalidInput, "地址主机名不合法").into_response();
        }
        if candidate.port == 0 {
            return ApiError::new(ErrorCode::InvalidInput, "地址端口不合法").into_response();
        }
        let ttl = candidate
            .expires_in
            .map(|ttl| ttl.clamp(60, max_ttl))
            .unwrap_or(default_ttl);
        records.push(AddressRecord {
            kind: kind.to_owned(),
            host: host.to_owned(),
            port: candidate.port,
            priority: candidate.priority.unwrap_or(0),
            expires_at: now + ttl,
            updated_at: now,
        });
    }
    let mut unique = std::collections::HashSet::new();
    if records
        .iter()
        .any(|record| !unique.insert((&record.kind, &record.host, record.port)))
    {
        return ApiError::new(ErrorCode::InvalidInput, "地址候选重复").into_response();
    }

    if let Err(error) = state
        .store
        .replace_addresses(&auth.account_id, &device_id, &records, now)
    {
        return error.into_response();
    }
    Json(json!({ "success": true, "accepted": records.len() })).into_response()
}

#[derive(Deserialize)]
struct AddressQuery {
    device_id: String,
}

async fn get_addresses(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    query: Result<Query<AddressQuery>, QueryRejection>,
) -> Response {
    let query = match query {
        Ok(Query(query)) => query,
        Err(_) => return ApiError::new(ErrorCode::InvalidInput, "查询参数不合法").into_response(),
    };
    let auth = match authenticate(&state, &headers, peer, RateKind::Addresses).await {
        Ok(auth) => auth,
        Err(error) => return error.into_response(),
    };

    let device_id = match normalize_device_id(&query.device_id) {
        Ok(device_id) => device_id,
        Err(message) => return ApiError::new(ErrorCode::InvalidInput, message).into_response(),
    };
    let device = match state.store.device(&device_id) {
        Ok(Some(device)) => device,
        Ok(None) => return ApiError::new(ErrorCode::DeviceNotFound, "设备未注册").into_response(),
        Err(error) => {
            return ApiError::internal(format!("读取设备失败：{error}")).into_response();
        }
    };
    if device.account_id != auth.account_id {
        return ApiError::new(ErrorCode::DeviceNotFound, "设备未注册").into_response();
    }
    if device.revoked_at.is_some() {
        return ApiError::new(ErrorCode::DeviceRevoked, "设备已被吊销").into_response();
    }

    let now = nipaplay_auth::unix_timestamp();
    let addresses = match state
        .store
        .address_snapshot(&auth.account_id, &device_id, now)
    {
        Ok(addresses) => addresses,
        Err(error) => {
            return error.into_response();
        }
    };
    let candidates: Vec<_> = addresses
        .into_iter()
        .map(|address| {
            json!({
                "kind": address.kind,
                "host": address.host,
                "port": address.port,
                "priority": address.priority,
                "expires_at": address.expires_at,
                "updated_at": address.updated_at,
            })
        })
        .collect();
    Json(json!({ "success": true, "device_id": device_id, "candidates": candidates }))
        .into_response()
}

async fn not_found() -> Response {
    (
        axum::http::StatusCode::NOT_FOUND,
        Json(json!({
            "success": false,
            "error": "not_found",
            "errorCode": 404,
            "errorMessage": "接口不存在",
        })),
    )
        .into_response()
}

#[derive(Clone, Copy)]
enum RateKind {
    Register,
    Renew,
    Devices,
    Addresses,
}

impl RateKind {
    fn account_limit(self, config: &Config) -> u32 {
        match self {
            RateKind::Register => config.register_per_hour,
            RateKind::Renew => config.renew_per_hour,
            RateKind::Devices => config.devices_per_hour,
            RateKind::Addresses => config.addresses_per_hour,
        }
    }
}

struct Authenticated {
    account_id: String,
}

fn input_json<T>(body: Result<Json<T>, JsonRejection>) -> Result<T, ApiError> {
    body.map(|Json(body)| body).map_err(|error| {
        let code = if error.status() == axum::http::StatusCode::PAYLOAD_TOO_LARGE {
            ErrorCode::InputTooLarge
        } else {
            ErrorCode::InvalidInput
        };
        ApiError::new(code, "请求体不是有效的接口 JSON")
    })
}

async fn authenticate(
    state: &AppState,
    headers: &HeaderMap,
    _peer: SocketAddr,
    kind: RateKind,
) -> Result<Authenticated, ApiError> {
    let token = bearer_token(headers)
        .ok_or_else(|| ApiError::new(ErrorCode::MissingToken, "缺少 Authorization: Bearer 令牌"))?;
    if token.len() > 4096
        || token
            .bytes()
            .any(|byte| byte.is_ascii_whitespace() || byte.is_ascii_control())
    {
        return Err(ApiError::new(ErrorCode::InvalidInput, "令牌格式不合法"));
    }
    let identity = format!("{:x}", Sha256::digest(token.as_bytes()));
    let token_key = format!("token:{identity}:{}", rate_kind_name(kind));
    if !state.limiter.check_window(
        Duration::from_secs(3600),
        &[(&token_key, kind.account_limit(&state.config))],
    ) {
        return Err(ApiError::new(
            ErrorCode::RateLimited,
            "请求过于频繁，请稍后再试",
        ));
    }

    let known = state.accounts.known_account(&identity);
    if let Some(account_id) = &known {
        check_account_rate(state, account_id, kind)?;
    }
    let account_id = state.accounts.resolve(token, &identity).await?;
    if known.is_none() {
        check_account_rate(state, &account_id, kind)?;
    }
    Ok(Authenticated { account_id })
}

fn check_account_rate(state: &AppState, account_id: &str, kind: RateKind) -> Result<(), ApiError> {
    let account_key = format!("account:{account_id}:{}", rate_kind_name(kind));
    if !state.limiter.check_window(
        Duration::from_secs(3600),
        &[(&account_key, kind.account_limit(&state.config))],
    ) {
        warn!(account_id = %account_id, "mesh rate limit exceeded (account)");
        return Err(ApiError::new(
            ErrorCode::RateLimited,
            "请求过于频繁，请稍后再试",
        ));
    }
    Ok(())
}

async fn admission(State(state): State<AppState>, request: Request, next: Next) -> Response {
    let Some(ConnectInfo(peer)) = request.extensions().get::<ConnectInfo<SocketAddr>>() else {
        return ApiError::internal("缺少连接信息").into_response();
    };
    let headers = request.headers();
    let client_ip = if state.config.trust_proxy_headers && peer.ip().is_loopback() {
        nipaplay_auth::client_ip(headers, *peer)
    } else {
        peer.ip()
    };

    // The per-IP bucket applies before any upstream call so a hostile client
    // cannot amplify traffic through the coordinator.
    let ip_key = format!("ip:{client_ip}");
    if !state.limiter.check_window(
        Duration::from_secs(60),
        &[(&ip_key, state.config.ip_requests_per_minute)],
    ) {
        warn!(client_ip = %client_ip, "mesh rate limit exceeded (ip)");
        return ApiError::new(ErrorCode::RateLimited, "请求过于频繁，请稍后再试").into_response();
    }

    next.run(request).await
}

fn rate_kind_name(kind: RateKind) -> &'static str {
    match kind {
        RateKind::Register => "register",
        RateKind::Renew => "renew",
        RateKind::Devices => "devices",
        RateKind::Addresses => "addresses",
    }
}

/// Address candidates are low-frequency hints; the server never stores them
/// longer than the hard cap, regardless of configuration.
fn effective_address_max_ttl(config: &Config) -> i64 {
    config
        .address_max_ttl_seconds
        .clamp(60, crate::config::MAX_ADDRESS_TTL_SECONDS) as i64
}

fn effective_certificate_validity(config: &Config) -> i64 {
    config.cert_validity_seconds.clamp(900, 7 * 86_400) as i64
}

fn valid_host(host: &str) -> bool {
    if host.is_empty() || host.len() > MAX_HOST_LEN {
        return false;
    }
    if host.parse::<std::net::IpAddr>().is_ok() {
        return true;
    }
    host.strip_suffix('.')
        .unwrap_or(host)
        .split('.')
        .all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
        })
}

fn validate_device_metadata(body: &RegisterRequest) -> Result<(), String> {
    let name = body.device_name.trim();
    if name.is_empty() || name.chars().count() > MAX_NAME_LEN || name.chars().any(char::is_control)
    {
        return Err(format!("device_name 长度需在 1..{MAX_NAME_LEN} 之间"));
    }
    let platform = body.platform.trim();
    if platform.is_empty()
        || platform.len() > MAX_PLATFORM_LEN
        || platform.chars().any(char::is_control)
    {
        return Err(format!("platform 长度需在 1..{MAX_PLATFORM_LEN} 之间"));
    }
    let app_version = body.app_version.trim();
    if app_version.is_empty()
        || app_version.len() > MAX_APP_VERSION_LEN
        || app_version.chars().any(char::is_control)
    {
        return Err(format!(
            "app_version 长度需在 1..{MAX_APP_VERSION_LEN} 之间"
        ));
    }
    Ok(())
}

fn normalize_device_id(raw: &str) -> Result<String, String> {
    let value = raw.trim();
    if value.len() != 43 {
        return Err("device_id 不合法".to_owned());
    }
    if !value
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
    {
        return Err("device_id 不合法".to_owned());
    }
    Ok(value.to_owned())
}
