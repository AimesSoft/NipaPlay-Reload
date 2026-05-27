/// Standalone font measurer using the same font chain and advance computation
/// as Next2's GPU glyph atlas. Ensures collision detection widths match rendering widths exactly.
///
/// Key: uses `face.glyph_hor_advance(glyph_id)` — the same metric the GPU renderer uses
/// for `cursor_x += entry.advance`. No heuristic, no approximation.

use std::collections::HashSet;
use ttf_parser::Face;

const FALLBACK_GLYPH_ADVANCE_RATIO: f32 = 0.58;
const MISSING_GLYPH_FALLBACK: char = '□';
const MAX_FONT_COLLECTION_FACES: u32 = 32;

static FONT_DATA: &[u8] = include_bytes!("../../../assets/subfont.ttf");
static NEXT2_FALLBACK_FONTS: &[&[u8]] = &[
    include_bytes!("../../assets/next2_fonts/NotoSansYi-Regular.ttf"),
    include_bytes!("../../assets/next2_fonts/NotoSansGeorgian-Regular.ttf"),
    include_bytes!("../../assets/next2_fonts/NotoSansLao-Regular.ttf"),
];

struct FontEntry {
    face: Face<'static>,
}

pub struct FontMeasurer {
    fonts: Vec<FontEntry>,
}

impl FontMeasurer {
    /// Create a new measurer with the same font chain as the GPU atlas.
    /// `custom_font_bytes`: optional custom font file contents (loaded from Dart side).
    pub fn new(custom_font_bytes: Option<Vec<u8>>) -> Result<Self, String> {
        let mut fonts = Vec::new();
        let mut seen = HashSet::new();

        // 1. Custom font (highest priority)
        if let Some(bytes) = custom_font_bytes {
            let boxed = bytes.into_boxed_slice();
            load_faces(boxed, &mut seen, &mut fonts)?;
        }

        // 2. Primary embedded font (subfont.ttf)
        load_faces(FONT_DATA.to_vec().into_boxed_slice(), &mut seen, &mut fonts)?;

        // 3. Fallback fonts
        for bytes in NEXT2_FALLBACK_FONTS {
            let boxed = (*bytes).to_vec().into_boxed_slice();
            let _ = load_faces(boxed, &mut seen, &mut fonts);
        }

        if fonts.is_empty() {
            return Err("measure: no usable font faces loaded".to_string());
        }

        Ok(Self { fonts })
    }

    /// Measure the rendered width of a string at the given font size.
    /// Uses the exact same advance computation as the GPU atlas:
    /// `glyph_hor_advance` → `scale_to_px` → `max(px * 0.58)`
    pub fn measure_width(&self, text: &str, font_size: f32) -> f32 {
        let mut width = 0.0f32;
        for ch in text.chars() {
            width += self.advance_for_char(ch, font_size);
        }
        width.max(1.0)
    }

    fn advance_for_char(&self, ch: char, px: f32) -> f32 {
        let resolved = self.resolve_char(ch);
        for font in &self.fonts {
            if let Some(glyph_id) = font.face.glyph_index(resolved) {
                let advance_units = font
                    .face
                    .glyph_hor_advance(glyph_id)
                    .map(|v| v as f32)
                    .unwrap_or_else(|| {
                        font.face.units_per_em() as f32 * FALLBACK_GLYPH_ADVANCE_RATIO
                    });
                let advance = scale_to_px(advance_units, &font.face, px)
                    .max(px * FALLBACK_GLYPH_ADVANCE_RATIO);
                return advance;
            }
        }
        // No font has this glyph — use fallback advance
        px * FALLBACK_GLYPH_ADVANCE_RATIO
    }

    fn resolve_char(&self, ch: char) -> char {
        if self.has_glyph(ch) {
            return ch;
        }
        if ch != MISSING_GLYPH_FALLBACK && self.has_glyph(MISSING_GLYPH_FALLBACK) {
            return MISSING_GLYPH_FALLBACK;
        }
        if self.has_glyph('?') {
            return '?';
        }
        ch
    }

    fn has_glyph(&self, ch: char) -> bool {
        self.fonts
            .iter()
            .any(|font| font.face.glyph_index(ch).is_some())
    }

    /// Compute the line ascent matching the GPU renderer's `line_ascent()`:
    /// `max(px * 0.82, max_face_ascender)`.
    pub fn line_ascent(&self, font_size: f32) -> f32 {
        let mut ascent = (font_size * 0.82).max(1.0);
        for font in &self.fonts {
            let face_ascent = scale_to_px(font.face.ascender() as f32, &font.face, font_size);
            ascent = ascent.max(face_ascent);
        }
        ascent
    }

    /// Compute the line descent: `max_face_descender` (absolute value).
    pub fn line_descent(&self, font_size: f32) -> f32 {
        let mut descent = 0.0f32;
        for font in &self.fonts {
            let d = scale_to_px(font.face.descender().abs() as f32, &font.face, font_size);
            descent = descent.max(d);
        }
        descent
    }

    /// Total line height = ascent + descent (matching font metrics, not heuristic).
    pub fn line_height(&self, font_size: f32) -> f32 {
        self.line_ascent(font_size) + self.line_descent(font_size)
    }
}

fn scale_to_px(units: f32, face: &Face<'static>, px: f32) -> f32 {
    let units_per_em = face.units_per_em().max(1) as f32;
    units * (px / units_per_em)
}

fn load_faces(
    bytes: Box<[u8]>,
    seen: &mut HashSet<u64>,
    out: &mut Vec<FontEntry>,
) -> Result<(), String> {
    let leaked: &'static [u8] = Box::leak(bytes);
    let face_count = ttf_parser::fonts_in_collection(leaked).unwrap_or(1);
    let face_limit = face_count.max(1).min(MAX_FONT_COLLECTION_FACES);

    for collection_index in 0..face_limit {
        let face = match Face::parse(leaked, collection_index) {
            Ok(face) => face,
            Err(ttf_parser::FaceParsingError::FaceIndexOutOfBounds) => break,
            Err(_) => {
                if collection_index == 0 {
                    return Err("measure: parse face failed".to_string());
                }
                break;
            }
        };

        let hash = hash_font_bytes(leaked, collection_index);
        if seen.insert(hash) {
            out.push(FontEntry { face });
        }
    }

    Ok(())
}

fn hash_font_bytes(bytes: &[u8], index: u32) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    bytes.hash(&mut hasher);
    index.hash(&mut hasher);
    hasher.finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_measure_ascii() {
        let measurer = FontMeasurer::new(None).unwrap();
        let w = measurer.measure_width("Hello", 25.0);
        // Each ASCII char ≈ 25 * 0.58 = 14.5px minimum, so 5 chars ≈ 72.5+
        assert!(w > 50.0, "width {} too small for 'Hello'", w);
        assert!(w < 200.0, "width {} too large for 'Hello'", w);
    }

    #[test]
    fn test_measure_cjk() {
        let measurer = FontMeasurer::new(None).unwrap();
        let w_cjk = measurer.measure_width("你好世界", 25.0);
        let w_ascii = measurer.measure_width("Hello", 25.0);
        // CJK chars should be wider than ASCII
        assert!(
            w_cjk > w_ascii,
            "CJK ({}) should be wider than ASCII ({})",
            w_cjk,
            w_ascii
        );
    }

    #[test]
    fn test_consistency() {
        let measurer = FontMeasurer::new(None).unwrap();
        // Measuring the same text twice should give the same result
        let w1 = measurer.measure_width("test弹幕", 25.0);
        let w2 = measurer.measure_width("test弹幕", 25.0);
        assert!((w1 - w2).abs() < 0.001);
    }

    #[test]
    fn test_empty_string() {
        let measurer = FontMeasurer::new(None).unwrap();
        let w = measurer.measure_width("", 25.0);
        assert!((w - 1.0).abs() < 0.001, "empty string should return 1.0, got {}", w);
    }

    #[test]
    fn test_font_metrics() {
        let measurer = FontMeasurer::new(None).unwrap();
        let ascent = measurer.line_ascent(25.0);
        let descent = measurer.line_descent(25.0);
        let height = measurer.line_height(25.0);

        // ascent should be at least 0.82 * 25 = 20.5
        assert!(ascent >= 20.0, "ascent {} too small", ascent);
        // descent should be non-negative
        assert!(descent >= 0.0, "descent {} negative", descent);
        // height = ascent + descent
        assert!((height - (ascent + descent)).abs() < 0.01);
        // height should be reasonable (not 0, not larger than 2x font size)
        assert!(height > 10.0 && height < 60.0, "height {} out of range", height);

        println!("font_size=25: ascent={:.1}, descent={:.1}, height={:.1}", ascent, descent, height);
    }

    #[test]
    fn test_font_metrics_scale() {
        let measurer = FontMeasurer::new(None).unwrap();
        // Metrics should scale proportionally with font size
        let h25 = measurer.line_height(25.0);
        let h50 = measurer.line_height(50.0);
        let ratio = h50 / h25;
        assert!(ratio > 1.8 && ratio < 2.2,
            "height should scale linearly: h25={}, h50={}, ratio={}", h25, h50, ratio);
    }
}
