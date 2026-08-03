pub fn with_cached_measurer<F, R>(_custom_font_bytes: Option<Vec<u8>>, f: F) -> Result<R, String>
where
    F: FnOnce(HeuristicMeasurer) -> R,
{
    Ok(f(HeuristicMeasurer))
}

pub struct HeuristicMeasurer;

impl HeuristicMeasurer {
    pub fn measure_width(&self, text: &str, font_size: f32) -> f32 {
        measure_text_width_heuristic(text, font_size)
    }

    pub fn line_ascent(&self, font_size: f32) -> f32 {
        font_size * 0.9
    }

    pub fn line_descent(&self, font_size: f32) -> f32 {
        font_size * 0.3
    }

    pub fn line_height(&self, font_size: f32) -> f32 {
        measure_line_height_heuristic(font_size)
    }
}

pub fn measure_text_width_heuristic(text: &str, font_size: f32) -> f32 {
    crate::dfm_core::model::measure_text_width(text, font_size)
}

const FALLBACK_GLYPH_ADVANCE_RATIO: f32 = 0.58;
const MAX_FONT_COLLECTION_FACES: u32 = 32;

/// Measure plain-text runs with the same font order and horizontal advances
/// as the Next2 GPU glyph atlas. Emoji runs are deliberately measured on the
/// Dart side, where Flutter resolves color-emoji grapheme clusters.
pub fn measure_text_widths_exact(
    texts: &[String],
    font_size: f32,
    custom_font_bytes: Option<&[u8]>,
) -> Result<Vec<f32>, String> {
    use ttf_parser::{Face, GlyphId};

    fn append_faces<'a>(bytes: &'a [u8], faces: &mut Vec<Face<'a>>) -> Result<(), String> {
        let face_count = ttf_parser::fonts_in_collection(bytes).unwrap_or(1);
        let face_limit = face_count.max(1).min(MAX_FONT_COLLECTION_FACES);
        for index in 0..face_limit {
            match Face::parse(bytes, index) {
                Ok(face) => faces.push(face),
                Err(ttf_parser::FaceParsingError::FaceIndexOutOfBounds) => break,
                Err(err) if index == 0 => {
                    return Err(format!("parse font face failed: {err:?}"));
                }
                Err(_) => break,
            }
        }
        Ok(())
    }

    fn find_glyph<'faces, 'data>(
        faces: &'faces [Face<'data>],
        ch: char,
    ) -> Option<(&'faces Face<'data>, GlyphId)> {
        faces
            .iter()
            .find_map(|face| face.glyph_index(ch).map(|glyph_id| (face, glyph_id)))
    }

    let mut faces = Vec::new();
    if let Some(bytes) = custom_font_bytes.filter(|bytes| !bytes.is_empty()) {
        append_faces(bytes, &mut faces)?;
    }
    append_faces(crate::next2_engine::DEFAULT_FONT_DATA, &mut faces)?;
    for bytes in crate::next2_engine::FALLBACK_FONT_DATA {
        append_faces(bytes, &mut faces)?;
    }
    if faces.is_empty() {
        return Err("no usable font faces for text measurement".to_string());
    }

    let px = if font_size.is_finite() {
        font_size.max(1.0)
    } else {
        1.0
    };
    Ok(texts
        .iter()
        .map(|text| {
            text.chars()
                .map(|ch| {
                    let resolved = find_glyph(&faces, ch)
                        .or_else(|| find_glyph(&faces, '□'))
                        .or_else(|| find_glyph(&faces, '?'));
                    let Some((face, glyph_id)) = resolved else {
                        return px * FALLBACK_GLYPH_ADVANCE_RATIO;
                    };
                    face.glyph_hor_advance(glyph_id)
                        .map(|units| units as f32 * (px / face.units_per_em().max(1) as f32))
                        .filter(|advance| advance.is_finite() && *advance >= 0.0)
                        .unwrap_or(px * FALLBACK_GLYPH_ADVANCE_RATIO)
                })
                .sum::<f32>()
                .max(1.0)
        })
        .collect())
}

pub fn measure_line_height_heuristic(font_size: f32) -> f32 {
    font_size * 1.2
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_measure_ascii() {
        let w = measure_text_width_heuristic("Hello", 25.0);
        assert!(w > 50.0, "width {} too small for 'Hello'", w);
        assert!(w < 200.0, "width {} too large for 'Hello'", w);
    }

    #[test]
    fn exact_measurement_preserves_narrow_latin_advances() {
        let widths = measure_text_widths_exact(&["j".into(), "o".into()], 50.0, None)
            .expect("measure embedded font");
        assert!(
            widths[0] < widths[1] * 0.6,
            "j={} should remain substantially narrower than o={}",
            widths[0],
            widths[1]
        );
    }

    #[test]
    fn test_measure_cjk() {
        let w_cjk = measure_text_width_heuristic("你好世界", 25.0);
        let w_ascii = measure_text_width_heuristic("Hello", 25.0);
        assert!(
            w_cjk > w_ascii,
            "CJK ({}) should be wider than ASCII ({})",
            w_cjk,
            w_ascii
        );
    }

    #[test]
    fn test_consistency() {
        let w1 = measure_text_width_heuristic("test弹幕", 25.0);
        let w2 = measure_text_width_heuristic("test弹幕", 25.0);
        assert!((w1 - w2).abs() < 0.001);
    }

    #[test]
    fn test_empty_string() {
        let w = measure_text_width_heuristic("", 25.0);
        assert!(
            (w - 1.0).abs() < 0.001,
            "empty string should return 1.0, got {}",
            w
        );
    }

    #[test]
    fn test_font_metrics() {
        let height = measure_line_height_heuristic(25.0);
        assert!(
            (height - 30.0).abs() < 0.001,
            "height should be 30.0, got {}",
            height
        );
    }

    #[test]
    fn test_font_metrics_scale() {
        let h25 = measure_line_height_heuristic(25.0);
        let h50 = measure_line_height_heuristic(50.0);
        let ratio = h50 / h25;
        assert!(
            (ratio - 2.0).abs() < 0.01,
            "ratio should be 2.0, got {}",
            ratio
        );
    }
}
