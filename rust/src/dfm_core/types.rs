/// Danmaku type-specific position computation.
/// Ported from R2LDanmaku, L2RDanmaku, FTDanmaku, FBDanmaku, SpecialDanmaku.

use crate::dfm_core::model::{DanmakuItem, DanmakuType, GlobalFlags, LinePath};

/// Layout result for a single danmaku item.
#[derive(Debug, Clone)]
pub struct LayoutResult {
    pub x: f32,
    pub y: f32,
    pub is_shown: bool,
}

/// Compute the X position for a danmaku at a given time.
pub fn get_x_at_time(item: &DanmakuItem, view_width: f32, time_ms: i64, flags: &GlobalFlags) -> f32 {
    match item.danmaku_type {
        DanmakuType::ScrollRL => get_r2l_x(item, view_width, time_ms, flags),
        DanmakuType::ScrollLR => get_l2r_x(item, view_width, time_ms, flags),
        DanmakuType::FixTop | DanmakuType::FixBottom => get_fixed_x(item, view_width),
        DanmakuType::Special => get_special_x(item, view_width, time_ms, flags),
    }
}

/// R2L: x = view_width - elapsed * step_x
/// Ported from R2LDanmaku.getAccurateLeft().
fn get_r2l_x(item: &DanmakuItem, view_width: f32, time_ms: i64, flags: &GlobalFlags) -> f32 {
    let actual_time = item.get_actual_time(flags);
    let elapsed = time_ms - actual_time;
    if elapsed >= item.duration_ms {
        -item.paint_width
    } else {
        view_width - elapsed as f32 * item.step_x
    }
}

/// L2R: x = step_x * elapsed - paint_width
/// Ported from L2RDanmaku.getAccurateLeft().
fn get_l2r_x(item: &DanmakuItem, view_width: f32, time_ms: i64, flags: &GlobalFlags) -> f32 {
    let actual_time = item.get_actual_time(flags);
    let elapsed = time_ms - actual_time;
    if elapsed >= item.duration_ms {
        view_width
    } else {
        elapsed as f32 * item.step_x - item.paint_width
    }
}

/// FT/FB: centered horizontally.
/// Ported from FTDanmaku.getLeft().
fn get_fixed_x(item: &DanmakuItem, view_width: f32) -> f32 {
    (view_width - item.paint_width) / 2.0
}

/// Special: linear path interpolation with alpha.
/// Simplified port from SpecialDanmaku.getRectAtTime() — only linear path + alpha.
fn get_special_x(item: &DanmakuItem, _view_width: f32, time_ms: i64, flags: &GlobalFlags) -> f32 {
    let actual_time = item.get_actual_time(flags);
    let elapsed = (time_ms - actual_time).max(0) as f32;

    let Some(ref paths) = item.line_paths else {
        return item.x;
    };

    let progress = if item.duration_ms > 0 {
        elapsed / item.duration_ms as f32
    } else {
        1.0
    }.clamp(0.0, 1.0);

    interpolate_path_x(paths, progress, item.x)
}

fn interpolate_path_x(paths: &[LinePath], progress: f32, default_x: f32) -> f32 {
    let total_len: f32 = paths.iter().map(|p| path_length(p)).sum();
    if total_len <= 0.0 {
        return default_x;
    }

    let target_dist = progress * total_len;
    let mut accumulated = 0.0f32;
    for path in paths {
        let seg_len = path_length(path);
        if accumulated + seg_len >= target_dist {
            let seg_progress = if seg_len > 0.0 {
                (target_dist - accumulated) / seg_len
            } else {
                0.0
            };
            return path.begin_x + (path.end_x - path.begin_x) * seg_progress;
        }
        accumulated += seg_len;
    }
    paths.last().map_or(default_x, |p| p.end_x)
}

fn path_length(p: &LinePath) -> f32 {
    ((p.end_x - p.begin_x).powi(2) + (p.end_y - p.begin_y).powi(2)).sqrt()
}

/// Compute alpha for special danmaku at a given time.
pub fn get_special_alpha(item: &DanmakuItem, time_ms: i64, flags: &GlobalFlags) -> u8 {
    if item.alpha_duration_ms <= 0 || item.begin_alpha == item.end_alpha {
        return item.alpha;
    }
    let actual_time = item.get_actual_time(flags);
    let elapsed = (time_ms - actual_time).max(0) as f32;
    let progress = (elapsed / item.alpha_duration_ms as f32).clamp(0.0, 1.0);
    let delta = item.end_alpha as f32 - item.begin_alpha as f32;
    (item.begin_alpha as f32 + delta * progress) as u8
}

/// Layout a danmaku item: compute position and set visibility.
/// Ported from R2LDanmaku.layout().
pub fn layout_item(item: &mut DanmakuItem, view_width: f32, _x: f32, y: f32, timer_ms: i64, flags: &GlobalFlags) {
    let actual_time = item.get_actual_time(flags);
    let delta = timer_ms - actual_time;

    if delta > 0 && delta < item.duration_ms {
        item.x = get_x_at_time(item, view_width, timer_ms, flags);
        if !item.is_shown_state(flags) {
            item.y = y;
            item.is_shown = true;
            item.visible_flag = flags.visible_flag;
        }
        // Update alpha for special danmaku
        if item.danmaku_type == DanmakuType::Special {
            item.alpha = get_special_alpha(item, timer_ms, flags);
        }
    } else {
        item.is_shown = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dfm_core::model::DanmakuItem;

    #[test]
    fn test_r2l_x_at_start() {
        let flags = GlobalFlags::default();
        let mut item = DanmakuItem::new(0, "test".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
        item.measure(1920.0, 1080.0, &flags);
        let x = get_r2l_x(&item, 1920.0, 0, &flags);
        assert!((x - 1920.0).abs() < 1.0);
    }

    #[test]
    fn test_r2l_x_at_end() {
        let flags = GlobalFlags::default();
        let mut item = DanmakuItem::new(0, "test".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
        item.measure(1920.0, 1080.0, &flags);
        let x = get_r2l_x(&item, 1920.0, 5000, &flags);
        assert!(x <= 0.0);
    }

    #[test]
    fn test_l2r_x_at_start() {
        let flags = GlobalFlags::default();
        let mut item = DanmakuItem::new(0, "test".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollLR, 5000);
        item.measure(1920.0, 1080.0, &flags);
        let x = get_l2r_x(&item, 1920.0, 0, &flags);
        assert!(x <= 0.0); // starts offscreen left
    }

    #[test]
    fn test_fixed_centered() {
        let item = DanmakuItem {
            paint_width: 100.0,
            ..DanmakuItem::new(0, "test".into(), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800)
        };
        let x = get_fixed_x(&item, 1920.0);
        assert!((x - 910.0).abs() < 1.0); // (1920 - 100) / 2
    }
}
