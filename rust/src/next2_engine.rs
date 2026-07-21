pub(crate) mod engine;
pub mod ffi;

mod present;

/// Resolve the three user-facing outline levels to a safe MSDF width.
///
/// The setting is a profile selector, not a numeric width multiplier:
/// 0 = disabled, 1 = the current thin outline, 2 = the legacy thick outline.
/// Keeping the legacy profile at 1.5x leaves enough of the 6px MSDF distance
/// field around every glyph. Treating level 2 as a literal 2x multiplier can
/// expand the outline to 5.2px and fill the glyph quad as a solid rectangle.
pub(crate) fn resolve_danmaku_outline_px(font_size: f32, width_level: f32) -> f32 {
    if !width_level.is_finite() || width_level <= 0.0 {
        return 0.0;
    }

    let thin_px = (font_size * 0.06).clamp(1.0, 2.6);
    if width_level < 1.5 {
        thin_px
    } else {
        thin_px * 1.5
    }
}

#[cfg(test)]
mod outline_profile_tests {
    use super::resolve_danmaku_outline_px;

    #[test]
    fn outline_levels_use_safe_profiles_instead_of_literal_multipliers() {
        assert_eq!(resolve_danmaku_outline_px(40.0, 0.0), 0.0);
        assert!((resolve_danmaku_outline_px(40.0, 1.0) - 2.4).abs() < 0.0001);
        assert!((resolve_danmaku_outline_px(40.0, 2.0) - 3.6).abs() < 0.0001);

        let largest_legacy_outline = resolve_danmaku_outline_px(256.0, 2.0);
        assert!((largest_legacy_outline - 3.9).abs() < 0.0001);
        assert!(largest_legacy_outline < 6.0);
    }

    #[test]
    fn invalid_outline_levels_disable_the_outline() {
        assert_eq!(resolve_danmaku_outline_px(40.0, f32::NAN), 0.0);
        assert_eq!(resolve_danmaku_outline_px(40.0, f32::INFINITY), 0.0);
        assert_eq!(resolve_danmaku_outline_px(40.0, -1.0), 0.0);
    }
}
