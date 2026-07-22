pub(crate) mod engine;
pub mod ffi;

mod present;

/// fdsm stores distances in `[-range / 2, range / 2]`, so this provides a
/// usable one-sided distance of 5px. The original 6px range only provided 3px
/// on each side, which cannot represent the 3.9px thick profile safely.
pub(crate) const DANMAKU_MSDF_RANGE: f64 = 10.0;

/// Resolve the three user-facing outline levels to a safe MSDF width.
///
/// The setting is a profile selector, not a numeric width multiplier:
/// 0 = disabled, 1 = the current thin outline, 2 = the legacy thick outline.
/// fdsm's range is two-sided. Keep a full pixel between the thick outline and
/// the one-sided distance limit so shader antialiasing cannot paint the outer
/// border of the glyph quad as a solid rectangle.
pub(crate) fn resolve_danmaku_outline_px(font_size: f32, width_level: f32) -> f32 {
    if !width_level.is_finite() || width_level <= 0.0 {
        return 0.0;
    }

    let thin_px = (font_size * 0.06).clamp(1.0, 2.6);
    if width_level < 1.5 {
        thin_px
    } else {
        let one_sided_range = DANMAKU_MSDF_RANGE as f32 * 0.5;
        (thin_px * 1.5).min(one_sided_range - 1.0)
    }
}

#[cfg(test)]
mod outline_profile_tests {
    use super::{resolve_danmaku_outline_px, DANMAKU_MSDF_RANGE};

    #[test]
    fn outline_levels_use_safe_profiles_instead_of_literal_multipliers() {
        assert_eq!(resolve_danmaku_outline_px(40.0, 0.0), 0.0);
        assert!((resolve_danmaku_outline_px(40.0, 1.0) - 2.4).abs() < 0.0001);
        assert!((resolve_danmaku_outline_px(40.0, 2.0) - 3.6).abs() < 0.0001);

        let largest_legacy_outline = resolve_danmaku_outline_px(256.0, 2.0);
        assert!((largest_legacy_outline - 3.9).abs() < 0.0001);
        assert!(largest_legacy_outline + 1.0 <= DANMAKU_MSDF_RANGE as f32 * 0.5);

        for font_size in [8.0, 20.0, 40.0, 50.0, 256.0] {
            let thin = resolve_danmaku_outline_px(font_size, 1.0);
            let thick = resolve_danmaku_outline_px(font_size, 2.0);
            assert!(
                thick >= thin * 1.45,
                "outline levels are not visually distinct at {font_size}px: thin={thin}, thick={thick}"
            );
        }
    }

    #[test]
    fn invalid_outline_levels_disable_the_outline() {
        assert_eq!(resolve_danmaku_outline_px(40.0, f32::NAN), 0.0);
        assert_eq!(resolve_danmaku_outline_px(40.0, f32::INFINITY), 0.0);
        assert_eq!(resolve_danmaku_outline_px(40.0, -1.0), 0.0);
    }
}
