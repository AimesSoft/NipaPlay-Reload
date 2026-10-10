//! Account authentication: verify the bearer token upstream and resolve the
//! stable Dandanplay user id. The client's self-reported identity is never used.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use nipaplay_auth::{AccountLookupError, DandanplayUpstream};

use crate::error::{ApiError, ErrorCode};

const VALID_TTL: Duration = Duration::from_secs(600);
const INVALID_TTL: Duration = Duration::from_secs(30);

#[derive(Clone)]
pub struct AccountResolver {
    upstream: DandanplayUpstream,
    cache: Arc<Mutex<HashMap<String, CachedAccount>>>,
}

#[derive(Clone)]
enum CachedAccount {
    Valid {
        account_id: String,
        expires_at: Instant,
    },
    Invalid {
        expires_at: Instant,
    },
}

impl AccountResolver {
    pub fn new(upstream: DandanplayUpstream) -> Self {
        Self {
            upstream,
            cache: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn known_account(&self, identity: &str) -> Option<String> {
        let cache = self
            .cache
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        match cache.get(identity) {
            Some(CachedAccount::Valid { account_id, .. }) => Some(account_id.clone()),
            _ => None,
        }
    }

    /// Verifies a bearer token and returns the upstream account id.
    ///
    /// A token must both pass the read-only validation endpoint and yield a
    /// numeric `userId` from the renewal endpoint. Any other outcome is an
    /// authentication failure; a network/upstream fault is reported separately
    /// so clients can retry instead of treating the token as invalid.
    pub async fn resolve(&self, token: &str, identity: &str) -> Result<String, ApiError> {
        if let Some(account_id) = self.cached(identity) {
            return account_id;
        }

        let valid = self
            .upstream
            .validate_token(token, identity)
            .await
            .map_err(|error| {
                ApiError::new(
                    ErrorCode::UpstreamUnavailable,
                    format!("无法验证账号登录状态：{error}"),
                )
            })?;
        if !valid {
            self.store_invalid(identity);
            return Err(ApiError::new(
                ErrorCode::InvalidToken,
                "弹弹play 登录已失效，请重新登录",
            ));
        }

        let account = match self.upstream.resolve_account(token).await {
            Ok(account) => account,
            Err(error) => {
                return Err(match error {
                    AccountLookupError::InvalidToken => {
                        self.store_invalid(identity);
                        ApiError::new(ErrorCode::InvalidToken, "弹弹play 登录已失效，请重新登录")
                    }
                    AccountLookupError::Transport(message) => ApiError::new(
                        ErrorCode::UpstreamUnavailable,
                        format!("无法获取账号身份：{message}"),
                    ),
                })
            }
        };

        self.store_valid(identity, account.account_id.clone());
        Ok(account.account_id)
    }

    fn cached(&self, identity: &str) -> Option<Result<String, ApiError>> {
        let now = Instant::now();
        let mut cache = self
            .cache
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        match cache.get(identity) {
            Some(CachedAccount::Valid {
                account_id,
                expires_at,
            }) if *expires_at > now => Some(Ok(account_id.clone())),
            Some(CachedAccount::Invalid { expires_at }) if *expires_at > now => Some(Err(
                ApiError::new(ErrorCode::InvalidToken, "弹弹play 登录已失效，请重新登录"),
            )),
            Some(_) => {
                cache.remove(identity);
                None
            }
            None => None,
        }
    }

    fn store_valid(&self, identity: &str, account_id: String) {
        let mut cache = self
            .cache
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        prune(&mut cache);
        if cache.len() >= 50_000 {
            return;
        }
        cache.insert(
            identity.to_owned(),
            CachedAccount::Valid {
                account_id,
                expires_at: Instant::now() + VALID_TTL,
            },
        );
    }

    fn store_invalid(&self, identity: &str) {
        let mut cache = self
            .cache
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        prune(&mut cache);
        if cache.len() >= 50_000 {
            return;
        }
        cache.insert(
            identity.to_owned(),
            CachedAccount::Invalid {
                expires_at: Instant::now() + INVALID_TTL,
            },
        );
    }
}

fn prune(cache: &mut HashMap<String, CachedAccount>) {
    if cache.len() >= 50_000 {
        let now = Instant::now();
        cache.retain(|_, entry| match entry {
            CachedAccount::Valid { expires_at, .. } | CachedAccount::Invalid { expires_at } => {
                *expires_at > now
            }
        });
    }
}
