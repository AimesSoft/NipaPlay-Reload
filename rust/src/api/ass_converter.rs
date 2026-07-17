use std::cmp::Ordering;
use std::fmt::Write;

const DEFAULT_PLAY_RES_X: i32 = 1920;
const DEFAULT_PLAY_RES_Y: i32 = 1080;
const FIXED_DURATION_SECONDS: f64 = 5.0;

#[derive(Clone, Debug)]
pub struct RustAssExportSettings {
    pub font_size: f64,
    pub opacity: f64,
    pub display_area: f64,
    pub scroll_duration_seconds: f64,
    pub time_offset_seconds: f64,
    pub merge_duplicates: bool,
    pub font_family: Option<String>,
    /// 0 = none, 1 = stroke, 2 = uniform.
    pub outline_style: i32,
    pub outline_width: f64,
    /// 0 = none, 1 = soft, 2 = medium, 3 = strong.
    pub shadow_style: i32,
}

#[derive(Clone, Debug)]
pub struct RustAssDanmakuInput {
    pub time_seconds: f64,
    pub content: String,
    /// Bilibili/DandanPlay mode: 1/6/7 scroll, 4 bottom, 5 top.
    pub type_code: i32,
    pub color_rgb: i32,
}

#[derive(Clone, Debug)]
pub struct RustPreparedDanmakuInput {
    pub time_seconds: f64,
    pub text: String,
    pub type_code: i32,
    pub color_rgb: i32,
    pub y_position: f64,
    pub width: f64,
    pub duration_seconds: f64,
    pub is_scroll: bool,
    pub is_filtered: bool,
}

#[derive(Clone, Debug)]
pub struct RustAssEvent {
    pub content: String,
    pub start_seconds: f64,
    pub end_seconds: f64,
    pub color_rgb: i32,
    /// Normalized mode: 1 scroll, 4 bottom, 5 top.
    pub type_code: i32,
}

#[derive(Clone, Debug)]
pub struct RustAssConversionResult {
    pub ass: String,
    pub events: Vec<RustAssEvent>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Kind {
    Scroll,
    Top,
    Bottom,
}

#[derive(Clone, Debug)]
struct ParsedDanmaku {
    content: String,
    time: f64,
    kind: Kind,
    color: i32,
}

#[flutter_rust_bridge::frb(sync)]
pub fn ass_resolve_font_size(in_app_font_size: f64) -> f64 {
    (in_app_font_size * 1.6).clamp(18.0, 96.0)
}

#[flutter_rust_bridge::frb(sync)]
pub fn convert_danmaku_to_ass(
    items: Vec<RustAssDanmakuInput>,
    settings: RustAssExportSettings,
) -> RustAssConversionResult {
    let ass_font_size = ass_resolve_font_size(settings.font_size);
    let lane_height = ((ass_font_size * 1.3).round() as i32).clamp(1, DEFAULT_PLAY_RES_Y);
    let lane_count = (((DEFAULT_PLAY_RES_Y as f64 * settings.display_area) / lane_height as f64)
        .floor() as i32)
        .clamp(1, 64) as usize;

    let mut ass = String::new();
    write_header(
        &mut ass,
        ass_font_size,
        &settings,
        DEFAULT_PLAY_RES_X,
        DEFAULT_PLAY_RES_Y,
    );

    let mut parsed: Vec<ParsedDanmaku> = items
        .into_iter()
        .filter_map(|item| {
            if item.content.is_empty() {
                return None;
            }
            let time = item.time_seconds + settings.time_offset_seconds;
            if time < 0.0 {
                return None;
            }
            Some(ParsedDanmaku {
                content: item.content,
                time,
                kind: kind_from_code(item.type_code),
                color: item.color_rgb & 0x00ff_ffff,
            })
        })
        .collect();
    parsed.sort_by(|a, b| a.time.partial_cmp(&b.time).unwrap_or(Ordering::Equal));
    if settings.merge_duplicates {
        parsed = merge_duplicates(parsed);
    }

    let mut scroll_lanes = vec![None; lane_count];
    let mut top_lanes = vec![None; lane_count];
    let mut bottom_lanes = vec![None; lane_count];
    let mut events = Vec::new();

    ass.push_str("[Events]\n");
    ass.push_str(
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n",
    );

    for item in parsed {
        let width = estimate_width(&item.content, ass_font_size);
        let alpha = alpha_hex(settings.opacity);
        let color = color_override(item.color);
        let outline = outline_color_override(item.color);
        let escaped = escape_ass_text(&item.content);

        match item.kind {
            Kind::Scroll => {
                let duration = positive_or(settings.scroll_duration_seconds, 10.0);
                let lane = pick_scroll_lane(&mut scroll_lanes, item.time, width, duration);
                let Some(lane) = lane else { continue };
                let y = lane as f64 * lane_height as f64 + lane_height as f64 / 2.0;
                let text = format!(
                    "{{\\an4\\move({},{:.1},{:.1},{:.1}){}{}\\1a{}}}{}",
                    DEFAULT_PLAY_RES_X, y, -width, y, color, outline, alpha, escaped
                );
                write_dialogue(
                    &mut ass,
                    0,
                    item.time,
                    item.time + duration,
                    "Danmaku",
                    &text,
                );
                events.push(make_event(&item, item.time + duration));
            }
            Kind::Top => {
                let lane = pick_fixed_lane(&mut top_lanes, item.time, FIXED_DURATION_SECONDS);
                let y = lane as f64 * lane_height as f64 + 2.0;
                let text = format!(
                    "{{\\an8\\pos({},{:.1}){}{}\\1a{}}}{}",
                    DEFAULT_PLAY_RES_X / 2,
                    y,
                    color,
                    outline,
                    alpha,
                    escaped
                );
                write_dialogue(
                    &mut ass,
                    1,
                    item.time,
                    item.time + FIXED_DURATION_SECONDS,
                    "DanmakuTop",
                    &text,
                );
                events.push(make_event(&item, item.time + FIXED_DURATION_SECONDS));
            }
            Kind::Bottom => {
                let lane = pick_fixed_lane(&mut bottom_lanes, item.time, FIXED_DURATION_SECONDS);
                let y = DEFAULT_PLAY_RES_Y as f64 - lane as f64 * lane_height as f64 - 2.0;
                let text = format!(
                    "{{\\an2\\pos({},{:.1}){}{}\\1a{}}}{}",
                    DEFAULT_PLAY_RES_X / 2,
                    y,
                    color,
                    outline,
                    alpha,
                    escaped
                );
                write_dialogue(
                    &mut ass,
                    2,
                    item.time,
                    item.time + FIXED_DURATION_SECONDS,
                    "DanmakuBottom",
                    &text,
                );
                events.push(make_event(&item, item.time + FIXED_DURATION_SECONDS));
            }
        }
    }

    RustAssConversionResult { ass, events }
}

#[flutter_rust_bridge::frb(sync)]
pub fn convert_prepared_danmaku_to_ass(
    items: Vec<RustPreparedDanmakuInput>,
    play_res_x: i32,
    play_res_y: i32,
    settings: RustAssExportSettings,
) -> RustAssConversionResult {
    let ass_font_size = ass_resolve_font_size(settings.font_size);
    let mut ass = String::new();
    write_header(&mut ass, ass_font_size, &settings, play_res_x, play_res_y);
    ass.push_str("[Events]\n");
    ass.push_str(
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n",
    );

    let alpha = alpha_hex(settings.opacity);
    let center_x = format!("{:.1}", play_res_x as f64 / 2.0);
    let mut events = Vec::new();

    for item in items {
        if item.is_filtered || item.text.is_empty() {
            continue;
        }
        let start = item.time_seconds + settings.time_offset_seconds;
        if start < 0.0 {
            continue;
        }
        let duration = positive_or(
            item.duration_seconds,
            if item.is_scroll {
                10.0
            } else {
                FIXED_DURATION_SECONDS
            },
        );
        let end = start + duration;
        let color = color_override(item.color_rgb);
        let outline = outline_color_override(item.color_rgb);
        let escaped = escape_ass_text(&item.text);
        let y = format!("{:.1}", item.y_position);

        let (layer, style, kind, text) = if item.is_scroll {
            let (x1, x2) = if item.type_code == 6 {
                (format!("{:.1}", -item.width), play_res_x.to_string())
            } else {
                (play_res_x.to_string(), format!("{:.1}", -item.width))
            };
            (
                0,
                "Danmaku",
                Kind::Scroll,
                format!(
                    "{{\\an7\\move({},{},{},{}){}{}\\1a{}}}{}",
                    x1, y, x2, y, color, outline, alpha, escaped
                ),
            )
        } else if item.type_code == 4 {
            (
                2,
                "DanmakuBottom",
                Kind::Bottom,
                format!(
                    "{{\\an8\\pos({},{}){}{}\\1a{}}}{}",
                    center_x, y, color, outline, alpha, escaped
                ),
            )
        } else {
            (
                1,
                "DanmakuTop",
                Kind::Top,
                format!(
                    "{{\\an8\\pos({},{}){}{}\\1a{}}}{}",
                    center_x, y, color, outline, alpha, escaped
                ),
            )
        };

        write_dialogue(&mut ass, layer, start, end, style, &text);
        events.push(RustAssEvent {
            content: item.text,
            start_seconds: start,
            end_seconds: end,
            color_rgb: item.color_rgb & 0x00ff_ffff,
            type_code: kind_code(kind),
        });
    }

    RustAssConversionResult { ass, events }
}

fn positive_or(value: f64, fallback: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        value
    } else {
        fallback
    }
}

fn kind_from_code(code: i32) -> Kind {
    match code {
        4 => Kind::Bottom,
        5 => Kind::Top,
        _ => Kind::Scroll,
    }
}

fn kind_code(kind: Kind) -> i32 {
    match kind {
        Kind::Scroll => 1,
        Kind::Bottom => 4,
        Kind::Top => 5,
    }
}

fn make_event(item: &ParsedDanmaku, end_seconds: f64) -> RustAssEvent {
    RustAssEvent {
        content: item.content.clone(),
        start_seconds: item.time,
        end_seconds,
        color_rgb: item.color,
        type_code: kind_code(item.kind),
    }
}

fn merge_duplicates(items: Vec<ParsedDanmaku>) -> Vec<ParsedDanmaku> {
    let mut result = Vec::with_capacity(items.len());
    let mut last_content: Option<String> = None;
    let mut last_time: Option<f64> = None;
    for item in items {
        if last_content.as_deref() == Some(item.content.as_str())
            && last_time.is_some_and(|time| (item.time - time).abs() < 3.0)
        {
            continue;
        }
        last_content = Some(item.content.clone());
        last_time = Some(item.time);
        result.push(item);
    }
    result
}

fn estimate_width(content: &str, font_size: f64) -> f64 {
    if content.is_empty() {
        return font_size;
    }
    content.encode_utf16().fold(0.0, |width, code| {
        let wide = code >= 0x1100
            && (code <= 0x115f
                || (0x2e80..=0xa4cf).contains(&code)
                || (0xac00..=0xd7a3).contains(&code)
                || (0xf900..=0xfaff).contains(&code)
                || (0xfe30..=0xfe4f).contains(&code)
                || (0xff00..=0xff60).contains(&code)
                || (0xffe0..=0xffe6).contains(&code));
        width + if wide { font_size } else { font_size * 0.6 }
    })
}

fn pick_scroll_lane(
    lanes: &mut [Option<f64>],
    time: f64,
    width: f64,
    duration: f64,
) -> Option<usize> {
    for (index, free_at) in lanes.iter_mut().enumerate() {
        if free_at.is_none_or(|value| time >= value) {
            let velocity = (DEFAULT_PLAY_RES_X as f64 + width) / duration;
            *free_at = Some(if velocity <= 0.0 {
                time + duration
            } else {
                time + width / velocity
            });
            return Some(index);
        }
    }
    None
}

fn pick_fixed_lane(lanes: &mut [Option<f64>], time: f64, duration: f64) -> usize {
    let mut earliest = 0usize;
    let mut earliest_free_at = f64::INFINITY;
    for (index, free_at) in lanes.iter_mut().enumerate() {
        if free_at.is_none_or(|value| time >= value) {
            *free_at = Some(time + duration);
            return index;
        }
        if let Some(value) = *free_at {
            if value < earliest_free_at {
                earliest = index;
                earliest_free_at = value;
            }
        }
    }
    lanes[earliest] = Some(earliest_free_at + duration);
    earliest
}

fn alpha_hex(opacity: f64) -> String {
    let alpha = ((1.0 - opacity.clamp(0.0, 1.0)) * 255.0).round() as i32;
    format!("&H{:02X}&", alpha.clamp(0, 255))
}

fn color_override(rgb: i32) -> String {
    let rgb = rgb & 0x00ff_ffff;
    if rgb == 0x00ff_ffff {
        return String::new();
    }
    let r = (rgb >> 16) & 0xff;
    let g = (rgb >> 8) & 0xff;
    let b = rgb & 0xff;
    format!("\\c&H{:06X}&", (b << 16) | (g << 8) | r)
}

fn outline_color_override(rgb: i32) -> &'static str {
    let r = (rgb >> 16) & 0xff;
    let g = (rgb >> 8) & 0xff;
    let b = rgb & 0xff;
    if r <= 8 && g <= 8 && b <= 8 {
        "\\3c&HFFFFFF&"
    } else {
        ""
    }
}

fn escape_ass_text(text: &str) -> String {
    text.replace('\\', "\\\\")
        .replace('{', "\\{")
        .replace('}', "\\}")
        .replace('\n', "\\N")
        .replace('\r', "")
}

fn format_ass_time(seconds: f64) -> String {
    let seconds = seconds.max(0.0);
    let total_cs = (seconds * 100.0).round() as i64;
    let cs = total_cs % 100;
    let total_seconds = total_cs / 100;
    let second = total_seconds % 60;
    let minute = (total_seconds / 60) % 60;
    let hour = total_seconds / 3600;
    format!("{}:{:02}:{:02}.{:02}", hour, minute, second, cs)
}

fn write_dialogue(output: &mut String, layer: i32, start: f64, end: f64, style: &str, text: &str) {
    let _ = writeln!(
        output,
        "Dialogue: {},{},{},{},,0,0,0,,{}",
        layer,
        format_ass_time(start),
        format_ass_time(end),
        style,
        text
    );
}

fn write_header(
    output: &mut String,
    font_size: f64,
    settings: &RustAssExportSettings,
    play_res_x: i32,
    play_res_y: i32,
) {
    let font_name = settings
        .font_family
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("Microsoft YaHei");
    let (outline, border_style) = match settings.outline_style {
        0 => ("0.0".to_string(), "1"),
        2 => (
            format!("{:.1}", (settings.outline_width * 1.5).clamp(0.0, 8.0)),
            "1",
        ),
        _ => (
            format!("{:.1}", settings.outline_width.clamp(0.0, 8.0)),
            "1",
        ),
    };
    let (shadow, back_color) = match settings.shadow_style {
        1 => ("1.0", "&HA8000000"),
        2 => ("1.5", "&H8F000000"),
        3 => ("2.0", "&H73000000"),
        _ => ("0.0", "&H00000000"),
    };

    let _ = writeln!(output, "[Script Info]");
    let _ = writeln!(output, "; Generated by NipaPlay external danmaku overlay");
    let _ = writeln!(output, "ScriptType: v4.00+");
    let _ = writeln!(output, "PlayResX: {play_res_x}");
    let _ = writeln!(output, "PlayResY: {play_res_y}");
    let _ = writeln!(output, "Aspect Ratio: 16:9");
    let _ = writeln!(output, "WrapStyle: 2");
    let _ = writeln!(output, "ScaledBorderAndShadow: yes");
    let _ = writeln!(output, "YCbCr Matrix: TV.709\n");
    let _ = writeln!(output, "[V4+ Styles]");
    let _ = writeln!(
        output,
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding"
    );
    for (name, alignment) in [("Danmaku", 2), ("DanmakuTop", 8), ("DanmakuBottom", 2)] {
        let _ = writeln!(
            output,
            "Style: {},{},{:.1},&H00FFFFFF,&H00FFFFFF,&H00000000,{},0,0,0,0,100,100,0,0,{},{},{},{},0,0,0,1",
            name, font_name, font_size, back_color, border_style, outline, shadow, alignment
        );
    }
    output.push('\n');
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings() -> RustAssExportSettings {
        RustAssExportSettings {
            font_size: 24.0,
            opacity: 1.0,
            display_area: 1.0,
            scroll_duration_seconds: 8.0,
            time_offset_seconds: 1.0,
            merge_duplicates: false,
            font_family: None,
            outline_style: 1,
            outline_width: 1.0,
            shadow_style: 0,
        }
    }

    #[test]
    fn produces_classic_events() {
        let result = convert_danmaku_to_ass(
            vec![
                RustAssDanmakuInput {
                    time_seconds: 1.0,
                    content: "scroll".into(),
                    type_code: 1,
                    color_rgb: 0xff0000,
                },
                RustAssDanmakuInput {
                    time_seconds: 2.0,
                    content: "top".into(),
                    type_code: 5,
                    color_rgb: 0x00ff00,
                },
            ],
            settings(),
        );
        assert_eq!(result.events.len(), 2);
        assert_eq!(result.events[0].start_seconds, 2.0);
        assert_eq!(result.events[0].end_seconds, 10.0);
        assert_eq!(result.events[1].type_code, 5);
        assert_eq!(result.ass.matches("Dialogue:").count(), 2);
        assert!(result.ass.contains("\\move(1920,25.0,-138.2,25.0)"));
    }
}
