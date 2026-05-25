#[derive(Deserialize)]
struct FramePayload {
    items: Vec<FrameItemPayload>,
    #[serde(default)]
    emoji_glyphs: Option<Vec<FrameEmojiGlyphPayload>>,
}

#[derive(Deserialize)]
struct FrameItemPayload {
    text: String,
    #[serde(default)]
    count_text: Option<String>,
    x: f64,
    y: f64,
    color_argb: i32,
    #[serde(default = "default_font_size_multiplier")]
    font_size_multiplier: f64,
    #[serde(default)]
    tokens: Option<Vec<FrameTokenPayload>>,
}

#[derive(Deserialize)]
struct FrameEmojiGlyphPayload {
    id: String,
    w: u32,
    h: u32,
    adv: f64,
    ox: f64,
    oy: f64,
    rgba_b64: String,
}

#[derive(Deserialize, Clone)]
struct FrameTokenPayload {
    k: String,
    #[serde(default)]
    t: Option<String>,
    #[serde(default)]
    id: Option<String>,
}

fn default_font_size_multiplier() -> f64 {
    1.0
}

#[derive(Clone)]
struct FrameItem {
    tokens: Vec<FrameToken>,
    x: f64,
    y: f64,
    color_argb: i32,
    font_size: f32,
    outline_width: f32,
    shadow_style: u8,
    opacity: f32,
}

#[derive(Clone)]
enum FrameToken {
    Text(String),
    Emoji(String),
}

fn normalize_tokens(
    tokens: Option<Vec<FrameTokenPayload>>,
    text: &str,
    count_text: Option<&str>,
) -> Vec<FrameToken> {
    if let Some(raw_tokens) = tokens {
        let mut out = Vec::with_capacity(raw_tokens.len());
        for token in raw_tokens {
            match token.k.as_str() {
                "e" => {
                    if let Some(id) = token.id {
                        if !id.is_empty() {
                            out.push(FrameToken::Emoji(id));
                        }
                    }
                }
                "t" => {
                    if let Some(t) = token.t {
                        if !t.is_empty() {
                            out.push(FrameToken::Text(t));
                        }
                    }
                }
                _ => {}
            }
        }
        if !out.is_empty() {
            return out;
        }
    }

    let mut fallback_text = text.to_string();
    if let Some(count_text) = count_text {
        if !count_text.is_empty() {
            fallback_text.push(' ');
            fallback_text.push_str(count_text);
        }
    }
    if fallback_text.is_empty() {
        Vec::new()
    } else {
        vec![FrameToken::Text(fallback_text)]
    }
}

fn decode_emoji_rasters(payloads: &[FrameEmojiGlyphPayload]) -> Vec<EmojiRasterData> {
    let mut out = Vec::with_capacity(payloads.len());
    for item in payloads {
        if item.id.is_empty() || item.w == 0 || item.h == 0 || item.rgba_b64.is_empty() {
            continue;
        }
        let Ok(rgba) = base64::engine::general_purpose::STANDARD.decode(item.rgba_b64.as_bytes())
        else {
            continue;
        };
        out.push(EmojiRasterData {
            id: item.id.clone(),
            width: item.w,
            height: item.h,
            advance: item.adv as f32,
            offset_x: item.ox as f32,
            offset_y: item.oy as f32,
            rgba,
        });
    }
    out
}

