use std::{net::SocketAddr, path::PathBuf};

use nipaplay_auth::{env_bool, env_number, env_value, load_app_secret, UpstreamConfig};

/// Minimum heartbeat interval the coordinator will advertise, per the Mesh
/// taskbook (heartbeats no more often than every 15 minutes, with jitter).
pub const MIN_HEARTBEAT_INTERVAL_SECONDS: u64 = 900;

/// Hard upper bound on address candidate lifetime (2 hours). Candidates are
/// low-frequency hints, so the coordinator never stores them for long.
pub const MAX_ADDRESS_TTL_SECONDS: u64 = 2 * 3600;

pub struct Config {
    pub listen: SocketAddr,
    pub database_path: PathBuf,
    pub ca_cert_file: PathBuf,
    pub ca_key_file: PathBuf,
    pub cert_validity_seconds: u64,
    pub heartbeat_interval_seconds: u64,
    pub address_default_ttl_seconds: u64,
    pub address_max_ttl_seconds: u64,
    pub register_per_hour: u32,
    pub renew_per_hour: u32,
    pub addresses_per_hour: u32,
    pub devices_per_hour: u32,
    pub ip_requests_per_minute: u32,
    pub trust_proxy_headers: bool,
    pub upstream: UpstreamConfig,
    pub account_claim_pointer: String,
}

impl Config {
    pub async fn from_env() -> Result<Self, String> {
        let listen = env_value("MESH_LISTEN_ADDR", "127.0.0.1:18082")
            .parse()
            .map_err(|error| format!("invalid MESH_LISTEN_ADDR: {error}"))?;
        let database_path = PathBuf::from(env_value("MESH_DATABASE_PATH", "nipaplay-mesh.db"));
        let ca_cert_file = required_path("MESH_CA_CERT_FILE")?;
        let ca_key_file = required_path("MESH_CA_KEY_FILE")?;

        let upstream_base = env_value("DANDANPLAY_UPSTREAM_BASE", "https://api.dandanplay.net")
            .trim_end_matches('/')
            .to_owned();
        let app_id = env_value("DANDANPLAY_APP_ID", "nipaplayv1");
        let user_agent = env_value("DANDANPLAY_USER_AGENT", "NipaPlay-Mesh/1.0");
        let app_secret = load_app_secret(&user_agent).await?;

        let heartbeat_interval_seconds = env_number(
            "MESH_HEARTBEAT_INTERVAL_SECONDS",
            MIN_HEARTBEAT_INTERVAL_SECONDS,
        )
        .max(MIN_HEARTBEAT_INTERVAL_SECONDS);
        let address_max_ttl_seconds =
            env_number("MESH_ADDRESS_MAX_TTL_SECONDS", MAX_ADDRESS_TTL_SECONDS)
                .clamp(60, MAX_ADDRESS_TTL_SECONDS);
        let address_default_ttl_seconds = env_number("MESH_ADDRESS_DEFAULT_TTL_SECONDS", 3_600)
            .clamp(60, address_max_ttl_seconds);

        Ok(Self {
            account_claim_pointer: env_value("MESH_ACCOUNT_CLAIM_POINTER", "/userId"),
            listen,
            database_path,
            ca_cert_file,
            ca_key_file,
            cert_validity_seconds: env_number("MESH_CERT_VALIDITY_SECONDS", 7 * 86_400)
                .clamp(900, 7 * 86_400),
            heartbeat_interval_seconds,
            address_default_ttl_seconds,
            address_max_ttl_seconds,
            register_per_hour: env_number("MESH_REGISTER_PER_HOUR", 10),
            renew_per_hour: env_number("MESH_RENEW_PER_HOUR", 24),
            addresses_per_hour: env_number("MESH_ADDRESSES_PER_HOUR", 60),
            devices_per_hour: env_number("MESH_DEVICES_PER_HOUR", 120),
            ip_requests_per_minute: env_number("MESH_IP_REQUESTS_PER_MINUTE", 300),
            trust_proxy_headers: env_bool("MESH_TRUST_PROXY_HEADERS", true),
            upstream: UpstreamConfig {
                base_url: upstream_base,
                app_id,
                app_secret,
                user_agent,
            },
        })
    }
}

fn required_path(name: &str) -> Result<PathBuf, String> {
    let value = env_value(name, "");
    let value = value.trim();
    if value.is_empty() {
        return Err(format!("{name} is required"));
    }
    Ok(PathBuf::from(value))
}
