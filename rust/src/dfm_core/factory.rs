/// Duration computation and viewport scaling.
/// Ported from DanmakuFactory.java.
use crate::dfm_core::model::Duration;

/// Reference Bilibili player width for duration scaling.
const BILI_PLAYER_WIDTH: f32 = 682.0;
/// Base duration at reference resolution (ms).
const COMMON_DANMAKU_DURATION: f32 = 3800.0;
/// Minimum scroll duration (ms).
const MIN_DANMAKU_DURATION: f32 = 4000.0;
/// Maximum scroll duration (ms).
const MAX_DANMAKU_DURATION_HIGH_DENSITY: f32 = 9000.0;

/// Compute scroll duration based on viewport width and speed factor.
/// Ported from DanmakuFactory.updateViewportState().
pub fn compute_scroll_duration(viewport_width: f32, speed_factor: f32) -> i64 {
    let raw = COMMON_DANMAKU_DURATION * speed_factor * (viewport_width / BILI_PLAYER_WIDTH);
    raw.clamp(MIN_DANMAKU_DURATION, MAX_DANMAKU_DURATION_HIGH_DENSITY) as i64
}

/// Compute fixed danmaku duration.
pub fn compute_fixed_duration() -> i64 {
    COMMON_DANMAKU_DURATION as i64
}

/// Create a scroll Duration object with the given viewport and speed factor.
pub fn create_scroll_duration(viewport_width: f32, speed_factor: f32) -> Duration {
    Duration::new(compute_scroll_duration(viewport_width, speed_factor))
}

/// Create a fixed Duration object.
pub fn create_fixed_duration() -> Duration {
    Duration::new(compute_fixed_duration())
}

/// Compute the global maximum danmaku duration across all types.
pub fn compute_max_duration(scroll_duration: i64, special_durations: &[i64]) -> i64 {
    let mut max_dur = scroll_duration;
    max_dur = max_dur.max(COMMON_DANMAKU_DURATION as i64);
    max_dur = max_dur.max(compute_fixed_duration());
    for &d in special_durations {
        max_dur = max_dur.max(d);
    }
    max_dur
}

/// Compute scale factors for viewport changes (used by SpecialDanmaku).
pub fn compute_scale_factors(
    old_width: f32,
    old_height: f32,
    new_width: f32,
    new_height: f32,
) -> (f32, f32) {
    let sx = if old_width > 0.0 {
        new_width / old_width
    } else {
        1.0
    };
    let sy = if old_height > 0.0 {
        new_height / old_height
    } else {
        1.0
    };
    (sx, sy)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scroll_duration_at_reference() {
        let dur = compute_scroll_duration(682.0, 1.0);
        // 3800 * 1.0 * (682/682) = 3800, clamped to min 4000
        assert_eq!(dur, 4000);
    }

    #[test]
    fn test_scroll_duration_wider_viewport() {
        let dur = compute_scroll_duration(1920.0, 1.0);
        // 3800 * 1.0 * (1920/682) ≈ 10698, clamped to max 9000
        assert_eq!(dur, 9000);
    }

    #[test]
    fn test_scroll_duration_with_speed_factor() {
        let dur = compute_scroll_duration(682.0, 0.5);
        // 3800 * 0.5 * 1.0 = 1900, clamped to min 4000
        assert_eq!(dur, 4000);
    }

    #[test]
    fn test_max_duration() {
        let max = compute_max_duration(5000, &[3000, 7000]);
        assert_eq!(max, 7000);
    }
}
