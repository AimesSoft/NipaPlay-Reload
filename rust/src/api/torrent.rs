use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};

use librqbit::{
    AddTorrent, AddTorrentOptions, Api, Session, SessionOptions, SessionPersistenceConfig,
};
use tokio::runtime::{Builder, Runtime};

struct TorrentRuntime {
    runtime: Runtime,
    api: Mutex<Option<Api>>,
    download_dir: Mutex<Option<String>>,
}

fn torrent_runtime() -> &'static TorrentRuntime {
    static INSTANCE: OnceLock<TorrentRuntime> = OnceLock::new();
    INSTANCE.get_or_init(|| TorrentRuntime {
        runtime: Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .thread_name("nipaplay-torrent")
            .build()
            .expect("failed to create torrent runtime"),
        api: Mutex::new(None),
        download_dir: Mutex::new(None),
    })
}

pub fn torrent_init_session(download_dir: String) -> Result<(), String> {
    let normalized_dir = normalize_download_dir(download_dir)?;
    let state = torrent_runtime();
    std::fs::create_dir_all(&normalized_dir)
        .map_err(|error| format!("failed to create download directory: {error}"))?;

    {
        let mut api_slot = state
            .api
            .lock()
            .map_err(|_| "torrent API lock poisoned".to_string())?;
        if api_slot.is_none() {
            let session_dir = default_session_dir(&normalized_dir);
            let session = state.runtime.block_on(async {
                Session::new_with_opts(
                    PathBuf::from(&normalized_dir),
                    SessionOptions {
                        fastresume: true,
                        persistence: Some(SessionPersistenceConfig::Json {
                            folder: Some(session_dir),
                        }),
                        ..Default::default()
                    },
                )
                .await
                .map_err(|error| format!("failed to create torrent session: {error:#}"))
            })?;
            *api_slot = Some(Api::new(Arc::clone(&session), None));
        }
    }
    {
        let mut current_dir = state
            .download_dir
            .lock()
            .map_err(|_| "torrent download directory lock poisoned".to_string())?;
        if current_dir.as_deref() == Some(normalized_dir.as_str()) {
            return Ok(());
        }
        *current_dir = Some(normalized_dir);
    }

    Ok(())
}

pub fn torrent_add_magnet(magnet_uri: String, download_dir: String) -> Result<String, String> {
    let magnet_uri = magnet_uri.trim().to_string();
    if magnet_uri.is_empty() {
        return Err("magnet URI is empty".to_string());
    }
    let normalized_dir = normalize_download_dir(download_dir)?;
    torrent_init_session(normalized_dir.clone())?;
    let state = torrent_runtime();
    let api = current_api(state)?;

    state.runtime.block_on(async {
        api.api_add_torrent(
            AddTorrent::from_url(magnet_uri),
            Some(AddTorrentOptions {
                overwrite: true,
                output_folder: Some(normalized_dir),
                ..Default::default()
            }),
        )
        .await
        .map_err(|error| format!("failed to add magnet: {error:#}"))
        .and_then(|response| response_to_json(&response))
    })
}

pub fn torrent_add_file(torrent_file_path: String, download_dir: String) -> Result<String, String> {
    let torrent_file_path = torrent_file_path.trim().to_string();
    if torrent_file_path.is_empty() {
        return Err("torrent file path is empty".to_string());
    }
    let normalized_dir = normalize_download_dir(download_dir)?;
    torrent_init_session(normalized_dir.clone())?;
    let state = torrent_runtime();
    let api = current_api(state)?;

    state.runtime.block_on(async {
        api.api_add_torrent(
            AddTorrent::from_local_filename(&torrent_file_path)
                .map_err(|error| format!("failed to read torrent file: {error:#}"))?,
            Some(AddTorrentOptions {
                overwrite: true,
                output_folder: Some(normalized_dir),
                ..Default::default()
            }),
        )
        .await
        .map_err(|error| format!("failed to add torrent file: {error:#}"))
        .and_then(|response| response_to_json(&response))
    })
}

pub fn torrent_list(download_dir: String) -> Result<String, String> {
    torrent_init_session(download_dir)?;
    let state = torrent_runtime();
    let api = current_api(state)?;

    let response = api.api_torrent_list_ext(librqbit::api::ApiTorrentListOpts { with_stats: true });
    response_to_json(&response)
}

pub fn torrent_pause(id: i32) -> Result<(), String> {
    let id = normalize_torrent_id(id)?;
    let state = torrent_runtime();
    let api = current_api(state)?;
    state
        .runtime
        .block_on(async { api.api_torrent_action_pause(id.into()).await })
        .map(|_| ())
        .map_err(|error| format!("failed to pause torrent: {error:#}"))
}

pub fn torrent_resume(id: i32) -> Result<(), String> {
    let id = normalize_torrent_id(id)?;
    let state = torrent_runtime();
    let api = current_api(state)?;
    state
        .runtime
        .block_on(async { api.api_torrent_action_start(id.into()).await })
        .map(|_| ())
        .map_err(|error| format!("failed to resume torrent: {error:#}"))
}

pub fn torrent_forget(id: i32) -> Result<(), String> {
    let id = normalize_torrent_id(id)?;
    let state = torrent_runtime();
    let api = current_api(state)?;
    state
        .runtime
        .block_on(async { api.api_torrent_action_forget(id.into()).await })
        .map(|_| ())
        .map_err(|error| format!("failed to remove torrent: {error:#}"))
}

pub fn torrent_delete(id: i32) -> Result<(), String> {
    let id = normalize_torrent_id(id)?;
    let state = torrent_runtime();
    let api = current_api(state)?;
    state
        .runtime
        .block_on(async { api.api_torrent_action_delete(id.into()).await })
        .map(|_| ())
        .map_err(|error| format!("failed to delete torrent files: {error:#}"))
}

#[flutter_rust_bridge::frb(sync)]
pub fn is_torrent_engine_available() -> bool {
    true
}

fn current_api(state: &TorrentRuntime) -> Result<Api, String> {
    state
        .api
        .lock()
        .map_err(|_| "torrent API lock poisoned".to_string())?
        .clone()
        .ok_or_else(|| "torrent session is not initialized".to_string())
}

fn normalize_download_dir(download_dir: String) -> Result<String, String> {
    let download_dir = download_dir.trim();
    if download_dir.is_empty() {
        return Err("download directory is empty".to_string());
    }
    Ok(download_dir.to_string())
}

fn default_session_dir(download_dir: &str) -> PathBuf {
    #[cfg(target_os = "macos")]
    if let Some(home) = std::env::var_os("HOME") {
        return PathBuf::from(home)
            .join("Library")
            .join("Application Support")
            .join("NipaPlay")
            .join("torrent_session");
    }

    #[cfg(target_os = "windows")]
    if let Some(appdata) = std::env::var_os("APPDATA") {
        return PathBuf::from(appdata)
            .join("NipaPlay")
            .join("torrent_session");
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        if let Some(data_home) = std::env::var_os("XDG_DATA_HOME") {
            return PathBuf::from(data_home)
                .join("nipaplay")
                .join("torrent_session");
        }
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home)
                .join(".local")
                .join("share")
                .join("nipaplay")
                .join("torrent_session");
        }
    }

    PathBuf::from(download_dir).join(".nipaplay_torrent_session")
}

fn normalize_torrent_id(id: i32) -> Result<usize, String> {
    usize::try_from(id).map_err(|_| format!("invalid torrent id: {id}"))
}

fn response_to_json<T: serde::Serialize>(response: &T) -> Result<String, String> {
    serde_json::to_string(response).map_err(|error| format!("failed to encode JSON: {error}"))
}
