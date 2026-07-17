use futures_util::StreamExt;
use md5::{Digest, Md5};
use percent_encoding::percent_decode_str;
use reqwest::header::{
    HeaderMap, HeaderValue, ACCEPT, ACCEPT_ENCODING, CONTENT_DISPOSITION, CONTENT_LENGTH,
    CONTENT_RANGE, CONTENT_TYPE, RANGE, USER_AGENT,
};
use reqwest::{Client, Method, RequestBuilder, StatusCode};
use std::fs::File;
use std::io::Read;
use std::net::IpAddr;
use std::time::Duration;
use url::Url;

const DEFAULT_MAX_HASH_LENGTH: usize = 16 * 1024 * 1024;
const DEFAULT_TIMEOUT_SECONDS: u64 = 20;

#[derive(Clone, Debug)]
pub struct RustMediaProbeResult {
    pub file_name: String,
    pub file_size: i64,
    pub bytes_hashed: i32,
    pub hash: String,
}

pub async fn probe_remote_media(
    original_url: String,
    max_hash_length: Option<i32>,
    timeout_seconds: Option<i32>,
) -> Result<RustMediaProbeResult, String> {
    let original = Url::parse(&original_url).map_err(|error| format!("无效媒体URL: {error}"))?;
    if !matches!(original.scheme(), "http" | "https") {
        return Err(format!("不支持的媒体URL协议: {}", original.scheme()));
    }
    let max_hash_length = max_hash_length
        .unwrap_or(DEFAULT_MAX_HASH_LENGTH as i32)
        .max(1) as usize;
    let timeout = Duration::from_secs(
        timeout_seconds
            .unwrap_or(DEFAULT_TIMEOUT_SECONDS as i32)
            .max(1) as u64,
    );
    let credentials = credentials_from_url(&original);
    let mut sanitized = original.clone();
    let _ = sanitized.set_username("");
    let _ = sanitized.set_password(None);

    let mut client_builder = Client::builder().timeout(timeout);
    if should_bypass_proxy(original.host_str().unwrap_or_default()) {
        client_builder = client_builder.no_proxy();
    }
    let client = client_builder
        .build()
        .map_err(|error| format!("创建HTTP客户端失败: {error}"))?;
    let headers = common_headers();

    let mut resolved_file_name = None;
    let mut file_size = None;

    let head_request = apply_auth(
        client.head(sanitized.clone()).headers(headers.clone()),
        credentials.as_ref(),
    );
    if let Ok(response) = head_request.send().await {
        if response.status().is_success() || response.status().is_redirection() {
            file_size = parse_positive_header(response.headers(), CONTENT_LENGTH);
            resolved_file_name = parse_content_disposition_file_name(response.headers());
        }
    }

    let range_request = apply_auth(
        client
            .get(sanitized.clone())
            .headers(headers.clone())
            .header(RANGE, format!("bytes=0-{}", max_hash_length - 1)),
        credentials.as_ref(),
    );
    let response = range_request
        .send()
        .await
        .map_err(|error| format!("Range请求失败: {error}"))?;
    if matches!(
        response.status(),
        StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN
    ) {
        return Err(format!(
            "远程服务器拒绝访问 (HTTP {})",
            response.status().as_u16()
        ));
    }

    if file_size.is_none() {
        file_size = parse_content_range(response.headers()).or_else(|| {
            response
                .content_length()
                .and_then(|value| i64::try_from(value).ok())
        });
    }
    resolved_file_name =
        resolved_file_name.or_else(|| parse_content_disposition_file_name(response.headers()));

    if file_size.is_none_or(|value| value <= 0) {
        file_size =
            fetch_file_size_via_propfind(&client, sanitized.clone(), headers, credentials.as_ref())
                .await;
    }
    let file_size = file_size
        .filter(|value| *value > 0)
        .ok_or("无法确定远程视频的实际大小")?;
    let expected = (file_size as usize).min(max_hash_length);

    let mut hasher = Md5::new();
    let mut bytes_hashed = 0usize;
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|error| format!("读取媒体首段失败: {error}"))?;
        let remaining = expected.saturating_sub(bytes_hashed);
        if remaining == 0 {
            break;
        }
        let take = remaining.min(chunk.len());
        hasher.update(&chunk[..take]);
        bytes_hashed += take;
        if bytes_hashed >= expected {
            break;
        }
    }
    if bytes_hashed == 0 {
        return Err("无法获取远程视频的前16MB数据".to_string());
    }
    if bytes_hashed < expected {
        return Err(format!(
            "仅获取到 {} 字节，无法满足识别所需的 {} 字节",
            bytes_hashed, expected
        ));
    }

    let hash = format!("{:x}", hasher.finalize());
    Ok(RustMediaProbeResult {
        file_name: resolved_file_name.unwrap_or_else(|| extract_file_name(&original)),
        file_size,
        bytes_hashed: expected as i32,
        hash,
    })
}

pub fn hash_file_head(file_path: String, max_bytes: Option<i32>) -> Result<String, String> {
    let max_bytes = max_bytes.unwrap_or(DEFAULT_MAX_HASH_LENGTH as i32).max(1) as usize;
    let mut file =
        File::open(&file_path).map_err(|error| format!("打开文件失败 {file_path}: {error}"))?;
    let mut hasher = Md5::new();
    let mut buffer = vec![0u8; 256 * 1024];
    let mut remaining = max_bytes;
    while remaining > 0 {
        let read_size = buffer.len().min(remaining);
        let read = file
            .read(&mut buffer[..read_size])
            .map_err(|error| format!("读取文件失败 {file_path}: {error}"))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
        remaining -= read;
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn common_headers() -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(USER_AGENT, HeaderValue::from_static("NipaPlay/1.0"));
    headers.insert(ACCEPT, HeaderValue::from_static("*/*"));
    headers.insert(ACCEPT_ENCODING, HeaderValue::from_static("identity"));
    headers
}

fn apply_auth(builder: RequestBuilder, credentials: Option<&(String, String)>) -> RequestBuilder {
    match credentials {
        Some((username, password)) => builder.basic_auth(username, Some(password)),
        None => builder,
    }
}

fn credentials_from_url(url: &Url) -> Option<(String, String)> {
    if url.username().is_empty() && url.password().is_none() {
        return None;
    }
    Some((
        percent_decode_str(url.username())
            .decode_utf8_lossy()
            .into_owned(),
        percent_decode_str(url.password().unwrap_or_default())
            .decode_utf8_lossy()
            .into_owned(),
    ))
}

fn parse_positive_header(headers: &HeaderMap, name: reqwest::header::HeaderName) -> Option<i64> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<i64>().ok())
        .filter(|value| *value > 0)
}

fn parse_content_range(headers: &HeaderMap) -> Option<i64> {
    let value = headers.get(CONTENT_RANGE)?.to_str().ok()?;
    let total = value.rsplit('/').next()?.trim();
    (total != "*").then(|| total.parse::<i64>().ok()).flatten()
}

fn parse_content_disposition_file_name(headers: &HeaderMap) -> Option<String> {
    let disposition = headers.get(CONTENT_DISPOSITION)?.to_str().ok()?;
    for part in disposition.split(';').map(str::trim) {
        let lower = part.to_ascii_lowercase();
        if lower.starts_with("filename*=") {
            let raw = strip_quotes(part.split_once('=')?.1.trim());
            let encoded = raw.split_once("''").map(|(_, value)| value).unwrap_or(raw);
            let decoded = percent_decode_str(encoded)
                .decode_utf8_lossy()
                .trim()
                .to_string();
            if !decoded.is_empty() {
                return Some(decoded);
            }
        }
    }
    for part in disposition.split(';').map(str::trim) {
        if part.to_ascii_lowercase().starts_with("filename=") {
            let value = strip_quotes(part.split_once('=')?.1.trim()).trim();
            if !value.is_empty() {
                return Some(value.to_string());
            }
        }
    }
    None
}

fn strip_quotes(value: &str) -> &str {
    if value.len() >= 2
        && ((value.starts_with('"') && value.ends_with('"'))
            || (value.starts_with('\'') && value.ends_with('\'')))
    {
        &value[1..value.len() - 1]
    } else {
        value
    }
}

async fn fetch_file_size_via_propfind(
    client: &Client,
    url: Url,
    mut headers: HeaderMap,
    credentials: Option<&(String, String)>,
) -> Option<i64> {
    headers.insert("depth", HeaderValue::from_static("0"));
    headers.insert(
        CONTENT_TYPE,
        HeaderValue::from_static("application/xml; charset=utf-8"),
    );
    let method = Method::from_bytes(b"PROPFIND").ok()?;
    let request = apply_auth(
        client
            .request(method, url)
            .headers(headers)
            .body("<?xml version=\"1.0\" encoding=\"utf-8\" ?><D:propfind xmlns:D=\"DAV:\"><D:prop><D:getcontentlength/></D:prop></D:propfind>"),
        credentials,
    );
    let response = request.send().await.ok()?;
    if !response.status().is_success() {
        return None;
    }
    let body = response.text().await.ok()?;
    let capture =
        regex::Regex::new(r"(?is)<(?:[A-Za-z0-9_-]+:)?getcontentlength[^>]*>\s*(\d+)\s*</")
            .ok()?
            .captures(&body)?;
    capture.get(1)?.as_str().parse::<i64>().ok()
}

fn extract_file_name(url: &Url) -> String {
    for key in ["path", "filePath", "file"] {
        if let Some((_, value)) = url.query_pairs().find(|(name, _)| name == key) {
            let candidate = value
                .rsplit(['/', '\\'])
                .find(|segment| !segment.trim().is_empty())
                .unwrap_or_default()
                .trim();
            if !candidate.is_empty() {
                return candidate.to_string();
            }
        }
    }
    url.path_segments()
        .and_then(|segments| segments.filter(|segment| !segment.is_empty()).next_back())
        .filter(|value| !value.is_empty())
        .unwrap_or("video")
        .to_string()
}

fn should_bypass_proxy(host: &str) -> bool {
    if host.eq_ignore_ascii_case("localhost") || host.ends_with(".local") {
        return true;
    }
    let Ok(ip) = host.parse::<IpAddr>() else {
        return false;
    };
    match ip {
        IpAddr::V4(ip) => ip.is_private() || ip.is_loopback(),
        IpAddr::V6(ip) => ip.is_loopback() || (ip.segments()[0] & 0xfe00) == 0xfc00,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::net::TcpListener;
    use std::thread;

    #[test]
    fn hashes_only_requested_file_prefix() {
        let path = std::env::temp_dir().join(format!("nipaplay-md5-{}", std::process::id()));
        let mut file = File::create(&path).unwrap();
        file.write_all(b"abcdef").unwrap();
        drop(file);
        let hash = hash_file_head(path.to_string_lossy().into_owned(), Some(3)).unwrap();
        assert_eq!(hash, "900150983cd24fb0d6963f7d28e17f72");
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn probes_range_response_without_returning_media_bytes() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            for _ in 0..2 {
                let (mut socket, _) = listener.accept().unwrap();
                let mut request = [0u8; 2048];
                let read = socket.read(&mut request).unwrap();
                let request = String::from_utf8_lossy(&request[..read]);
                if request.starts_with("HEAD ") {
                    socket
                        .write_all(
                            b"HTTP/1.1 200 OK\r\nContent-Length: 6\r\nContent-Disposition: attachment; filename=episode.mkv\r\nConnection: close\r\n\r\n",
                        )
                        .unwrap();
                } else {
                    socket
                        .write_all(
                            b"HTTP/1.1 206 Partial Content\r\nContent-Length: 6\r\nContent-Range: bytes 0-5/6\r\nConnection: close\r\n\r\nabcdef",
                        )
                        .unwrap();
                }
            }
        });

        let runtime = tokio::runtime::Runtime::new().unwrap();
        let result = runtime
            .block_on(probe_remote_media(
                format!("http://{address}/video"),
                Some(16),
                Some(5),
            ))
            .unwrap();
        server.join().unwrap();
        assert_eq!(result.file_name, "episode.mkv");
        assert_eq!(result.file_size, 6);
        assert_eq!(result.bytes_hashed, 6);
        assert_eq!(result.hash, "e80b5017098950fc58aad83c8c14978e");
    }
}
