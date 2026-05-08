use std::io::{Read, SeekFrom, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;

use librqbit::ByteBufT;
use librqbit::{
    AddTorrent, AddTorrentOptions, AddTorrentResponse, Api, ListOnlyResponse, Magnet, Session,
    SessionOptions, SessionPersistenceConfig,
};
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use tokio::runtime::{Builder, Runtime};

struct TorrentRuntime {
    runtime: Runtime,
    api: Mutex<Option<Api>>,
    session: Mutex<Option<Arc<Session>>>,
    download_dir: Mutex<Option<String>>,
    stream_server: Mutex<Option<TorrentStreamServer>>,
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
        api: Mutex::new(None),
        session: Mutex::new(None),
        download_dir: Mutex::new(None),
        stream_server: Mutex::new(None),
    })
}

pub fn torrent_init_session(download_dir: String) -> Result<(), String> {
    let normalized_dir = normalize_download_dir(download_dir)?;
    let state = torrent_runtime();
    torrent_log(format_args!(
        "init_session start: download_dir={normalized_dir:?}"
    ));
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
            torrent_log(format_args!(
                "init_session reuse existing session: download_dir={normalized_dir:?}"
            ));
            let mut current_dir = state
                .download_dir
                .lock()
                .map_err(|_| "torrent download directory lock poisoned".to_string())?;
            *current_dir = Some(normalized_dir);
            return Ok(());
        }
    }

    // Session does not exist or download directory changed – (re)create it.
    let session_dir = default_session_dir(&normalized_dir);
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

    torrent_log(format_args!("init_session success"));
    Ok(())
}

pub fn torrent_add_magnet(
    magnet_uri: String,
    download_dir: String,
    create_folder_for_task: bool,
) -> Result<String, String> {
    let raw_len = magnet_uri.len();
    let magnet_uri = magnet_uri.trim().to_string();
    let had_outer_whitespace = raw_len != magnet_uri.len();
    torrent_log(format_args!(
        "add_magnet start: {}, had_outer_whitespace={had_outer_whitespace}, download_dir={download_dir:?}, create_folder_for_task={create_folder_for_task}",
        magnet_log_summary(&magnet_uri)
    ));
    if magnet_uri.is_empty() {
        torrent_log(format_args!("add_magnet rejected: magnet URI is empty"));
        return Err("magnet URI is empty".to_string());
    }

    let parsed_magnet = match Magnet::parse(&magnet_uri) {
        Ok(magnet) => {
            torrent_log(format_args!(
                "add_magnet parsed: {}",
                parsed_magnet_log_summary(&magnet)
            ));
            magnet
        }
        Err(error) => {
            let detail = format!("{error:#}");
            torrent_log(format_args!(
                "add_magnet parse failed: {}, error={}",
                magnet_log_summary(&magnet_uri),
                truncate_for_log(&detail, 240)
            ));
            return Err(format!("invalid magnet URI: {detail}"));
        }
    };

    let normalized_dir = normalize_download_dir(download_dir)?;
    torrent_init_session(normalized_dir.clone())?;
    let state = torrent_runtime();
    let api = current_api(state)?;
    let magnet_trackers = parsed_magnet.trackers.clone();

    if create_folder_for_task {
        torrent_log(format_args!(
            "add_magnet resolving metadata for task folder: {}",
            magnet_log_summary(&magnet_uri)
        ));
        let metadata = resolve_magnet_metadata_for_add(state, &magnet_uri)?;
        let fallback_folder_name = parsed_magnet
            .name
            .as_deref()
            .and_then(sanitize_folder_name)
            .or_else(|| parsed_magnet.as_id20().map(|id| id.as_string()));
        let folder_name = torrent_metadata_folder_name(&metadata).or(fallback_folder_name);
        let mut options = add_torrent_options(normalized_dir, folder_name.clone());
        if !metadata.seen_peers.is_empty() {
            options.initial_peers = Some(metadata.seen_peers.clone());
        }
        if !magnet_trackers.is_empty() {
            options.trackers = Some(magnet_trackers);
        }
        let output_folder = options.output_folder.clone();
        torrent_log(format_args!(
            "add_magnet rqbit_add start: folder_name={folder_name:?}, output_folder={output_folder:?}, source=resolved_metadata"
        ));

        return state.runtime.block_on(async {
            match api
                .api_add_torrent(
                    AddTorrent::from_bytes(metadata.torrent_bytes),
                    Some(options),
                )
                .await
            {
                Ok(response) => {
                    torrent_log(format_args!(
                        "add_magnet rqbit_add success: {}",
                        magnet_log_summary(&magnet_uri)
                    ));
                    response_to_json(&response)
                }
                Err(error) => {
                    let detail = format_error_chain(&error);
                    torrent_log(format_args!(
                        "add_magnet rqbit_add failed: {}, output_folder={output_folder:?}, error={}",
                        magnet_log_summary(&magnet_uri),
                        truncate_for_log(&detail, 480)
                    ));
                    Err(format!("failed to add magnet: {detail}"))
                }
            }
        });
    }

    let folder_name = None;
    let options = add_torrent_options(normalized_dir, folder_name.clone());
    let output_folder = options.output_folder.clone();
    torrent_log(format_args!(
        "add_magnet rqbit_add start: folder_name={folder_name:?}, output_folder={output_folder:?}"
    ));

    state.runtime.block_on(async {
        match api
            .api_add_torrent(AddTorrent::from_url(magnet_uri.clone()), Some(options))
            .await
        {
            Ok(response) => {
                torrent_log(format_args!(
                    "add_magnet rqbit_add success: {}",
                    magnet_log_summary(&magnet_uri)
                ));
                response_to_json(&response)
            }
            Err(error) => {
                let detail = format_error_chain(&error);
                torrent_log(format_args!(
                    "add_magnet rqbit_add failed: {}, output_folder={output_folder:?}, error={}",
                    magnet_log_summary(&magnet_uri),
                    truncate_for_log(&detail, 480)
                ));
                Err(format!("failed to add magnet: {detail}"))
            }
        }
    })
}

pub fn torrent_add_file(
    torrent_file_path: String,
    download_dir: String,
    create_folder_for_task: bool,
) -> Result<String, String> {
    let torrent_file_path = torrent_file_path.trim().to_string();
    torrent_log(format_args!(
        "add_torrent_file start: torrent_file_path={torrent_file_path:?}, download_dir={download_dir:?}, create_folder_for_task={create_folder_for_task}"
    ));
    if torrent_file_path.is_empty() {
        torrent_log(format_args!(
            "add_torrent_file rejected: torrent file path is empty"
        ));
        return Err("torrent file path is empty".to_string());
    }
    let normalized_dir = normalize_download_dir(download_dir)?;
    torrent_init_session(normalized_dir.clone())?;
    let state = torrent_runtime();
    let api = current_api(state)?;
    let folder_name = create_folder_for_task.then(|| file_stem_folder_name(&torrent_file_path));
    let options = add_torrent_options(normalized_dir, folder_name.clone());
    let output_folder = options.output_folder.clone();
    torrent_log(format_args!(
        "add_torrent_file rqbit_add start: folder_name={folder_name:?}, output_folder={output_folder:?}"
    ));

    state.runtime.block_on(async {
        let add = AddTorrent::from_local_filename(&torrent_file_path).map_err(|error| {
            let detail = format!("{error:#}");
            torrent_log(format_args!(
                "add_torrent_file read failed: torrent_file_path={torrent_file_path:?}, error={}",
                truncate_for_log(&detail, 480)
            ));
            format!("failed to read torrent file: {detail}")
        })?;
        match api.api_add_torrent(add, Some(options)).await {
            Ok(response) => {
                torrent_log(format_args!(
                    "add_torrent_file rqbit_add success: torrent_file_path={torrent_file_path:?}"
                ));
                response_to_json(&response)
            }
            Err(error) => {
                let detail = format_error_chain(&error);
                torrent_log(format_args!(
                    "add_torrent_file rqbit_add failed: torrent_file_path={torrent_file_path:?}, output_folder={output_folder:?}, error={}",
                    truncate_for_log(&detail, 480)
                ));
                Err(format!("failed to add torrent file: {detail}"))
            }
        }
    })
}

pub fn torrent_list(download_dir: String) -> Result<String, String> {
    torrent_init_session(download_dir)?;
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

fn resolve_magnet_metadata_for_add(
    state: &TorrentRuntime,
    magnet_uri: &str,
) -> Result<ListOnlyResponse, String> {
    let session = current_session(state)?;
    state.runtime.block_on(async {
        match session
            .add_torrent(
                AddTorrent::from_url(magnet_uri.to_string()),
                Some(AddTorrentOptions {
                    list_only: true,
                    overwrite: true,
                    ..Default::default()
                }),
            )
            .await
        {
            Ok(AddTorrentResponse::ListOnly(response)) => Ok(response),
            Ok(AddTorrentResponse::Added(_, _)) => {
                Err("unexpected torrent add response while resolving metadata".to_string())
            }
            Ok(AddTorrentResponse::AlreadyManaged(_, _)) => {
                Err("unexpected managed torrent while resolving metadata".to_string())
            }
            Err(error) => {
                let detail = format!("{error:#}");
                torrent_log(format_args!(
                    "add_magnet metadata resolve failed: {}, error={}",
                    magnet_log_summary(magnet_uri),
                    truncate_for_log(&detail, 480)
                ));
                Err(format!("failed to resolve magnet metadata: {detail}"))
            }
        }
    })
}

fn torrent_log(args: std::fmt::Arguments<'_>) {
    eprintln!("[nipaplay_torrent] {args}");
}

fn magnet_log_summary(magnet_uri: &str) -> String {
    let has_whitespace = magnet_uri.chars().any(char::is_whitespace);
    let starts_with_magnet_ci = magnet_uri.to_ascii_lowercase().starts_with("magnet:");
    let mut summary = format!(
        "len={}, starts_with_magnet={}, starts_with_magnet_ci={}, has_whitespace={has_whitespace}",
        magnet_uri.len(),
        magnet_uri.starts_with("magnet:"),
        starts_with_magnet_ci
    );

    match Magnet::parse(magnet_uri) {
        Ok(magnet) => {
            summary.push_str(", parse=ok, ");
            summary.push_str(&parsed_magnet_log_summary(&magnet));
        }
        Err(error) => {
            let detail = format!("{error:#}");
            summary.push_str(", parse=err(");
            summary.push_str(&truncate_for_log(&detail, 160));
            summary.push(')');
        }
    }

    summary
}

fn parsed_magnet_log_summary(magnet: &Magnet) -> String {
    let btv1 = magnet
        .as_id20()
        .map(|id| id.as_string())
        .unwrap_or_else(|| "<none>".to_string());
    let btv2 = magnet
        .as_id32()
        .map(|id| id.as_string())
        .unwrap_or_else(|| "<none>".to_string());
    let display_name = magnet
        .name
        .as_deref()
        .map(|name| truncate_for_log(name, 120))
        .unwrap_or_else(|| "<none>".to_string());

    format!(
        "btv1_info_hash={btv1}, btv2_info_hash={btv2}, tracker_count={}, dn={display_name:?}",
        magnet.trackers.len()
    )
}

fn format_error_chain(error: &(dyn std::error::Error + 'static)) -> String {
    let mut message = error.to_string();
    let mut source = error.source();
    while let Some(error) = source {
        message.push_str(" | caused by: ");
        message.push_str(&error.to_string());
        source = error.source();
    }
    message
}

fn truncate_for_log(value: &str, max_chars: usize) -> String {
    let mut chars = value.chars();
    let truncated: String = chars.by_ref().take(max_chars).collect();
    if chars.next().is_some() {
        format!("{truncated}...")
    } else {
        truncated
    }
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
    let mut stream = api
        .api_stream(torrent_id.into(), file_id)
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
    if let Some(name) = metadata.info.name.as_ref() {
        let name = String::from_utf8_lossy(name.as_slice());
        if let Some(folder_name) = sanitize_folder_name(name.as_ref()) {
            return Some(folder_name);
        }
    }

    let mut largest_file: Option<(u64, String)> = None;
    let files = metadata.info.iter_file_details().ok()?;
    for file in files {
        let file_name = match file.filename.to_string() {
            Ok(value) => value,
            Err(_) => continue,
        };
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
