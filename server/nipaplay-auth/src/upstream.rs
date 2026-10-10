use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use reqwest::redirect::Policy;
use serde_json::Value;

use crate::{app_signature, unix_timestamp};

/// Upstream Dandanplay connection settings shared by every server binary.
#[derive(Clone)]
pub struct UpstreamConfig {
    pub base_url: String,
    pub app_id: String,
    pub app_secret: String,
    pub user_agent: String,
}

impl UpstreamConfig {
    pub fn new(
        base_url: impl Into<String>,
        app_id: impl Into<String>,
        app_secret: impl Into<String>,
    ) -> Self {
        Self {
            base_url: base_url.into().trim_end_matches('/').to_owned(),
            app_id: app_id.into(),
            app_secret: app_secret.into(),
            user_agent: "NipaPlay/1.0".to_owned(),
        }
    }
}

/// Cached outcome of a token validation, keyed by a non-reversible token identity.
#[derive(Clone)]
pub struct TokenValidationCache {
    entries: Arc<Mutex<HashMap<String, TokenValidationEntry>>>,
}

struct TokenValidationEntry {
    valid: bool,
    expires_at: Instant,
}

impl Default for TokenValidationCache {
    fn default() -> Self {
        Self::new()
    }
}

impl TokenValidationCache {
    pub fn new() -> Self {
        Self {
            entries: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    fn get(&self, identity: &str) -> Option<bool> {
        let now = Instant::now();
        let mut entries = self
            .entries
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        match entries.get(identity) {
            Some(entry) if entry.expires_at > now => Some(entry.valid),
            Some(_) => {
                entries.remove(identity);
                None
            }
            None => None,
        }
    }

    fn put(&self, identity: String, valid: bool) {
        let ttl = if valid {
            Duration::from_secs(600)
        } else {
            Duration::from_secs(30)
        };
        let now = Instant::now();
        let mut entries = self
            .entries
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if entries.len() > 50_000 {
            entries.retain(|_, entry| entry.expires_at > now);
        }
        entries.insert(
            identity,
            TokenValidationEntry {
                valid,
                expires_at: now + ttl,
            },
        );
    }
}

/// Client for the Dandanplay upstream API.
///
/// Exposes play-history validation and renewal-based account identification.
/// The coordinator never proxies user traffic; renewal may rotate a token.
#[derive(Clone)]
pub struct DandanplayUpstream {
    config: Arc<UpstreamConfig>,
    client: reqwest::Client,
    cache: TokenValidationCache,
}

/// Stable account identity resolved from the upstream, never from client input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountIdentity {
    pub account_id: String,
    pub user_name: Option<String>,
}

/// Why an account lookup failed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AccountLookupError {
    /// The upstream rejected the token; the caller must re-authenticate.
    InvalidToken,
    /// The upstream was unreachable or returned an unexpected response.
    Transport(String),
}

impl std::fmt::Display for AccountLookupError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AccountLookupError::InvalidToken => formatter.write_str("invalid account token"),
            AccountLookupError::Transport(message) => formatter.write_str(message),
        }
    }
}

impl DandanplayUpstream {
    pub fn new(config: UpstreamConfig) -> Result<Self, String> {
        let client = reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(25))
            .redirect(Policy::none())
            .build()
            .map_err(|error| format!("failed to build upstream client: {error}"))?;
        Ok(Self::with_client(config, client))
    }

    /// Uses the caller's HTTP policy and connection pool with the shared auth logic.
    pub fn with_client(config: UpstreamConfig, client: reqwest::Client) -> Self {
        Self {
            config: Arc::new(config),
            client,
            cache: TokenValidationCache::new(),
        }
    }

    fn signed_get(&self, path: &str, token: &str) -> reqwest::RequestBuilder {
        self.signed_request(reqwest::Method::GET, path, token)
    }

    fn signed_request(
        &self,
        method: reqwest::Method,
        path: &str,
        token: &str,
    ) -> reqwest::RequestBuilder {
        let timestamp = unix_timestamp();
        let signature = app_signature(
            &self.config.app_id,
            timestamp,
            path.split('?')
                .next()
                .expect("a path has a first component"),
            &self.config.app_secret,
        );
        self.client
            .request(method, format!("{}{path}", self.config.base_url))
            .header(reqwest::header::ACCEPT, "application/json")
            .header(reqwest::header::USER_AGENT, &self.config.user_agent)
            .header(reqwest::header::AUTHORIZATION, format!("Bearer {token}"))
            .header("x-appid", &self.config.app_id)
            .header("x-timestamp", timestamp.to_string())
            .header("x-signature", signature)
    }

    /// Validates a bearer token with the read-only play-history endpoint.
    ///
    /// Valid results are cached for 10 minutes, invalid ones for 30 seconds.
    pub async fn validate_token(&self, token: &str, identity: &str) -> Result<bool, String> {
        if let Some(valid) = self.cache.get(identity) {
            return Ok(valid);
        }

        let response = self
            .signed_get(
                "/api/v2/playhistory?withRelatedBangumi=false&pageIndex=0&pageSize=1",
                token,
            )
            .send()
            .await
            .map_err(|error| error.to_string())?;

        let status = response.status();
        if status == reqwest::StatusCode::UNAUTHORIZED || status == reqwest::StatusCode::FORBIDDEN {
            self.cache.put(identity.to_owned(), false);
            return Ok(false);
        }
        if !status.is_success() {
            return Err(format!("token validation returned HTTP {status}"));
        }
        let payload: Value = response.json().await.map_err(|error| error.to_string())?;
        let valid = payload.get("success").and_then(Value::as_bool) == Some(true);
        self.cache.put(identity.to_owned(), valid);
        Ok(valid)
    }

    /// Resolves the stable upstream account identity for a token.
    ///
    /// Uses `POST /api/v2/login/renew`, with GET fallback on 405 + Allow: GET,
    /// matching the application client's renewal policy. It returns `LoginResponse`
    /// shape as a fresh login (including the numeric `userId`). The upstream
    /// derives the identity from the token itself, so the coordinator never
    /// trusts a client-supplied account id.
    pub async fn resolve_account(
        &self,
        token: &str,
    ) -> Result<AccountIdentity, AccountLookupError> {
        let mut response = self
            .signed_request(reqwest::Method::POST, "/api/v2/login/renew", token)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .send()
            .await
            .map_err(|error| AccountLookupError::Transport(error.to_string()))?;
        if response.status() == reqwest::StatusCode::METHOD_NOT_ALLOWED
            && response
                .headers()
                .get(reqwest::header::ALLOW)
                .and_then(|value| value.to_str().ok())
                .is_some_and(|allow| {
                    allow
                        .split(',')
                        .any(|method| method.trim().eq_ignore_ascii_case("GET"))
                })
        {
            response = self
                .signed_get("/api/v2/login/renew", token)
                .send()
                .await
                .map_err(|error| AccountLookupError::Transport(error.to_string()))?;
        }

        let status = response.status();
        if status == reqwest::StatusCode::UNAUTHORIZED || status == reqwest::StatusCode::FORBIDDEN {
            return Err(AccountLookupError::InvalidToken);
        }
        if !status.is_success() {
            return Err(AccountLookupError::Transport(format!(
                "account lookup returned HTTP {status}"
            )));
        }
        let payload: Value = response
            .json()
            .await
            .map_err(|error| AccountLookupError::Transport(error.to_string()))?;
        if payload.get("success").and_then(Value::as_bool) != Some(true) {
            return Err(AccountLookupError::InvalidToken);
        }
        let account_id = payload
            .get("userId")
            .and_then(Value::as_i64)
            .filter(|id| *id > 0)
            .map(|id| id.to_string())
            .ok_or_else(|| {
                AccountLookupError::Transport("upstream response is missing userId".to_owned())
            })?;
        let user_name = payload
            .get("userName")
            .and_then(Value::as_str)
            .map(str::to_owned);
        Ok(AccountIdentity {
            account_id,
            user_name,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn signs_the_path_without_query_and_preserves_validation_request() {
        let mut config = UpstreamConfig::new("http://127.0.0.1:1", "test-app", "test-secret");
        config.user_agent = "test-agent".to_owned();
        let upstream = DandanplayUpstream::new(config).unwrap();
        let request = upstream
            .signed_get(
                "/api/v2/playhistory?withRelatedBangumi=false&pageIndex=0&pageSize=1",
                "test-token",
            )
            .build()
            .unwrap();
        let headers = request.headers();
        let timestamp = headers["x-timestamp"].to_str().unwrap().parse().unwrap();
        assert_eq!(
            headers["x-signature"],
            app_signature("test-app", timestamp, "/api/v2/playhistory", "test-secret")
        );
        assert_eq!(
            request.url().query(),
            Some("withRelatedBangumi=false&pageIndex=0&pageSize=1")
        );
        assert_eq!(headers["authorization"], "Bearer test-token");
        assert_eq!(headers["accept"], "application/json");
        assert_eq!(headers["user-agent"], "test-agent");
        assert_eq!(headers["x-appid"], "test-app");
    }

    #[test]
    fn caches_valid_and_invalid_results_with_distinct_ttls_and_expires_them() {
        let cache = TokenValidationCache::new();
        let before = Instant::now();
        cache.put("valid".to_owned(), true);
        cache.put("invalid".to_owned(), false);
        let after = Instant::now();
        assert_eq!(cache.get("valid"), Some(true));
        assert_eq!(cache.get("invalid"), Some(false));
        {
            let mut entries = cache.entries.lock().unwrap();
            for (key, ttl) in [("valid", 600), ("invalid", 30)] {
                let entry = entries.get_mut(key).unwrap();
                assert!(entry.expires_at >= before + Duration::from_secs(ttl));
                assert!(entry.expires_at <= after + Duration::from_secs(ttl));
                entry.expires_at = before - Duration::from_secs(1);
            }
        }
        assert_eq!(cache.get("valid"), None);
        assert_eq!(cache.get("invalid"), None);
    }

    #[test]
    fn signature_matches_a_fixed_independent_vector() {
        assert_eq!(
            app_signature("test-app", 123, "/api/v2/playhistory", "test-secret"),
            "JcZCk+i2x9jLi+FPpJrwTkPpIV4KKC1Ti5Uanco0E6U="
        );
    }
}
