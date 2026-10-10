//! Shared authentication and upstream helpers for NipaPlay server binaries.
//!
//! The Dandanplay gateway and the mesh coordinator both need to extract bearer
//! tokens, identify callers, rate limit them, and verify tokens against the
//! upstream Dandanplay API. This crate is the single implementation of that
//! logic so the two binaries cannot drift apart.

mod ratelimit;
mod secret;
mod upstream;

pub use ratelimit::RateLimiter;
pub use secret::{decode_legacy_secret, load_app_secret};
pub use upstream::{
    AccountIdentity, AccountLookupError, DandanplayUpstream, TokenValidationCache, UpstreamConfig,
};

use std::{
    env,
    net::{IpAddr, SocketAddr},
    str::FromStr,
    time::{SystemTime, UNIX_EPOCH},
};

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use http::{header, HeaderMap};
use sha2::{Digest, Sha256};

/// Extracts the token from an `Authorization: Bearer <token>` header.
pub fn bearer_token(headers: &HeaderMap) -> Option<&str> {
    let value = headers.get(header::AUTHORIZATION)?.to_str().ok()?;
    let (scheme, token) = value.split_once(' ')?;
    (scheme.eq_ignore_ascii_case("bearer"))
        .then_some(token.trim())
        .filter(|token| !token.is_empty())
}

/// Stable, non-reversible identifier for a token, used as a cache and log key.
pub fn token_identity(token: &str) -> String {
    let digest = Sha256::digest(token.as_bytes());
    format!("{:x}", digest)[..16].to_owned()
}

/// Client IP as reported by a trusted reverse proxy, falling back to nothing.
pub fn forwarded_ip(headers: &HeaderMap) -> Option<IpAddr> {
    for name in ["x-real-ip", "x-forwarded-for"] {
        let Some(raw) = headers.get(name).and_then(|value| value.to_str().ok()) else {
            continue;
        };
        if let Some(value) = raw.split(',').next() {
            if let Ok(ip) = IpAddr::from_str(value.trim()) {
                return Some(ip);
            }
        }
    }
    None
}

/// Reverse-proxy client IP, falling back to the socket peer address.
pub fn client_ip(headers: &HeaderMap, peer: SocketAddr) -> IpAddr {
    forwarded_ip(headers).unwrap_or(peer.ip())
}

/// Upstream request signature: base64(SHA-256(appId + timestamp + path + secret)).
pub fn app_signature(app_id: &str, timestamp: i64, path: &str, secret: &str) -> String {
    let source = format!("{app_id}{timestamp}{path}{secret}");
    BASE64.encode(Sha256::digest(source.as_bytes()))
}

/// Current UNIX time in whole seconds.
pub fn unix_timestamp() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

/// Environment value with a default.
pub fn env_value(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.to_owned())
}

/// Boolean environment value with a default.
pub fn env_bool(name: &str, default: bool) -> bool {
    env::var(name)
        .ok()
        .and_then(|value| match value.trim().to_ascii_lowercase().as_str() {
            "1" | "true" | "yes" | "on" => Some(true),
            "0" | "false" | "no" | "off" => Some(false),
            _ => None,
        })
        .unwrap_or(default)
}

/// Numeric environment value with a default.
pub fn env_number<T>(name: &str, default: T) -> T
where
    T: FromStr + Copy,
{
    env::var(name)
        .ok()
        .and_then(|value| value.trim().parse().ok())
        .unwrap_or(default)
}
