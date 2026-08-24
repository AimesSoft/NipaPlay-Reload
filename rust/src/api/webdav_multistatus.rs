use percent_encoding::percent_decode_str;
use quick_xml::events::Event;
use quick_xml::name::LocalName;
use quick_xml::Reader;

pub struct RustWebDavEntry {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub size: Option<i64>,
    pub last_modified: Option<String>,
}

/// Parses one complete WebDAV PROPFIND multistatus response off the Dart UI
/// isolate. Namespace prefixes are ignored and only the first propstat/prop,
/// matching the legacy Dart parser, contributes metadata.
pub fn parse_webdav_multistatus(
    xml: String,
    base_path: String,
    include_all_files: bool,
) -> Result<Vec<RustWebDavEntry>, String> {
    let mut reader = Reader::from_str(&xml);
    reader.config_mut().trim_text(false);

    let mut depth = 0usize;
    let mut response: Option<ResponseState> = None;
    let mut entries = Vec::new();

    loop {
        match reader.read_event() {
            Ok(Event::Start(element)) => {
                depth += 1;
                let name = element.local_name();
                if name_eq(name, b"response") && response.is_none() {
                    response = Some(ResponseState::new(depth));
                    continue;
                }
                if let Some(state) = response.as_mut() {
                    state.handle_start(name, depth);
                }
            }
            Ok(Event::Empty(element)) => {
                if let Some(state) = response.as_mut() {
                    state.handle_empty(element.local_name());
                }
            }
            Ok(Event::Text(text)) => {
                if let Some(state) = response.as_mut() {
                    let decoded = text
                        .unescape()
                        .map_err(|error| format!("Invalid WebDAV XML text: {error}"))?;
                    state.push_text(&decoded);
                }
            }
            Ok(Event::CData(text)) => {
                if let Some(state) = response.as_mut() {
                    let decoded = text
                        .decode()
                        .map_err(|error| format!("Invalid WebDAV XML CDATA: {error}"))?;
                    state.push_text(&decoded);
                }
            }
            Ok(Event::End(element)) => {
                if let Some(state) = response.as_mut() {
                    state.handle_end(element.local_name(), depth);
                }
                if response
                    .as_ref()
                    .is_some_and(|state| state.response_depth == depth)
                    && name_eq(element.local_name(), b"response")
                {
                    if let Some(entry) = response
                        .take()
                        .and_then(|state| state.finish(&base_path, include_all_files))
                    {
                        entries.push(entry);
                    }
                }
                depth = depth.saturating_sub(1);
            }
            Ok(Event::Eof) => {
                if response.is_some() || depth != 0 {
                    return Err("Unexpected end of WebDAV multistatus XML".to_string());
                }
                break;
            }
            Ok(_) => {}
            Err(error) => {
                return Err(format!(
                    "Invalid WebDAV multistatus XML at byte {}: {error}",
                    reader.error_position()
                ))
            }
        }
    }

    Ok(entries)
}

#[derive(Clone, Copy)]
enum TextField {
    Href,
    DisplayName,
    ContentLength,
    LastModified,
}

struct TextCapture {
    field: TextField,
    depth: usize,
    value: String,
}

struct ResponseState {
    response_depth: usize,
    propstat_selected: bool,
    propstat_depth: Option<usize>,
    prop_selected: bool,
    prop_depth: Option<usize>,
    resource_type_depth: Option<usize>,
    href: Option<String>,
    display_name: Option<String>,
    content_length: Option<String>,
    last_modified: Option<String>,
    is_directory: bool,
    capture: Option<TextCapture>,
}

impl ResponseState {
    fn new(response_depth: usize) -> Self {
        Self {
            response_depth,
            propstat_selected: false,
            propstat_depth: None,
            prop_selected: false,
            prop_depth: None,
            resource_type_depth: None,
            href: None,
            display_name: None,
            content_length: None,
            last_modified: None,
            is_directory: false,
            capture: None,
        }
    }

    fn handle_start(&mut self, name: LocalName<'_>, depth: usize) {
        if name_eq(name, b"href") && self.href.is_none() {
            self.start_capture(TextField::Href, depth);
            return;
        }
        if name_eq(name, b"propstat") && !self.propstat_selected {
            self.propstat_selected = true;
            self.propstat_depth = Some(depth);
            return;
        }
        if self.propstat_depth.is_some() && name_eq(name, b"prop") && !self.prop_selected {
            self.prop_selected = true;
            self.prop_depth = Some(depth);
            return;
        }
        if self.prop_depth.is_none() {
            return;
        }
        if name_eq(name, b"displayname") && self.display_name.is_none() {
            self.start_capture(TextField::DisplayName, depth);
        } else if name_eq(name, b"getcontentlength") && self.content_length.is_none() {
            self.start_capture(TextField::ContentLength, depth);
        } else if name_eq(name, b"getlastmodified") && self.last_modified.is_none() {
            self.start_capture(TextField::LastModified, depth);
        } else if name_eq(name, b"resourcetype") && self.resource_type_depth.is_none() {
            self.resource_type_depth = Some(depth);
        } else if name_eq(name, b"collection") && self.resource_type_depth.is_some() {
            self.is_directory = true;
        }
    }

    fn handle_empty(&mut self, name: LocalName<'_>) {
        if name_eq(name, b"href") && self.href.is_none() {
            self.href = Some(String::new());
        } else if self.prop_depth.is_some() {
            if name_eq(name, b"displayname") && self.display_name.is_none() {
                self.display_name = Some(String::new());
            } else if name_eq(name, b"getcontentlength") && self.content_length.is_none() {
                self.content_length = Some(String::new());
            } else if name_eq(name, b"getlastmodified") && self.last_modified.is_none() {
                self.last_modified = Some(String::new());
            } else if name_eq(name, b"collection") && self.resource_type_depth.is_some() {
                self.is_directory = true;
            }
        }
    }

    fn handle_end(&mut self, name: LocalName<'_>, depth: usize) {
        if self
            .capture
            .as_ref()
            .is_some_and(|capture| capture.depth == depth)
        {
            if let Some(capture) = self.capture.take() {
                self.finish_capture(capture);
            }
        }
        if self.resource_type_depth == Some(depth) && name_eq(name, b"resourcetype") {
            self.resource_type_depth = None;
        }
        if self.prop_depth == Some(depth) && name_eq(name, b"prop") {
            self.prop_depth = None;
        }
        if self.propstat_depth == Some(depth) && name_eq(name, b"propstat") {
            self.propstat_depth = None;
        }
    }

    fn start_capture(&mut self, field: TextField, depth: usize) {
        if self.capture.is_none() {
            self.capture = Some(TextCapture {
                field,
                depth,
                value: String::new(),
            });
        }
    }

    fn push_text(&mut self, value: &str) {
        if let Some(capture) = self.capture.as_mut() {
            capture.value.push_str(value);
        }
    }

    fn finish_capture(&mut self, capture: TextCapture) {
        match capture.field {
            TextField::Href => self.href = Some(capture.value),
            TextField::DisplayName => self.display_name = Some(capture.value),
            TextField::ContentLength => self.content_length = Some(capture.value),
            TextField::LastModified => self.last_modified = Some(capture.value),
        }
    }

    fn finish(self, base_path: &str, include_all_files: bool) -> Option<RustWebDavEntry> {
        if !self.propstat_selected || !self.prop_selected {
            return None;
        }
        let href = self.href?;
        let normalized_href = href.strip_suffix('/').unwrap_or(&href);
        let normalized_base_path = base_path.strip_suffix('/').unwrap_or(base_path);
        if normalized_href == normalized_base_path
            || href == base_path
            || href == format!("{base_path}/")
        {
            return None;
        }

        let mut display_name = self.display_name.unwrap_or_default();
        if display_name.is_empty() {
            display_name = href
                .split('/')
                .rev()
                .find(|segment| !segment.is_empty())
                .map(|segment| percent_decode_str(segment).decode_utf8_lossy().into_owned())
                .filter(|segment| !segment.is_empty())
                .unwrap_or_else(|| href.clone());
        }

        if !self.is_directory && !include_all_files && !is_video_file(&display_name) {
            return None;
        }

        let size = (!self.is_directory)
            .then(|| self.content_length?.trim().parse::<i64>().ok())
            .flatten();
        let last_modified = self
            .last_modified
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        Some(RustWebDavEntry {
            name: display_name,
            path: href,
            is_directory: self.is_directory,
            size,
            last_modified,
        })
    }
}

fn name_eq(name: LocalName<'_>, expected: &[u8]) -> bool {
    name.as_ref().eq_ignore_ascii_case(expected)
}

fn is_video_file(name: &str) -> bool {
    let Some((_, extension)) = name.rsplit_once('.') else {
        return false;
    };
    matches!(
        extension.to_ascii_lowercase().as_str(),
        "mp4"
            | "mkv"
            | "avi"
            | "mov"
            | "wmv"
            | "flv"
            | "webm"
            | "m4v"
            | "com"
            | "cn"
            | "org"
            | "net"
            | "me"
            | "cc"
            | "tv"
            | "co"
            | "xyz"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    const XML: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/show/</D:href>
    <D:propstat><D:prop><D:displayname>show</D:displayname><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/show/Season%202/</D:href>
    <D:propstat><D:prop><D:displayname></D:displayname><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/show/Episode%202.mkv</D:href>
    <D:propstat><D:prop><D:displayname>Episode 2 &amp; OVA.mkv</D:displayname><D:getcontentlength>1234</D:getcontentlength><D:getlastmodified>Sat, 23 Aug 2026 12:00:00 GMT</D:getlastmodified><D:resourcetype/></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/show/readme.txt</D:href>
    <D:propstat><D:prop><D:displayname>readme.txt</D:displayname><D:getcontentlength>12</D:getcontentlength><D:resourcetype/></D:prop></D:propstat>
  </D:response>
</D:multistatus>"#;

    #[test]
    fn parses_namespaces_entities_metadata_and_video_filter() {
        let entries = parse_webdav_multistatus(XML.into(), "/dav/show/".into(), false)
            .expect("valid multistatus");
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].name, "Season 2");
        assert!(entries[0].is_directory);
        assert_eq!(entries[1].name, "Episode 2 & OVA.mkv");
        assert_eq!(entries[1].size, Some(1234));
        assert_eq!(
            entries[1].last_modified.as_deref(),
            Some("Sat, 23 Aug 2026 12:00:00 GMT")
        );
    }

    #[test]
    fn include_all_files_keeps_non_video_entries() {
        let entries = parse_webdav_multistatus(XML.into(), "/dav/show/".into(), true)
            .expect("valid multistatus");
        assert_eq!(entries.len(), 3);
        assert_eq!(entries[2].name, "readme.txt");
    }

    #[test]
    fn rejects_malformed_xml() {
        assert!(parse_webdav_multistatus("<D:response>".into(), "/".into(), true).is_err());
    }
}
