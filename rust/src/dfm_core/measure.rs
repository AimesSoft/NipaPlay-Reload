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
    let mut width = 0.0f32;
    for ch in text.chars() {
        if ch == ' ' {
            width += font_size * 0.35;
        } else if ch.is_ascii() {
            width += font_size * 0.55;
        } else {
            width += font_size;
        }
    }
    width.max(1.0)
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
    fn test_measure_cjk() {
        let w_cjk = measure_text_width_heuristic("你好世界", 25.0);
        let w_ascii = measure_text_width_heuristic("Hello", 25.0);
        assert!(w_cjk > w_ascii, "CJK ({}) should be wider than ASCII ({})", w_cjk, w_ascii);
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
        assert!((w - 1.0).abs() < 0.001, "empty string should return 1.0, got {}", w);
    }

    #[test]
    fn test_font_metrics() {
        let height = measure_line_height_heuristic(25.0);
        assert!((height - 30.0).abs() < 0.001, "height should be 30.0, got {}", height);
    }

    #[test]
    fn test_font_metrics_scale() {
        let h25 = measure_line_height_heuristic(25.0);
        let h50 = measure_line_height_heuristic(50.0);
        let ratio = h50 / h25;
        assert!((ratio - 2.0).abs() < 0.01, "ratio should be 2.0, got {}", ratio);
    }
}
