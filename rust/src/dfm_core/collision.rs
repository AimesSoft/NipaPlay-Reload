/// Collision detection for danmaku layout.
/// Ported from DanmakuUtils.willHitInDuration() and checkHitAtTime().
/// Key improvement: each danmaku has independent speed based on its length.

use crate::dfm_core::model::{DanmakuItem, DanmakuType, GlobalFlags};

/// Check if two danmaku items will collide during their display duration.
/// Ported from DanmakuUtils.willHitInDuration().
/// Uses time-window overlap instead of curr_time_ms-based checks,
/// which works correctly for both real-time rendering and pre-computed layout.
pub fn will_hit_in_duration(
    d1: &DanmakuItem,
    d2: &DanmakuItem,
    view_width: f32,
    _curr_time_ms: i64,
    flags: &GlobalFlags,
) -> bool {
    let type1 = d1.danmaku_type;
    let type2 = d2.danmaku_type;

    // Different types never collide
    if type1 != type2 {
        return false;
    }

    let actual1 = d1.get_actual_time(flags);
    let actual2 = d2.get_actual_time(flags);
    let d_time = actual2 - actual1;

    // d2 starts at same time or before d1 → always collide
    // (same-start-time scroll items must use different rows)
    if d_time <= 0 {
        return true;
    }

    // Time gap exceeds d1's duration → no temporal overlap
    if d_time >= d1.duration_ms {
        return false;
    }

    // Fixed danmakus of same type always collide (they share vertical space)
    if type1 == DanmakuType::FixTop || type1 == DanmakuType::FixBottom {
        return true;
    }

    // For scroll types: check geometric overlap at two time points
    // Check at d2's start time (when d2 appears, d1 has already moved)
    // and at d1's end time (when d1 disappears)
    check_hit_at_time(d1, d2, view_width, actual2, flags)
        || check_hit_at_time(d1, d2, view_width, actual1 + d1.duration_ms, flags)
}

/// Check if two danmaku overlap geometrically at a specific time.
fn check_hit_at_time(
    d1: &DanmakuItem,
    d2: &DanmakuItem,
    view_width: f32,
    time_ms: i64,
    flags: &GlobalFlags,
) -> bool {
    let rect1 = d1.get_rect_at_time(view_width, time_ms, flags);
    let rect2 = d2.get_rect_at_time(view_width, time_ms, flags);
    check_hit(d1.danmaku_type, d2.danmaku_type, &rect1, &rect2)
}

/// Check if two rectangles overlap based on danmaku type.
/// Ported from DanmakuUtils.checkHit().
fn check_hit(type1: DanmakuType, type2: DanmakuType, rect1: &[f32; 4], rect2: &[f32; 4]) -> bool {
    if type1 != type2 {
        return false;
    }
    match type1 {
        DanmakuType::ScrollRL => {
            // R2L: hit if d2's left < d1's right
            rect2[0] < rect1[2]
        }
        DanmakuType::ScrollLR => {
            // L2R: hit if d2's right > d1's left
            rect2[2] > rect1[0]
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dfm_core::model::DanmakuItem;

    #[test]
    fn test_different_types_no_collision() {
        let flags = GlobalFlags::default();
        let d1 = DanmakuItem::new(0, "a".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
        let d2 = DanmakuItem::new(0, "b".into(), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800);
        assert!(!will_hit_in_duration(&d1, &d2, 1920.0, 0, &flags));
    }

    #[test]
    fn test_same_type_same_time_hit() {
        let flags = GlobalFlags::default();
        let mut d1 = DanmakuItem::new(0, "a".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
        let mut d2 = DanmakuItem::new(0, "b".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
        d1.measure(1920.0, 1080.0, &flags);
        d2.measure(1920.0, 1080.0, &flags);
        // Same start time, same duration → time windows overlap → geometric hit
        assert!(will_hit_in_duration(&d1, &d2, 1920.0, 0, &flags));
    }

    #[test]
    fn test_fixed_same_type_always_collide() {
        let flags = GlobalFlags::default();
        let d1 = DanmakuItem::new(0, "a".into(), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800);
        let d2 = DanmakuItem::new(1000, "b".into(), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800);
        assert!(will_hit_in_duration(&d1, &d2, 1920.0, 500, &flags));
    }

    #[test]
    fn test_far_apart_no_collision() {
        let flags = GlobalFlags::default();
        let d1 = DanmakuItem::new(0, "a".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
        let d2 = DanmakuItem::new(10000, "b".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
        // d2 starts 10s after d1, d1 duration is 5s → no collision
        assert!(!will_hit_in_duration(&d1, &d2, 1920.0, 0, &flags));
    }
}
