use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
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
/// Exposes read-only token validation and identity from the accepted JWT.
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
    InvalidIdentity(String),
}

impl std::fmt::Display for AccountLookupError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AccountLookupError::InvalidToken => formatter.write_str("invalid account token"),
            AccountLookupError::Transport(message) => formatter.write_str(message),
            AccountLookupError::InvalidIdentity(message) => formatter.write_str(message),
        }
    }
}
impl std::error::Error for AccountLookupError {}

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

    /// Validates the exact bearer token upstream before reading its JWT identity.
    pub async fn resolve_account(
        &self,
        token: &str,
        claim_pointer: &str,
    ) -> Result<AccountIdentity, AccountLookupError> {
        use sha2::Digest;
        let identity = format!("{:x}", sha2::Sha256::digest(token.as_bytes()));
        if !self
            .validate_token(token, &identity)
            .await
            .map_err(AccountLookupError::Transport)?
        {
            return Err(AccountLookupError::InvalidToken);
        }
        let payload = jwt_payload(token)?;
        let claim = payload.pointer(claim_pointer).ok_or_else(|| {
            AccountLookupError::InvalidIdentity(
                "account identity claim is missing; configure MESH_ACCOUNT_CLAIM_POINTER"
                    .to_owned(),
            )
        })?;
        let account_id = match claim {
            Value::Number(number) => number
                .as_u64()
                .filter(|id| *id > 0)
                .map(|id| id.to_string()),
            Value::String(value)
                if !value.is_empty()
                    && value.len() <= 128
                    && value
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b"-._".contains(&b))
                    && value != "0" =>
            {
                Some(value.clone())
            }
            _ => None,
        }
        .ok_or_else(|| {
            AccountLookupError::InvalidIdentity(
                "account identity claim must be a positive integer or a nonempty identifier"
                    .to_owned(),
            )
        })?;
        Ok(AccountIdentity {
            account_id,
            user_name: None,
        })
    }

    /// For operator diagnostics: verifies upstream first, returns names only.
    pub async fn account_claim_names(
        &self,
        token: &str,
    ) -> Result<Vec<String>, AccountLookupError> {
        if !self
            .validate_token(token, &crate::token_identity(token))
            .await
            .map_err(AccountLookupError::Transport)?
        {
            return Err(AccountLookupError::InvalidToken);
        }
        let payload = jwt_payload(token)?;
        let mut names = Vec::new();
        fn walk(value: &Value, path: &str, names: &mut Vec<String>) {
            if let Value::Object(fields) = value {
                for (key, value) in fields {
                    let pointer = format!("{path}/{}", key.replace('~', "~0").replace('/', "~1"));
                    names.push(pointer.clone());
                    walk(value, &pointer, names);
                }
            }
        }
        walk(&payload, "", &mut names);
        names.sort();
        Ok(names)
    }
}

fn jwt_payload(token: &str) -> Result<Value, AccountLookupError> {
    let invalid = || AccountLookupError::InvalidIdentity("invalid JWT payload".to_owned());
    let parts: Vec<_> = token.split('.').collect();
    if parts.len() != 3 || parts.iter().any(|part| part.is_empty()) {
        return Err(invalid());
    }
    let bytes = URL_SAFE_NO_PAD.decode(parts[1]).map_err(|_| invalid())?;
    let payload: Value = serde_json::from_slice(&bytes).map_err(|_| invalid())?;
    if !payload.is_object() {
        return Err(invalid());
    }
    Ok(payload)
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
