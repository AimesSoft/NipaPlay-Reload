use std::{
    net::SocketAddr,
    sync::Arc,
    time::{Duration, Instant},
};

use axum::{
    body::{to_bytes, Body},
    extract::{ConnectInfo, Request, State},
    http::{header, HeaderName, HeaderValue, Method, StatusCode},
    response::{IntoResponse, Response},
    routing::{any, get},
    Json, Router,
};
use nipaplay_auth::{
    app_signature, bearer_token, client_ip, env_bool, env_number, env_value, load_app_secret,
    token_identity, unix_timestamp, DandanplayUpstream, RateLimiter, UpstreamConfig,
};
use reqwest::redirect::Policy;
use serde_json::{json, Value};
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing::{error, info, warn};
use tracing_subscriber::EnvFilter;

#[derive(Clone)]
struct AppState {
    config: Arc<Config>,
    client: reqwest::Client,
    limiter: RateLimiter,
    upstream: DandanplayUpstream,
}

struct Config {
    listen: SocketAddr,
    upstream_base: String,
    app_id: String,
    app_secret: String,
    user_agent: String,
    allow_unknown_api_v2: bool,
    max_request_bytes: usize,
    account_requests_per_minute: u32,
    ip_requests_per_minute: u32,
    global_requests_per_minute: u32,
}

impl Config {
    async fn from_env() -> Result<Self, String> {
        let listen = env_value("LISTEN_ADDR", "127.0.0.1:18081")
            .parse()
            .map_err(|error| format!("invalid LISTEN_ADDR: {error}"))?;
        let upstream_base = env_value("DANDANPLAY_UPSTREAM_BASE", "https://api.dandanplay.net")
            .trim_end_matches('/')
            .to_owned();
        let app_id = env_value("DANDANPLAY_APP_ID", "nipaplayv1");
        let user_agent = env_value("DANDANPLAY_USER_AGENT", "NipaPlay/1.0");
        let app_secret = load_app_secret(&user_agent).await?;

        Ok(Self {
            listen,
            upstream_base,
            app_id,
            app_secret,
            user_agent,
            allow_unknown_api_v2: env_bool("ALLOW_UNKNOWN_API_V2", true),
            max_request_bytes: env_number("MAX_REQUEST_BYTES", 8 * 1024 * 1024),
            account_requests_per_minute: env_number("ACCOUNT_REQUESTS_PER_MINUTE", 120),
            ip_requests_per_minute: env_number("IP_REQUESTS_PER_MINUTE", 300),
            global_requests_per_minute: env_number("GLOBAL_REQUESTS_PER_MINUTE", 3000),
        })
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let config = Arc::new(Config::from_env().await.map_err(std::io::Error::other)?);
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(25))
        .redirect(Policy::none())
        .build()?;
    let upstream = DandanplayUpstream::new(UpstreamConfig {
        base_url: config.upstream_base.clone(),
        app_id: config.app_id.clone(),
        app_secret: config.app_secret.clone(),
        user_agent: config.user_agent.clone(),
    })
    .map_err(std::io::Error::other)?;
    let state = AppState {
        config: Arc::clone(&config),
        client,
        limiter: RateLimiter::new(),
        upstream,
    };

    let app = app_router(state);

    let listener = tokio::net::TcpListener::bind(config.listen).await?;
    info!(listen = %config.listen, "NipaPlay Dandanplay gateway started");
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await?;
    Ok(())
}

fn app_router(state: AppState) -> Router {
    Router::new()
        .route("/healthz", get(health))
        .route("/api/v2/{*path}", any(proxy))
        .fallback(not_found)
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

async fn health(State(state): State<AppState>) -> impl IntoResponse {
    Json(json!({
        "ok": true,
        "service": "nipaplay-dandanplay-gateway",
        "appId": state.config.app_id,
        "allowUnknownApiV2": state.config.allow_unknown_api_v2,
        "requireAuthForMatch": true,
        "requireAuthForApi": true
    }))
}

async fn not_found() -> Response {
    json_error(StatusCode::NOT_FOUND, "接口不存在")
}

async fn proxy(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    request: Request,
) -> Response {
    let started_at = Instant::now();
    let (parts, body) = request.into_parts();
    let method = parts.method;
    let uri = parts.uri;
    let headers = parts.headers;
    let path = uri.path().to_owned();
    let known = is_known_endpoint(&method, &path);

    if !known && !state.config.allow_unknown_api_v2 {
        warn!(method = %method, path, "blocked unknown Dandanplay endpoint");
        return json_error(StatusCode::NOT_FOUND, "当前版本未开放该弹弹play接口");
    }
    if !known {
        warn!(method = %method, path, "forwarding unknown Dandanplay endpoint in compatibility mode");
    }

    let authorization = bearer_token(&headers);
    let account_entry = is_account_entry(&method, &path);
    // These browser account-management pages authenticate with the short-lived
    // webToken issued to an already authenticated account. The upstream checks
    // its validity; it is never accepted for any other API endpoint.
    let web_token = account_page_web_token(&path, uri.query());
    if !account_entry && authorization.is_none() && web_token.is_none() {
        return json_error(
            StatusCode::UNAUTHORIZED,
            "请先登录弹弹play账号后再使用弹弹play服务",
        );
    }

    let client_ip = client_ip(&headers, peer);
    let identity = authorization
        .or(web_token.as_deref())
        .map(token_identity)
        .unwrap_or_else(|| "anonymous".to_owned());
    let account_key = format!("account:{identity}");
    let ip_key = format!("ip:{client_ip}");
    let rate_keys = [
        ("global", state.config.global_requests_per_minute),
        (ip_key.as_str(), state.config.ip_requests_per_minute),
        (
            account_key.as_str(),
            if authorization.is_some() || web_token.is_some() {
                state.config.account_requests_per_minute
            } else {
                0
            },
        ),
    ];
    if !state.limiter.check(&rate_keys) {
        warn!(client_ip = %client_ip, identity, method = %method, path, "rate limit exceeded");
        return json_error(StatusCode::TOO_MANY_REQUESTS, "请求过于频繁，请稍后再试");
    }

    // Renewal must reach the upstream with the existing token even when that
    // token needs renewing. It is not an anonymous entry point.
    if !account_entry && web_token.is_none() && path != "/api/v2/login/renew" {
        let token = authorization.expect("API authorization checked above");
        match state.upstream.validate_token(token, &identity).await {
            Ok(true) => {}
            Ok(false) => {
                return json_error(StatusCode::UNAUTHORIZED, "弹弹play登录已失效，请重新登录");
            }
            Err(error) => {
                warn!(client_ip = %client_ip, identity, %error, "failed to validate Dandanplay token");
                return json_error(
                    StatusCode::SERVICE_UNAVAILABLE,
                    "暂时无法验证弹弹play登录状态，请稍后再试",
                );
            }
        }
    }

    let body = match to_bytes(body, state.config.max_request_bytes).await {
        Ok(body) => body,
        Err(_) => return json_error(StatusCode::PAYLOAD_TOO_LARGE, "请求体过大"),
    };
    let timestamp = unix_timestamp();
    let body = match rewrite_account_body(&path, &body, &state.config, timestamp) {
        Ok(body) => body,
        Err(message) => return json_error(StatusCode::BAD_REQUEST, message),
    };

    let path_and_query = uri
        .path_and_query()
        .map(|value| value.as_str())
        .unwrap_or(path.as_str());
    let upstream_url = format!("{}{}", state.config.upstream_base, path_and_query);
    let signature = app_signature(
        &state.config.app_id,
        timestamp,
        &path,
        &state.config.app_secret,
    );

    let mut upstream = state.client.request(method.clone(), upstream_url);
    for name in [header::ACCEPT, header::CONTENT_TYPE, header::AUTHORIZATION] {
        if let Some(value) = headers.get(&name) {
            upstream = upstream.header(name, value);
        }
    }
    upstream = upstream
        .header(header::USER_AGENT, &state.config.user_agent)
        .header("x-appid", &state.config.app_id)
        .header("x-timestamp", timestamp.to_string())
        .header("x-signature", signature)
        .body(body);

    let upstream_response = match upstream.send().await {
        Ok(response) => response,
        Err(error) => {
            error!(method = %method, path, client_ip = %client_ip, %error, "upstream request failed");
            let status = if error.is_timeout() {
                StatusCode::GATEWAY_TIMEOUT
            } else {
                StatusCode::BAD_GATEWAY
            };
            return json_error(status, "弹弹play服务暂时不可用");
        }
    };

    let status = upstream_response.status();
    let upstream_headers = upstream_response.headers().clone();
    let response_body = match upstream_response.bytes().await {
        Ok(bytes) => bytes,
        Err(error) => {
            error!(method = %method, path, %error, "failed to read upstream response");
            return json_error(StatusCode::BAD_GATEWAY, "读取弹弹play响应失败");
        }
    };

    let mut response = Response::builder().status(status);
    for name in [
        header::CONTENT_TYPE,
        header::ETAG,
        header::LAST_MODIFIED,
        header::LOCATION,
        header::ALLOW,
        header::WWW_AUTHENTICATE,
        HeaderName::from_static("x-error-message"),
    ] {
        if let Some(value) = upstream_headers.get(&name) {
            response = response.header(name, value);
        }
    }
    response = response
        .header("x-nipaplay-gateway", "rust")
        .header(header::CACHE_CONTROL, "private, no-store");

    info!(
        method = %method,
        path,
        status = status.as_u16(),
        elapsed_ms = started_at.elapsed().as_millis(),
        client_ip = %client_ip,
        identity,
        known,
        "proxied Dandanplay request"
    );

    response
        .body(Body::from(response_body))
        .unwrap_or_else(|_| json_error(StatusCode::INTERNAL_SERVER_ERROR, "构造响应失败"))
}

fn is_account_entry(method: &Method, path: &str) -> bool {
    method == Method::POST && matches!(path, "/api/v2/login" | "/api/v2/register")
}

fn account_page_web_token(path: &str, query: Option<&str>) -> Option<String> {
    if !matches!(
        path,
        "/api/v2/oauth/deleteAccount" | "/api/v2/oauthprovider/bangumi/manage"
    ) {
        return None;
    }
    let url = reqwest::Url::parse(&format!("http://localhost/?{}", query?)).ok()?;
    url.query_pairs()
        .find(|(key, value)| key == "webToken" && !value.is_empty())
        .map(|(_, value)| value.into_owned())
}

fn is_known_endpoint(method: &Method, path: &str) -> bool {
    let tail = match path.strip_prefix("/api/v2/") {
        Some(value) if !value.is_empty() => value,
        _ => return false,
    };

    match tail {
        "login" | "register" => method == Method::POST,
        "login/renew" => method == Method::GET || method == Method::POST,
        "match" => method == Method::POST,
        "bangumi/recent" | "bangumi/shin" => method == Method::GET,
        "search/anime" | "search/episodes" | "search/adv" | "search/adv/config" | "search/tag" => {
            method == Method::GET
        }
        "favorite" => method == Method::GET || method == Method::POST,
        "playhistory" => method == Method::GET || method == Method::POST,
        "oauth/webToken" | "oauthprovider/bangumi/login" => method == Method::GET,
        _ if tail.starts_with("comment/") => method == Method::GET || method == Method::POST,
        _ if tail.starts_with("bangumi/bgmtv/") => method == Method::GET,
        _ if tail.starts_with("bangumi/") && tail.ends_with("/comments") => method == Method::GET,
        _ if tail.starts_with("bangumi/") => method == Method::GET,
        _ if tail.starts_with("favorite/") => method == Method::DELETE,
        _ if tail.starts_with("trending/") => method == Method::GET,
        _ => false,
    }
}

fn rewrite_account_body(
    path: &str,
    body: &[u8],
    config: &Config,
    timestamp: i64,
) -> Result<Vec<u8>, &'static str> {
    if path != "/api/v2/login" && path != "/api/v2/register" {
        return Ok(body.to_vec());
    }

    let mut value: Value =
        serde_json::from_slice(body).map_err(|_| "登录或注册请求不是有效 JSON")?;
    let object = value.as_object_mut().ok_or("登录或注册请求格式错误")?;
    let user_name = string_field(object, "userName")?;
    let password = string_field(object, "password")?;

    let hash_input = if path == "/api/v2/login" {
        format!(
            "{}{}{}{}{}",
            config.app_id, password, timestamp, user_name, config.app_secret
        )
    } else {
        let email = string_field(object, "email")?;
        let screen_name = string_field(object, "screenName")?;
        format!(
            "{}{}{}{}{}{}{}",
            config.app_id, email, password, screen_name, timestamp, user_name, config.app_secret
        )
    };

    object.insert("appId".to_owned(), Value::String(config.app_id.clone()));
    object.insert("unixTimestamp".to_owned(), Value::Number(timestamp.into()));
    object.insert(
        "hash".to_owned(),
        Value::String(format!("{:x}", md5::compute(hash_input.as_bytes()))),
    );
    serde_json::to_vec(&value).map_err(|_| "无法编码登录或注册请求")
}

fn string_field<'a>(
    object: &'a serde_json::Map<String, Value>,
    name: &str,
) -> Result<&'a str, &'static str> {
    object
        .get(name)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or("登录或注册请求缺少必要字段")
}

fn json_error(status: StatusCode, message: impl Into<String>) -> Response {
    let message = message.into();
    let mut response = Json(json!({
        "success": false,
        "errorCode": status.as_u16(),
        "errorMessage": message
    }))
    .into_response();
    *response.status_mut() = status;
    response
        .headers_mut()
        .insert("x-nipaplay-gateway", HeaderValue::from_static("rust"));
    response
}

async fn shutdown_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };

    #[cfg(unix)]
    let terminate = async {
        if let Ok(mut signal) =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        {
            signal.recv().await;
        }
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{http::HeaderMap, routing::post};

    fn config(secret: &str) -> Config {
        Config {
            listen: "127.0.0.1:18081".parse().unwrap(),
            upstream_base: "https://api.dandanplay.net".to_owned(),
            app_id: "nipaplayv1".to_owned(),
            app_secret: secret.to_owned(),
            user_agent: "NipaPlay/1.0".to_owned(),
            allow_unknown_api_v2: true,
            max_request_bytes: 1024,
            account_requests_per_minute: 120,
            ip_requests_per_minute: 300,
            global_requests_per_minute: 3000,
        }
    }

    #[test]
    fn current_client_routes_are_known() {
        let routes = [
            (Method::POST, "/api/v2/login"),
            (Method::POST, "/api/v2/register"),
            (Method::GET, "/api/v2/login/renew"),
            (Method::POST, "/api/v2/match"),
            (Method::GET, "/api/v2/comment/123"),
            (Method::POST, "/api/v2/comment/123"),
            (Method::GET, "/api/v2/bangumi/42"),
            (Method::GET, "/api/v2/bangumi/bgmtv/42"),
            (Method::GET, "/api/v2/bangumi/42/comments"),
            (Method::GET, "/api/v2/search/anime"),
            (Method::GET, "/api/v2/search/episodes"),
            (Method::GET, "/api/v2/search/adv/config"),
            (Method::GET, "/api/v2/search/tag"),
            (Method::GET, "/api/v2/favorite"),
            (Method::POST, "/api/v2/favorite"),
            (Method::DELETE, "/api/v2/favorite/42"),
            (Method::GET, "/api/v2/playhistory"),
            (Method::POST, "/api/v2/playhistory"),
            (Method::GET, "/api/v2/oauth/webToken"),
            (Method::GET, "/api/v2/oauthprovider/bangumi/login"),
            (Method::GET, "/api/v2/trending/all/hot/week"),
        ];

        for (method, path) in routes {
            assert!(is_known_endpoint(&method, path), "missing {method} {path}");
        }
    }

    #[test]
    fn rewrites_login_hash_with_server_secret() {
        let config = config("secret");
        let body = br#"{"userName":"alice","password":"pw","hash":"client-value"}"#;
        let rewritten = rewrite_account_body("/api/v2/login", body, &config, 123).unwrap();
        let value: Value = serde_json::from_slice(&rewritten).unwrap();
        let expected = format!("{:x}", md5::compute(b"nipaplayv1pw123alicesecret"));
        assert_eq!(value["hash"], expected);
        assert_eq!(value["unixTimestamp"], 123);
        assert_eq!(value["appId"], "nipaplayv1");
    }

    #[test]
    fn leaves_non_account_bodies_untouched() {
        let config = config("secret");
        let body = br#"{"fileName":"episode.mkv"}"#;
        assert_eq!(
            rewrite_account_body("/api/v2/match", body, &config, 123).unwrap(),
            body
        );
    }

    #[test]
    fn parses_bearer_scheme_case_insensitively() {
        let mut headers = HeaderMap::new();
        headers.insert(
            header::AUTHORIZATION,
            HeaderValue::from_static("bearer account-token"),
        );
        assert_eq!(bearer_token(&headers), Some("account-token"));
    }

    #[test]
    fn forwarded_ip_falls_back_to_forwarded_for() {
        let mut headers = HeaderMap::new();
        headers.insert(
            "x-forwarded-for",
            HeaderValue::from_static("203.0.113.9, 127.0.0.1"),
        );
        assert_eq!(
            nipaplay_auth::forwarded_ip(&headers),
            Some("203.0.113.9".parse().unwrap())
        );
    }

    #[tokio::test]
    async fn all_apis_require_a_valid_account_token() {
        async fn validation(headers: HeaderMap) -> Json<Value> {
            if headers.get(header::AUTHORIZATION)
                == Some(&HeaderValue::from_static("Bearer valid-token"))
            {
                Json(json!({"success":true}))
            } else {
                // Some upstream failures return HTTP 200 with success:false.
                Json(json!({"success":false}))
            }
        }

        async fn matched() -> Json<Value> {
            Json(json!({"success": true, "isMatched": false, "matches": []}))
        }

        let upstream = Router::new()
            .route("/api/v2/playhistory", get(validation))
            .route("/api/v2/match", post(matched))
            .fallback(any(matched));
        let upstream_listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let upstream_addr = upstream_listener.local_addr().unwrap();
        let upstream_task = tokio::spawn(async move {
            axum::serve(upstream_listener, upstream).await.unwrap();
        });

        let mut config = config("secret");
        config.upstream_base = format!("http://{upstream_addr}");
        let upstream = DandanplayUpstream::new(UpstreamConfig {
            base_url: config.upstream_base.clone(),
            app_id: config.app_id.clone(),
            app_secret: config.app_secret.clone(),
            user_agent: config.user_agent.clone(),
        })
        .unwrap();
        let state = AppState {
            config: Arc::new(config),
            client: reqwest::Client::new(),
            limiter: RateLimiter::new(),
            upstream,
        };
        let gateway_listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let gateway_addr = gateway_listener.local_addr().unwrap();
        let gateway_task = tokio::spawn(async move {
            axum::serve(
                gateway_listener,
                app_router(state).into_make_service_with_connect_info::<SocketAddr>(),
            )
            .await
            .unwrap();
        });

        let client = reqwest::Client::new();
        let url = format!("http://{gateway_addr}/api/v2/match");
        let anonymous = client.post(&url).json(&json!({})).send().await.unwrap();
        assert_eq!(anonymous.status(), StatusCode::UNAUTHORIZED);

        let trailing_slash = client
            .post(format!("{url}/"))
            .json(&json!({}))
            .send()
            .await
            .unwrap();
        assert_eq!(trailing_slash.status(), StatusCode::UNAUTHORIZED);

        let invalid = client
            .post(&url)
            .bearer_auth("invalid-token")
            .json(&json!({}))
            .send()
            .await
            .unwrap();
        assert_eq!(invalid.status(), StatusCode::UNAUTHORIZED);

        let valid = client
            .post(&url)
            .bearer_auth("valid-token")
            .json(&json!({}))
            .send()
            .await
            .unwrap();
        assert_eq!(valid.status(), StatusCode::OK);

        for path in [
            "/api/v2/comment/123",
            "/api/v2/bangumi/shin",
            "/api/v2/bangumi/42",
            "/api/v2/bangumi/42/comments",
            "/api/v2/search/anime",
            "/api/v2/search/adv/config",
            "/api/v2/trending/all/hot/week",
            "/api/v2/unknown/future",
        ] {
            let url = format!("http://{gateway_addr}{path}");
            for method in [Method::GET, Method::POST, Method::HEAD, Method::DELETE] {
                let response = client.request(method.clone(), &url).send().await.unwrap();
                assert_eq!(
                    response.status(),
                    StatusCode::UNAUTHORIZED,
                    "anonymous {method} {path}"
                );
                let response = client
                    .request(method.clone(), &url)
                    .bearer_auth("invalid-token")
                    .send()
                    .await
                    .unwrap();
                assert_eq!(
                    response.status(),
                    StatusCode::UNAUTHORIZED,
                    "invalid {method} {path}"
                );
            }
            let response = client
                .get(&url)
                .bearer_auth("valid-token")
                .send()
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::OK, "valid {path}");
            assert_eq!(
                response.headers()[header::CACHE_CONTROL],
                "private, no-store"
            );
            let response = client
                .get(format!("{url}?webToken=valid-token"))
                .send()
                .await
                .unwrap();
            assert_eq!(
                response.status(),
                StatusCode::UNAUTHORIZED,
                "webToken must not unlock {path}"
            );
        }

        for path in ["/api/v2/login", "/api/v2/register"] {
            let url = format!("http://{gateway_addr}{path}");
            let response = client.post(&url).json(&json!({
                "userName":"test", "password":"test", "email":"test@example.com", "screenName":"test"
            })).send().await.unwrap();
            assert_eq!(response.status(), StatusCode::OK, "account entry {path}");
            assert_eq!(
                client.get(&url).send().await.unwrap().status(),
                StatusCode::UNAUTHORIZED
            );
        }
        let renew = format!("http://{gateway_addr}/api/v2/login/renew");
        assert_eq!(
            client.post(&renew).send().await.unwrap().status(),
            StatusCode::UNAUTHORIZED
        );
        assert_eq!(
            client
                .post(&renew)
                .bearer_auth("renewable-token")
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::OK
        );

        gateway_task.abort();
        upstream_task.abort();
    }
}
