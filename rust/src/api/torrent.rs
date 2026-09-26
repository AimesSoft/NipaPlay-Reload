use std::collections::HashMap;
use std::io::{Read, SeekFrom, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::Duration;

use futures_util::future::{AbortHandle, AbortRegistration, Abortable};

use librqbit::{
    AddTorrent, AddTorrentOptions, AddTorrentResponse, Api, DhtSessionConfig, ListOnlyResponse,
    Magnet, Session, SessionOptions, SessionPersistenceConfig,
};
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use tokio::runtime::{Builder, Runtime};

struct TorrentRuntime {
    runtime: Runtime,
    initialization: Mutex<()>,
    previews: Mutex<PreviewRegistry>,
    api: Mutex<Option<Api>>,
    session: Mutex<Option<Arc<Session>>>,
    download_dir: Mutex<Option<String>>,
    stream_server: Mutex<Option<TorrentStreamServer>>,
}

// A preview owns both the cancellation handle and its resolved metadata until
// the dialog is cancelled or the exact preview is consumed by an add request.
#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
struct PreviewRegistry {
    next_id: i32,
    requests: HashMap<i32, PreviewRequest>,
}

#[flutter_rust_bridge::frb(ignore)]
struct PreviewRequest {
    abort: AbortHandle,
    registration: Option<AbortRegistration>,
    metadata: Option<Arc<ListOnlyResponse>>,
}

#[flutter_rust_bridge::frb(ignore)]
impl PreviewRegistry {
    fn begin(&mut self) -> Result<i32, String> {
        if self.requests.len() >= 32 {
            return Err("too many pending torrent previews".to_string());
        }
        self.next_id = self
            .next_id
            .checked_add(1)
            .ok_or_else(|| "preview request ID exhausted".to_string())?;
        let (abort, registration) = AbortHandle::new_pair();
        self.requests.insert(
            self.next_id,
            PreviewRequest {
                abort,
                registration: Some(registration),
                metadata: None,
            },
        );
        Ok(self.next_id)
    }

    fn cancel(&mut self, id: i32) {
        if let Some(request) = self.requests.remove(&id) {
            request.abort.abort();
        }
    }
}

struct TorrentStreamServer {
    port: u16,
}

#[derive(Clone, Copy)]
struct HttpRange {
    start: u64,
    end: Option<u64>,
}

fn torrent_runtime() -> &'static TorrentRuntime {
    static INSTANCE: OnceLock<TorrentRuntime> = OnceLock::new();
    INSTANCE.get_or_init(|| TorrentRuntime {
        runtime: Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .thread_name("nipaplay-torrent")
            .build()
            .expect("failed to create torrent runtime"),
        initialization: Mutex::new(()),
        previews: Mutex::new(PreviewRegistry::default()),
        api: Mutex::new(None),
        session: Mutex::new(None),
        download_dir: Mutex::new(None),
        stream_server: Mutex::new(None),
    })
}

pub fn torrent_init_session(
    download_dir: String,
    session_dir: Option<String>,
) -> Result<(), String> {
    let normalized_dir = normalize_download_dir(download_dir)?;
    let state = torrent_runtime();
    // Hold this lock through creation and publication of both API and session.
    let _initialization = state
        .initialization
        .lock()
        .map_err(|_| "torrent initialization lock poisoned".to_string())?;
    std::fs::create_dir_all(&normalized_dir)
        .map_err(|error| format!("failed to create download directory: {error}"))?;

    // Keep a single rqbit session per process. The current default download
    // directory is still passed per torrent via AddTorrentOptions::output_folder.
    // Recreating the session on every directory change can race with the old
    // persistent DHT socket and fail to bind the saved DHT port.
    {
        let api_slot = state
            .api
            .lock()
            .map_err(|_| "torrent API lock poisoned".to_string())?;
        if api_slot.is_some() {
            let mut current_dir = state
                .download_dir
                .lock()
                .map_err(|_| "torrent download directory lock poisoned".to_string())?;
            *current_dir = Some(normalized_dir);
            return Ok(());
        }
    }

    let session_dir = session_dir
        .map(PathBuf::from)
        .unwrap_or_else(|| default_session_dir(&normalized_dir));
    torrent_log(format_args!(
        "init_session create session: download_dir={normalized_dir:?}, session_dir={session_dir:?}"
    ));
    let session = state.runtime.block_on(async {
        Session::new_with_opts(
            PathBuf::from(&normalized_dir),
            SessionOptions {
                fastresume: true,
                persistence: Some(SessionPersistenceConfig::Json {
                    folder: Some(session_dir),
                }),
                // HarmonyOS uses Rust's `aarch64-unknown-linux-ohos` target,
                // whose HOME points outside the application sandbox. Keep
                // rqbit from writing its global DHT cache there.
                dht: Some(DhtSessionConfig {
                    persistence: if cfg!(any(target_os = "android", feature = "ohos")) {
                        None
                    } else {
                        DhtSessionConfig::default().persistence
                    },
                    ..Default::default()
                }),
                ..Default::default()
            },
        )
        .await
        .map_err(|error| format!("failed to create torrent session: {error:#}"))
    })?;

    let mut api_slot = state
        .api
        .lock()
        .map_err(|_| "torrent API lock poisoned".to_string())?;
    *api_slot = Some(Api::new(Arc::clone(&session), None));

    let mut session_slot = state
        .session
        .lock()
        .map_err(|_| "torrent session lock poisoned".to_string())?;
    *session_slot = Some(Arc::clone(&session));

    let mut current_dir = state
        .download_dir
        .lock()
        .map_err(|_| "torrent download directory lock poisoned".to_string())?;
    *current_dir = Some(normalized_dir);

    Ok(())
}

/// Reserve a request before dispatching the asynchronous FFI call, so that
/// cancellation also works when the call has not started running yet.
#[flutter_rust_bridge::frb(sync)]
pub fn torrent_begin_preview() -> Result<i32, String> {
    torrent_runtime()
        .previews
        .lock()
        .map_err(|_| "torrent preview lock poisoned".to_string())?
        .begin()
}

#[flutter_rust_bridge::frb(sync)]
pub fn torrent_cancel_preview(request_id: i32) -> Result<(), String> {
    torrent_runtime()
        .previews
        .lock()
        .map_err(|_| "torrent preview lock poisoned".to_string())?
        .cancel(request_id);
    Ok(())
}

pub fn torrent_add_magnet(
    magnet_uri: String,
    download_dir: String,
    create_folder_for_task: bool,
    preview_id: i32,
) -> Result<String, String> {
    let magnet = Magnet::parse(magnet_uri.trim())
        .map_err(|error| format!("invalid magnet URI: {error:#}"))?;
    let state = torrent_runtime();
    let metadata = state
        .previews
        .lock()
        .map_err(|_| "torrent preview lock poisoned".to_string())?
        .requests
        .remove(&preview_id)
        .and_then(|request| request.metadata)
        .ok_or_else(|| "预览已失效，请重新预览后添加任务".to_string())?;
    if magnet.as_id20() != Some(metadata.info_hash) {
        return Err("磁力链接已改变，请重新预览".to_string());
    }
    let normalized_dir = normalize_download_dir(download_dir)?;
    torrent_init_session(normalized_dir.clone(), None)?;
    let folder = if create_folder_for_task {
        torrent_metadata_folder_name(&metadata).or_else(|| Some(metadata.info_hash.as_string()))
    } else {
        None
    };
    let mut options = add_torrent_options(normalized_dir, folder);
    options.only_files = metadata.only_files.clone();
    options.initial_peers = Some(metadata.seen_peers.clone());
    options.trackers = Some(magnet.trackers);
    add_to_session(
        state,
        AddTorrent::from_bytes(metadata.torrent_bytes.clone()),
        options,
    )
}

pub fn torrent_add_file(
    torrent_file_path: String,
    download_dir: String,
    create_folder_for_task: bool,
) -> Result<String, String> {
    let torrent_file_path = torrent_file_path.trim();
    let normalized_dir = normalize_download_dir(download_dir)?;
    torrent_init_session(normalized_dir.clone(), None)?;
    let folder = create_folder_for_task.then(|| file_stem_folder_name(torrent_file_path));
    let add = AddTorrent::from_local_filename(torrent_file_path)
        .map_err(|error| format!("failed to read torrent file: {error:#}"))?;
    add_to_session(
        torrent_runtime(),
        add,
        add_torrent_options(normalized_dir, folder),
    )
}

fn add_to_session(
    state: &TorrentRuntime,
    add: AddTorrent<'_>,
    options: AddTorrentOptions,
) -> Result<String, String> {
    let session = current_session(state)?;
    state.runtime.block_on(async {
        let response = session
            .add_torrent(add, Some(options))
            .await
            .map_err(|error| format!("failed to add torrent: {error:#}"))?;
        let (id, handle, already_exists) = match response {
            AddTorrentResponse::Added(id, handle) => (id, handle, false),
            AddTorrentResponse::AlreadyManaged(id, handle) => (id, handle, true),
            AddTorrentResponse::ListOnly(_) => {
                return Err("unexpected preview response".to_string())
            }
        };
        response_to_json(&serde_json::json!({
            "id": id,
            "already_exists": already_exists,
            "output_folder": handle.output_folder(),
        }))
    })
}

pub fn torrent_preview_magnet(
    magnet_uri: String,
    download_dir: String,
    request_id: i32,
) -> Result<String, String> {
    let state = torrent_runtime();
    let result = (|| {
        let registration = state
            .previews
            .lock()
            .map_err(|_| "torrent preview lock poisoned".to_string())?
            .requests
            .get_mut(&request_id)
            .and_then(|request| request.registration.take())
            .ok_or_else(|| "预览已取消".to_string())?;
        let magnet_uri = magnet_uri.trim();
        Magnet::parse(magnet_uri).map_err(|error| format!("invalid magnet URI: {error:#}"))?;
        torrent_init_session(download_dir, None)?;
        let session = current_session(state)?;
        let metadata = state.runtime.block_on(async {
            resolve_preview(session, magnet_uri, registration, Duration::from_secs(60)).await
        })?;
        let json = torrent_preview_to_json(&metadata)?;
        let mut previews = state
            .previews
            .lock()
            .map_err(|_| "torrent preview lock poisoned".to_string())?;
        let request = previews
            .requests
            .get_mut(&request_id)
            .ok_or_else(|| "预览已取消".to_string())?;
        request.metadata = Some(Arc::new(metadata));
        Ok(json)
    })();
    if result.is_err() {
        torrent_cancel_preview(request_id)?;
    }
    result
}

async fn resolve_preview(
    session: Arc<Session>,
    magnet_uri: &str,
    registration: AbortRegistration,
    timeout: Duration,
) -> Result<ListOnlyResponse, String> {
    let resolve = async {
        match session
            .add_torrent(
                AddTorrent::from_url(magnet_uri.to_string()),
                Some(AddTorrentOptions {
                    list_only: true,
                    ..Default::default()
                }),
            )
            .await
        {
            Ok(AddTorrentResponse::ListOnly(metadata)) => Ok(metadata),
            Ok(_) => Err("unexpected torrent response while resolving metadata".to_string()),
            Err(error) => Err(format!("failed to resolve magnet metadata: {error:#}")),
        }
    };
    bounded_preview(resolve, registration, timeout).await
}

async fn bounded_preview<T>(
    resolve: impl std::future::Future<Output = Result<T, String>>,
    registration: AbortRegistration,
    timeout: Duration,
) -> Result<T, String> {
    match tokio::time::timeout(timeout, Abortable::new(resolve, registration)).await {
        Err(_) => Err("磁力链接解析超时，请检查网络或稍后重试".to_string()),
        Ok(Err(_)) => Err("预览已取消".to_string()),
        Ok(Ok(result)) => result,
    }
}

pub fn torrent_list(download_dir: String) -> Result<String, String> {
    torrent_init_session(download_dir, None)?;
    let state = torrent_runtime();
    let api = current_api(state)?;

    let response = api.api_torrent_list_ext(librqbit::api::ApiTorrentListOpts { with_stats: true });
    response_to_json(&response)
}

pub fn torrent_details(id: i32) -> Result<String, String> {
    let id = normalize_torrent_id(id)?;
    let state = torrent_runtime();
    let api = current_api(state)?;
    let response = api
        .api_torrent_details(id.into())
        .map_err(|error| format!("failed to get torrent details: {error:#}"))?;
    response_to_json(&response)
}

pub fn torrent_stream_url(id: i32, file_id: i32, filename: String) -> Result<String, String> {
    let id = normalize_torrent_id(id)?;
    let file_id = normalize_torrent_id(file_id)?;
    let state = torrent_runtime();
    current_api(state)?;
    let port = ensure_stream_server(state)?;
    let filename = url_path_segment_encode(&file_stem_or_name(&filename));
    Ok(format!(
        "http://127.0.0.1:{port}/torrent/{id}/stream/{file_id}/{filename}"
    ))
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

fn current_session(state: &TorrentRuntime) -> Result<Arc<Session>, String> {
    state
        .session
        .lock()
        .map_err(|_| "torrent session lock poisoned".to_string())?
        .clone()
        .ok_or_else(|| "torrent session is not initialized".to_string())
}

fn torrent_log(args: std::fmt::Arguments<'_>) {
    eprintln!("[nipaplay_torrent] {args}");
}

fn ensure_stream_server(state: &'static TorrentRuntime) -> Result<u16, String> {
    let mut server_slot = state
        .stream_server
        .lock()
        .map_err(|_| "torrent stream server lock poisoned".to_string())?;
    if let Some(server) = server_slot.as_ref() {
        return Ok(server.port);
    }

    let listener = TcpListener::bind(("127.0.0.1", 0))
        .map_err(|error| format!("failed to bind torrent stream server: {error}"))?;
    let port = listener
        .local_addr()
        .map_err(|error| format!("failed to read torrent stream server address: {error}"))?
        .port();

    thread::Builder::new()
        .name("nipaplay-torrent-stream".to_string())
        .spawn(move || {
            for incoming in listener.incoming() {
                match incoming {
                    Ok(stream) => {
                        let _ = thread::Builder::new()
                            .name("nipaplay-torrent-stream-client".to_string())
                            .spawn(move || {
                                if let Err(error) = handle_stream_request(stream) {
                                    eprintln!("[nipaplay_torrent_stream] request failed: {error}");
                                }
                            });
                    }
                    Err(error) => {
                        eprintln!("[nipaplay_torrent_stream] accept failed: {error}");
                        break;
                    }
                }
            }
        })
        .map_err(|error| format!("failed to start torrent stream server: {error}"))?;

    *server_slot = Some(TorrentStreamServer { port });
    Ok(port)
}

fn handle_stream_request(mut socket: TcpStream) -> Result<(), String> {
    let request = read_http_request(&mut socket)?;
    let (method, path, range) = parse_http_request(&request)?;
    if method != "GET" && method != "HEAD" {
        write_simple_response(
            &mut socket,
            "405 Method Not Allowed",
            "text/plain",
            b"Method Not Allowed",
        )?;
        return Ok(());
    }

    let (torrent_id, file_id) =
        parse_stream_path(&path).ok_or_else(|| format!("invalid torrent stream path: {path}"))?;
    let state = torrent_runtime();
    let api = current_api(state)?;
    let mut stream = state
        .runtime
        .block_on(api.api_stream(torrent_id.into(), file_id))
        .map_err(|error| format!("failed to create torrent stream: {error:#}"))?;
    let file_len = stream.len();

    let start = range.map(|range| range.start).unwrap_or(0);
    let end = range
        .and_then(|range| range.end)
        .unwrap_or_else(|| file_len.saturating_sub(1))
        .min(file_len.saturating_sub(1));

    if file_len > 0 && (start >= file_len || start > end) {
        let body = b"Requested Range Not Satisfiable";
        write!(
            socket,
            "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            body.len()
        )
        .map_err(|error| format!("failed to write range error response: {error}"))?;
        socket
            .write_all(body)
            .map_err(|error| format!("failed to write range error body: {error}"))?;
        return Ok(());
    }

    if start > 0 {
        state
            .runtime
            .block_on(stream.seek(SeekFrom::Start(start)))
            .map_err(|error| format!("failed to seek torrent stream: {error}"))?;
    }

    let content_type = api
        .torrent_file_mime_type(torrent_id.into(), file_id)
        .unwrap_or("application/octet-stream");
    let status = if range.is_some() {
        "206 Partial Content"
    } else {
        "200 OK"
    };
    let content_length = if file_len == 0 { 0 } else { end - start + 1 };

    write!(
        socket,
        "HTTP/1.1 {status}\r\nAccept-Ranges: bytes\r\nContent-Type: {content_type}\r\nContent-Length: {content_length}\r\nConnection: close\r\n"
    )
    .map_err(|error| format!("failed to write stream headers: {error}"))?;
    if range.is_some() && file_len > 0 {
        write!(
            socket,
            "Content-Range: bytes {}-{}/{}\r\n",
            start, end, file_len
        )
        .map_err(|error| format!("failed to write content range: {error}"))?;
    }
    socket
        .write_all(b"\r\n")
        .map_err(|error| format!("failed to finish stream headers: {error}"))?;

    if method == "HEAD" {
        return Ok(());
    }

    let mut buffer = vec![0_u8; 64 * 1024];
    let mut bytes_remaining = content_length;
    while bytes_remaining > 0 {
        let read_len = buffer.len().min(bytes_remaining as usize);
        let bytes_read = state
            .runtime
            .block_on(stream.read(&mut buffer[..read_len]))
            .map_err(|error| format!("failed to read torrent stream: {error}"))?;
        if bytes_read == 0 {
            break;
        }
        socket
            .write_all(&buffer[..bytes_read])
            .map_err(|error| format!("failed to write torrent stream: {error}"))?;
        bytes_remaining = bytes_remaining.saturating_sub(bytes_read as u64);
    }

    Ok(())
}

fn read_http_request(socket: &mut TcpStream) -> Result<String, String> {
    let mut request = Vec::with_capacity(1024);
    let mut buffer = [0_u8; 1024];
    loop {
        let bytes_read = socket
            .read(&mut buffer)
            .map_err(|error| format!("failed to read HTTP request: {error}"))?;
        if bytes_read == 0 {
            break;
        }
        request.extend_from_slice(&buffer[..bytes_read]);
        if request.windows(4).any(|window| window == b"\r\n\r\n") {
            break;
        }
        if request.len() > 64 * 1024 {
            return Err("HTTP request headers are too large".to_string());
        }
    }
    String::from_utf8(request).map_err(|error| format!("invalid HTTP request encoding: {error}"))
}

fn parse_http_request(request: &str) -> Result<(&str, String, Option<HttpRange>), String> {
    let mut lines = request.lines();
    let request_line = lines
        .next()
        .ok_or_else(|| "empty HTTP request".to_string())?;
    let mut parts = request_line.split_whitespace();
    let method = parts
        .next()
        .ok_or_else(|| "missing HTTP method".to_string())?;
    let path = parts
        .next()
        .ok_or_else(|| "missing HTTP path".to_string())?
        .to_string();

    let range_start = lines.find_map(|line| {
        let (name, value) = line.split_once(':')?;
        if !name.trim().eq_ignore_ascii_case("range") {
            return None;
        }
        parse_range(value.trim())
    });

    Ok((method, path, range_start))
}

fn parse_range(value: &str) -> Option<HttpRange> {
    let range = value.strip_prefix("bytes=")?;
    let (start, end) = range.split_once('-')?;
    let start = start.trim().parse::<u64>().ok()?;
    let end = if end.trim().is_empty() {
        None
    } else {
        Some(end.trim().parse::<u64>().ok()?)
    };
    Some(HttpRange { start, end })
}

fn parse_stream_path(path: &str) -> Option<(usize, usize)> {
    let path = path.split('?').next().unwrap_or(path);
    let mut segments = path.trim_start_matches('/').split('/');
    if segments.next()? != "torrent" {
        return None;
    }
    let torrent_id = segments.next()?.parse::<usize>().ok()?;
    if segments.next()? != "stream" {
        return None;
    }
    let file_id = segments.next()?.parse::<usize>().ok()?;
    Some((torrent_id, file_id))
}

fn write_simple_response(
    socket: &mut TcpStream,
    status: &str,
    content_type: &str,
    body: &[u8],
) -> Result<(), String> {
    write!(
        socket,
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    )
    .map_err(|error| format!("failed to write HTTP response headers: {error}"))?;
    socket
        .write_all(body)
        .map_err(|error| format!("failed to write HTTP response body: {error}"))
}

fn add_torrent_options(download_dir: String, folder_name: Option<String>) -> AddTorrentOptions {
    let output_folder = folder_name
        .map(|folder| Path::new(&download_dir).join(folder))
        .unwrap_or_else(|| PathBuf::from(download_dir));

    AddTorrentOptions {
        overwrite: true,
        output_folder: Some(output_folder.to_string_lossy().into_owned()),
        ..Default::default()
    }
}

fn file_stem_folder_name(file_path: &str) -> String {
    let fallback = "torrent";
    let name = Path::new(file_path)
        .file_stem()
        .or_else(|| Path::new(file_path).file_name())
        .and_then(|name| name.to_str())
        .unwrap_or(fallback);
    sanitize_folder_name(name).unwrap_or_else(|| fallback.to_string())
}

fn file_stem_or_name(file_path: &str) -> String {
    Path::new(file_path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("video")
        .to_string()
}

fn torrent_metadata_folder_name(metadata: &ListOnlyResponse) -> Option<String> {
    if let Some(name) = metadata.info.name() {
        if let Some(folder_name) = sanitize_folder_name(name.as_ref()) {
            return Some(folder_name);
        }
    }

    let mut largest_file: Option<(u64, String)> = None;
    let files = metadata.info.iter_file_details();
    for file in files {
        let file_name = file.filename.to_string();
        let stem = Path::new(&file_name)
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or(&file_name);
        let Some(folder_name) = sanitize_folder_name(stem) else {
            continue;
        };
        if largest_file
            .as_ref()
            .map(|(length, _)| file.len > *length)
            .unwrap_or(true)
        {
            largest_file = Some((file.len, folder_name));
        }
    }

    largest_file.map(|(_, folder_name)| folder_name)
}

fn torrent_metadata_display_name(metadata: &ListOnlyResponse) -> Option<String> {
    metadata.info.name().and_then(|name| {
        let name = name.trim().to_string();
        if name.is_empty() {
            None
        } else {
            Some(name)
        }
    })
}

fn torrent_preview_to_json(metadata: &ListOnlyResponse) -> Result<String, String> {
    let files = metadata.info.iter_file_details();
    let mut total_size = 0_u64;
    let files_json = files
        .enumerate()
        .map(|(index, file)| {
            total_size = total_size.saturating_add(file.len);
            let path = file.filename.to_string();
            serde_json::json!({
                "index": index,
                "path": path,
                "length": file.len,
            })
        })
        .collect::<Vec<_>>();

    let suggested_folder_name = torrent_metadata_folder_name(metadata).unwrap_or_default();
    let name = torrent_metadata_display_name(metadata)
        .or_else(|| {
            if suggested_folder_name.is_empty() {
                None
            } else {
                Some(suggested_folder_name.clone())
            }
        })
        .unwrap_or_else(|| "未命名任务".to_string());

    response_to_json(&serde_json::json!({
        "name": name,
        "suggested_folder_name": suggested_folder_name,
        "total_size": total_size,
        "files": files_json,
    }))
}

fn url_path_segment_encode(input: &str) -> String {
    let mut output = String::new();
    for byte in input.as_bytes() {
        match *byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                output.push(*byte as char)
            }
            byte => output.push_str(&format!("%{byte:02X}")),
        }
    }
    output
}

fn sanitize_folder_name(name: &str) -> Option<String> {
    let stem = Path::new(name)
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or(name);
    let sanitized: String = stem
        .chars()
        .map(|ch| match ch {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            ch if ch.is_control() => '_',
            ch => ch,
        })
        .collect();
    let sanitized = sanitized.trim().trim_matches('.').trim().to_string();
    if sanitized.is_empty() {
        None
    } else {
        Some(sanitized)
    }
}

fn normalize_download_dir(download_dir: String) -> Result<String, String> {
    let download_dir = download_dir.trim();
    if download_dir.is_empty() {
        return Err("download directory is empty".to_string());
    }
    let path = std::path::PathBuf::from(download_dir);

    // Canonicalize to resolve symlinks and relative components (e.g. ../../).
    // This prevents path-traversal attacks.
    let canonical = if path.exists() {
        path.canonicalize()
            .map_err(|error| format!("invalid download directory '{}': {error}", download_dir))?
    } else {
        // Path doesn't exist yet – canonicalize the parent and append the
        // final component so the caller can later create_dir_all on it.
        let parent = path
            .parent()
            .filter(|p| p.exists())
            .ok_or_else(|| format!("parent directory for '{}' does not exist", download_dir))?;
        let canon_parent = parent
            .canonicalize()
            .map_err(|error| format!("invalid parent directory for '{}': {error}", download_dir))?;
        let file_name = path
            .file_name()
            .ok_or_else(|| "invalid download directory path".to_string())?;
        canon_parent.join(file_name)
    };

    canonical
        .into_os_string()
        .into_string()
        .map_err(|_| "download directory path contains invalid unicode".to_string())
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

    #[cfg(any(target_os = "android", feature = "ohos"))]
    {
        // Android does not expose XDG_DATA_HOME or HOME env vars. HarmonyOS
        // exposes a HOME outside the application sandbox. Store the session
        // beside downloads so both platforms use an app-writable location.
        return PathBuf::from(download_dir).join(".nipaplay_torrent_session");
    }

    #[cfg(not(any(
        target_os = "macos",
        target_os = "windows",
        target_os = "android",
        feature = "ohos"
    )))]
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

    #[cfg(not(any(target_os = "android", feature = "ohos")))]
    return PathBuf::from(download_dir).join(".nipaplay_torrent_session");
}

fn normalize_torrent_id(id: i32) -> Result<usize, String> {
    usize::try_from(id).map_err(|_| format!("invalid torrent id: {id}"))
}

fn response_to_json<T: serde::Serialize>(response: &T) -> Result<String, String> {
    serde_json::to_string(response).map_err(|error| format!("failed to encode JSON: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn runtime() -> Runtime {
        Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .unwrap()
    }

    #[test]
    fn cancellation_before_dispatch_releases_the_request() {
        let mut requests = PreviewRegistry::default();
        let id = requests.begin().unwrap();
        requests.cancel(id);
        assert!(!requests.requests.contains_key(&id));
        requests.cancel(id); // Closing an already completed dialog is harmless.
    }

    #[test]
    fn cancellation_aborts_an_in_flight_resolution() {
        let mut requests = PreviewRegistry::default();
        let id = requests.begin().unwrap();
        let registration = requests
            .requests
            .get_mut(&id)
            .unwrap()
            .registration
            .take()
            .unwrap();
        let handle = requests.requests.get(&id).unwrap().abort.clone();
        runtime().block_on(async {
            let resolving = bounded_preview(
                std::future::pending::<Result<(), String>>(),
                registration,
                Duration::from_secs(60),
            );
            let cancel = async {
                tokio::task::yield_now().await;
                handle.abort();
            };
            let (result, _) = tokio::join!(resolving, cancel);
            assert_eq!(result.unwrap_err(), "预览已取消");
        });
    }

    #[test]
    fn resolution_timeout_drops_network_work() {
        struct OnDrop(Arc<AtomicUsize>);
        impl Drop for OnDrop {
            fn drop(&mut self) {
                self.0.fetch_add(1, Ordering::SeqCst);
            }
        }
        let dropped = Arc::new(AtomicUsize::new(0));
        let guard = OnDrop(dropped.clone());
        let (_, registration) = AbortHandle::new_pair();
        runtime().block_on(async {
            let result = bounded_preview(
                async move {
                    let _guard = guard;
                    std::future::pending::<Result<(), String>>().await
                },
                registration,
                Duration::from_millis(10),
            )
            .await;
            assert!(result.unwrap_err().contains("超时"));
        });
        assert_eq!(dropped.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn adding_resolved_bytes_offline_reports_duplicates_and_keeps_original_directory() {
        let directory =
            std::env::temp_dir().join(format!("nipaplay-torrent-test-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let runtime = runtime();
        let session = runtime
            .block_on(Session::new_with_opts(
                directory.clone(),
                SessionOptions {
                    dht: None,
                    disable_trackers: true,
                    disable_local_service_discovery: true,
                    ..Default::default()
                },
            ))
            .unwrap();
        let state = TorrentRuntime {
            runtime,
            initialization: Mutex::new(()),
            previews: Mutex::new(PreviewRegistry::default()),
            api: Mutex::new(Some(Api::new(session.clone(), None))),
            session: Mutex::new(Some(session.clone())),
            download_dir: Mutex::new(None),
            stream_server: Mutex::new(None),
        };
        // One byte, no trackers. Neither adding nor re-adding may resolve peers.
        let bytes = b"d4:infod6:lengthi1e4:name8:test.mp412:piece lengthi16384e6:pieces20:00000000000000000000ee";
        let first_folder = directory.join("first").to_string_lossy().into_owned();
        let first = add_to_session(
            &state,
            AddTorrent::from_bytes(bytes.as_slice()),
            AddTorrentOptions {
                paused: true,
                ..add_torrent_options(first_folder.clone(), None)
            },
        )
        .unwrap();
        let second = add_to_session(
            &state,
            AddTorrent::from_bytes(bytes.as_slice()),
            AddTorrentOptions {
                paused: true,
                ..add_torrent_options(
                    directory.join("second").to_string_lossy().into_owned(),
                    None,
                )
            },
        )
        .unwrap();
        let first: serde_json::Value = serde_json::from_str(&first).unwrap();
        let second: serde_json::Value = serde_json::from_str(&second).unwrap();
        assert_eq!(first["already_exists"], false);
        assert_eq!(second["already_exists"], true);
        assert_eq!(first["id"], second["id"]);
        assert_eq!(second["output_folder"], first_folder);
        assert!(session
            .get((first["id"].as_u64().unwrap() as usize).into())
            .unwrap()
            .is_paused());
        state.runtime.block_on(session.stop());
        drop(state);
        std::fs::remove_dir_all(directory).unwrap();
    }
}
