//! NipaPlay Mesh coordinator: account-scoped control plane.
//!
//! Responsibilities:
//! - verify the caller's Dandanplay token upstream and resolve the stable account id;
//! - register devices and issue short-lived Ed25519 X.509 device certificates;
//! - list an account's devices and revoke them;
//! - accept and serve low-frequency address candidates.
//!
//! The coordinator never proxies media or task traffic between devices.

mod account;
mod api;
mod cert;
mod config;
mod error;
mod store;
#[cfg(test)]
mod tests;

use std::{path::PathBuf, sync::Arc, time::Duration};

use clap::Parser;
use nipaplay_auth::{DandanplayUpstream, RateLimiter};
use tokio::net::TcpListener;
use tracing::info;
use tracing_subscriber::EnvFilter;

use crate::{
    account::AccountResolver, api::AppState, cert::CertificateAuthority, config::Config,
    store::Store,
};

#[derive(Parser)]
#[command(
    name = "nipaplay-mesh-coordinator",
    about = "NipaPlay Mesh control plane"
)]
struct Cli {
    /// Generate a development CA at the given certificate/key paths and exit.
    #[arg(long, num_args = 2, value_names = ["CERT_PEM", "KEY_PEM"])]
    generate_dev_ca: Option<Vec<PathBuf>>,
    /// Read a token from stdin, validate it, print only JWT claim JSON pointers.
    #[arg(long)]
    inspect_account_claim_names: bool,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let cli = Cli::parse();
    if let Some(paths) = cli.generate_dev_ca {
        let cert_path = &paths[0];
        let key_path = &paths[1];
        cert::generate_ca(cert_path, key_path).map_err(std::io::Error::other)?;
        println!(
            "wrote development CA certificate to {} and key to {}",
            cert_path.display(),
            key_path.display()
        );
        return Ok(());
    }

    let config = Arc::new(Config::from_env().await.map_err(std::io::Error::other)?);
    let upstream = DandanplayUpstream::via_gateway(
        config.gateway_base.clone(),
        config.gateway_user_agent.clone(),
    )
    .map_err(std::io::Error::other)?;
    if cli.inspect_account_claim_names {
        use std::io::Read;
        let mut token = String::new();
        std::io::stdin().take(4097).read_to_string(&mut token)?;
        let names = upstream
            .account_claim_names(token.trim())
            .await
            .map_err(std::io::Error::other)?;
        println!("{}", serde_json::to_string(&names)?);
        return Ok(());
    }
    let store = Store::open(&config.database_path).map_err(std::io::Error::other)?;
    let ca = Arc::new(
        CertificateAuthority::load(&config.ca_cert_file, &config.ca_key_file)
            .map_err(std::io::Error::other)?,
    );
    let state = AppState {
        config: Arc::clone(&config),
        store: store.clone(),
        ca,
        accounts: AccountResolver::new(upstream, config.account_claim_pointer.clone()),
        limiter: RateLimiter::new(),
    };

    let prune_store = store;
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(Duration::from_secs(3600));
        loop {
            ticker.tick().await;
            if let Err(error) = prune_store.prune_expired_addresses(nipaplay_auth::unix_timestamp())
            {
                tracing::warn!(%error, "failed to prune expired address candidates");
            }
        }
    });

    let app = api::router(state);
    let listener = TcpListener::bind(config.listen).await?;
    info!(
        listen = %config.listen,
        database = %config.database_path.display(),
        "NipaPlay Mesh coordinator started"
    );
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<std::net::SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await?;
    Ok(())
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
