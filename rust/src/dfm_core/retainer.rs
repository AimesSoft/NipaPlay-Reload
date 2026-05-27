/// Track-based collision avoidance layout engine.
/// Inspired by Next2's track + compaction approach for correct pre-computed layout.
///
/// Key design: per-type track arrays storing lightweight collision records,
/// compact expired items before each placement, assign to first non-colliding track,
/// compute Y from track index.

use crate::dfm_core::model::{DanmakuItem, DanmakuType, GlobalFlags};

/// Lightweight record stored in tracks for collision detection.
/// Avoids needing to look up items by index from an external array.
/// For fixed danmaku, `time_ms` is used as the track's END time (not start time),
/// so that Pass 1 can correctly check if a new danmaku starts after the track is free.
#[derive(Debug, Clone)]
struct TrackEntry {
    time_ms: i64,
    duration_ms: i64,
    paint_width: f32,
    danmaku_type: DanmakuType,
    danmaku_index: usize,
}

impl TrackEntry {
    fn from_item(item: &DanmakuItem, index: usize) -> Self {
        Self {
            time_ms: item.time_ms + item.duration_ms,
            duration_ms: item.duration_ms,
            paint_width: item.paint_width,
            danmaku_type: item.danmaku_type,
            danmaku_index: index,
        }
    }
}

/// Track-based collision avoidance engine.
#[derive(Debug, Clone)]
pub struct DanmakuRetainer {
    r2l_tracks: Vec<Vec<TrackEntry>>,
    lr_tracks: Vec<Vec<TrackEntry>>,
    top_tracks: Vec<Vec<TrackEntry>>,
    bottom_tracks: Vec<Vec<TrackEntry>>,
    margin: f32,
    track_gap_ratio: f32,
}

impl DanmakuRetainer {
    pub fn new(margin: f32, track_gap_ratio: f32) -> Self {
        Self {
            r2l_tracks: Vec::new(),
            lr_tracks: Vec::new(),
            top_tracks: Vec::new(),
            bottom_tracks: Vec::new(),
            margin,
            track_gap_ratio,
        }
    }

    pub fn clear(&mut self) {
        self.r2l_tracks.clear();
        self.lr_tracks.clear();
        self.top_tracks.clear();
        self.bottom_tracks.clear();
    }

    /// Assign a Y position to a danmaku item using track-based collision avoidance.
    /// Returns true if a position was found, false if the item should be dropped.
    /// Returns the index of any displaced danmaku (for fixed types) that should be marked as filtered.
    pub fn fix(
        &mut self,
        item: &mut DanmakuItem,
        view_width: f32,
        view_height: f32,
        flags: &GlobalFlags,
        display_area: f32,
    ) -> (bool, Option<usize>) {
        let effective_height = view_height * display_area;
        let track_height = item.paint_height + item.paint_height * self.track_gap_ratio;
        let track_count = (effective_height / track_height).floor().max(1.0) as usize;
        let danmaku_index = item.index as usize;

        let entry = TrackEntry::from_item(item, danmaku_index);

        match item.danmaku_type {
            DanmakuType::ScrollRL => {
                if self.r2l_tracks.len() != track_count {
                    self.r2l_tracks.resize_with(track_count, Vec::new);
                }
                match select_scroll_track(&entry, &mut self.r2l_tracks, track_count, view_width) {
                    Some(row) => {
                        item.y = self.margin + row as f32 * track_height;
                        item.is_shown = true;
                        item.visible_flag = flags.visible_flag;
                        (true, None)
                    }
                    None => (false, None),
                }
            }
            DanmakuType::ScrollLR => {
                if self.lr_tracks.len() != track_count {
                    self.lr_tracks.resize_with(track_count, Vec::new);
                }
                match select_scroll_track(&entry, &mut self.lr_tracks, track_count, view_width) {
                    Some(row) => {
                        item.y = self.margin + row as f32 * track_height;
                        item.is_shown = true;
                        item.visible_flag = flags.visible_flag;
                        (true, None)
                    }
                    None => (false, None),
                }
            }
            DanmakuType::FixTop => {
                if self.top_tracks.len() != track_count {
                    self.top_tracks.resize_with(track_count, Vec::new);
                }
                match select_fixed_track(&entry, &mut self.top_tracks, track_count) {
                    Some((row, was_queued, displaced_index)) => {
                        if was_queued {
                            let last = self.top_tracks[row].last().unwrap();
                            let new_start = last.time_ms - last.duration_ms;
                            item.time_ms = new_start;
                        }
                        item.y = self.margin + row as f32 * track_height;
                        item.is_shown = true;
                        item.visible_flag = flags.visible_flag;
                        (true, displaced_index)
                    }
                    None => (false, None),
                }
            }
            DanmakuType::FixBottom => {
                if self.bottom_tracks.len() != track_count {
                    self.bottom_tracks.resize_with(track_count, Vec::new);
                }
                match select_fixed_track(&entry, &mut self.bottom_tracks, track_count) {
                    Some((row, was_queued, displaced_index)) => {
                        if was_queued {
                            let last = self.bottom_tracks[row].last().unwrap();
                            let new_start = last.time_ms - last.duration_ms;
                            item.time_ms = new_start;
                        }
                        item.y = effective_height - (row as f32 + 1.0) * track_height;
                        item.is_shown = true;
                        item.visible_flag = flags.visible_flag;
                        (true, displaced_index)
                    }
                    None => (false, None),
                }
            }
            DanmakuType::Special => {
                item.y = 0.0;
                item.is_shown = true;
                item.visible_flag = flags.visible_flag;
                (true, None)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Track selection
// ---------------------------------------------------------------------------

/// Compact expired scroll entries from tracks.
fn compact_scroll_tracks(
    current_time_ms: i64,
    tracks: &mut [Vec<TrackEntry>],
    current_duration_ms: i64,
) {
    for track in tracks.iter_mut() {
        track.retain(|existing| {
            // Keep if time windows overlap
            (current_time_ms - existing.time_ms) <= current_duration_ms
                && (current_time_ms - existing.time_ms) >= -existing.duration_ms
        });
    }
}

/// Select a track for a scroll danmaku.
/// Returns the track index, or None if the item should be dropped.
/// When all tracks collide, uses overwrite strategy: replace the track
/// whose items have the smallest right edge (oldest items that have
/// moved furthest left), matching DFM's overwriteInsert behavior.
fn select_scroll_track(
    new_entry: &TrackEntry,
    tracks: &mut [Vec<TrackEntry>],
    track_count: usize,
    view_width: f32,
) -> Option<usize> {
    compact_scroll_tracks(new_entry.time_ms, tracks, new_entry.duration_ms);

    for i in 0..track_count {
        let collides = tracks[i].iter().any(|existing| {
            scroll_entries_collide(new_entry, existing, view_width)
        });
        if !collides {
            tracks[i].push(new_entry.clone());
            return Some(i);
        }
    }

    // All tracks collide — overwrite the track with the smallest right edge
    // (the item that has moved furthest left, freeing the most space).
    // This matches DFM's overwriteInsert strategy.
    let mut best_track = 0;
    let mut min_right_edge = f32::MAX;
    for i in 0..track_count {
        for entry in &tracks[i] {
            let right_edge = entry_right_edge_at(entry, new_entry.time_ms, view_width);
            if right_edge < min_right_edge {
                min_right_edge = right_edge;
                best_track = i;
            }
        }
    }
    tracks[best_track].clear();
    tracks[best_track].push(new_entry.clone());
    Some(best_track)
}

/// Compute the right edge of a scroll entry at a given time.
fn entry_right_edge_at(entry: &TrackEntry, time_ms: i64, view_width: f32) -> f32 {
    entry_x_at(entry, time_ms, view_width) + entry.paint_width
}

/// Select a track for a fixed danmaku with queue-like behavior.
/// Each track holds multiple non-overlapping fixed entries (appended in time order).
/// Pass 1: find a track whose last entry ends before the new entry starts → no displacement.
/// Pass 2: all tracks are occupied at the new entry's time → queue on the track
/// whose last entry expires soonest, displacing that last entry.
/// Returns `Some(track, was_queued, displaced_index)` where displaced_index is
/// Some only when a previously-queued entry is displaced (Pass 2).
fn select_fixed_track(
    new_entry: &TrackEntry,
    tracks: &mut [Vec<TrackEntry>],
    track_count: usize,
) -> Option<(usize, bool, Option<usize>)> {
    let new_start = new_entry.time_ms - new_entry.duration_ms;
    
    for i in 0..track_count {
        if tracks[i].is_empty() {
            tracks[i].push(new_entry.clone());
            return Some((i, false, None));
        }
        let last = tracks[i].last().unwrap();
        let last_end = last.time_ms;
        if new_start >= last_end {
            tracks[i].push(new_entry.clone());
            return Some((i, false, None));
        }
    }
    
    let mut best_track = 0;
    let mut earliest_end = i64::MAX;
    for i in 0..track_count {
        let last = tracks[i].last().unwrap();
        let end = last.time_ms;
        if end < earliest_end {
            earliest_end = end;
            best_track = i;
        }
    }
    let last = tracks[best_track].last().unwrap();
    let displaced_index = last.danmaku_index;
    let new_end = earliest_end + new_entry.duration_ms;
    let queued = TrackEntry {
        time_ms: new_end,
        duration_ms: new_entry.duration_ms,
        paint_width: new_entry.paint_width,
        danmaku_type: new_entry.danmaku_type,
        danmaku_index: new_entry.danmaku_index,
    };
    tracks[best_track].push(queued);
    Some((best_track, true, Some(displaced_index)))
}

// ---------------------------------------------------------------------------
// Collision detection (ported from DanmakuFlameMaster's DanmakuUtils)
// ---------------------------------------------------------------------------

/// Check if two scroll entries will collide (1:1 port from DFM)
/// Ported from DanmakuUtils.willHitInDuration()
fn scroll_entries_collide(entry_a: &TrackEntry, entry_b: &TrackEntry, view_width: f32) -> bool {
    if entry_a.danmaku_type != entry_b.danmaku_type {
        return false;
    }

    // Assign d1 to the earlier entry, d2 to the later one
    let (d1, d2) = if entry_a.time_ms <= entry_b.time_ms {
        (entry_a, entry_b)
    } else {
        (entry_b, entry_a)
    };

    // dTime = d2_time - d1_time
    let d_time = d2.time_ms - d1.time_ms;
    
    // Case 1: d2 is at or before d1 - collide
    if d_time <= 0 {
        return true;
    }
    
    // Case 2: d2 is long after d1 - not collide
    if d_time >= d1.duration_ms as i64 {
        return false;
    }

    // Case 3: Need to check collision at two points in time
    let curr_time = d2.time_ms;
    let d1_end_time = d1.time_ms + d1.duration_ms as i64;
    
    check_hit_at_time(d2, d1, curr_time, view_width)
        || check_hit_at_time(d2, d1, d1_end_time, view_width)
}

/// Check collision at a specific time (port from DanmakuUtils.checkHitAtTime)
fn check_hit_at_time(
    d_new: &TrackEntry,
    d_existing: &TrackEntry,
    time_ms: i64,
    view_width: f32,
) -> bool {
    // Get rects at given time
    let rect1 = entry_rect_at(d_new, time_ms, view_width);
    let rect2 = entry_rect_at(d_existing, time_ms, view_width);
    
    // Call checkHit
    check_hit(d_new.danmaku_type, d_existing.danmaku_type, rect1, rect2)
}

/// Get entry's bounding rectangle at a specific time
fn entry_rect_at(
    entry: &TrackEntry,
    time_ms: i64,
    view_width: f32,
) -> (f32, f32, f32, f32) {
    let left = entry_left_at(entry, time_ms, view_width);
    (left, 0.0, left + entry.paint_width, 0.0)
}

/// Perform actual hit check based on type (port from DanmakuUtils.checkHit)
fn check_hit(
    type1: DanmakuType,
    type2: DanmakuType,
    rect1: (f32, f32, f32, f32),
    rect2: (f32, f32, f32, f32),
) -> bool {
    if type1 != type2 {
        return false;
    }
    
    match type1 {
        DanmakuType::ScrollRL => {
            // For RL: hit if left2 < right1
            rect2.0 < rect1.2
        }
        DanmakuType::ScrollLR => {
            // For LR: hit if right2 > left1
            rect2.2 > rect1.0
        }
        _ => false,
    }
}

/// Get the left edge (x position) of a scroll entry at a given time.
/// Handles entries that start in the future or have ended.
fn entry_left_at(entry: &TrackEntry, time_ms: i64, view_width: f32) -> f32 {
    if entry.danmaku_type == DanmakuType::ScrollLR {
        return entry_x_at(entry, time_ms, view_width);
    }
    
    // For ScrollRL: x is the LEFT edge
    let elapsed = (time_ms - entry.time_ms).max(0) as f32;
    let duration = entry.duration_ms as f32;
    
    if duration <= 0.0 {
        return view_width;
    }
    
    // Position at left edge: view_width - elapsed_fraction * (view_width + width)
    let pos = view_width - (elapsed / duration) * (view_width + entry.paint_width);
    
    // If elapsed > duration, danmaku has left the screen, return off-screen position
    if elapsed >= duration {
        return -entry.paint_width;
    }
    
    // If danmaku hasn't entered yet (elapsed < 0, should not happen here)
    pos.max(-entry.paint_width)
}

/// Get the right edge of a scroll entry at a given time.
fn entry_right_at(entry: &TrackEntry, time_ms: i64, view_width: f32) -> f32 {
    entry_left_at(entry, time_ms, view_width) + entry.paint_width
}

/// Compute the X position of a scroll entry at a given time.
fn entry_x_at(entry: &TrackEntry, time_ms: i64, view_width: f32) -> f32 {
    let elapsed = (time_ms - entry.time_ms).max(0) as f32;
    let duration = entry.duration_ms as f32;
    if duration <= 0.0 {
        return match entry.danmaku_type {
            DanmakuType::ScrollRL => view_width,
            DanmakuType::ScrollLR => -entry.paint_width,
            _ => 0.0,
        };
    }
    match entry.danmaku_type {
        DanmakuType::ScrollRL => {
            view_width - (elapsed / duration) * (view_width + entry.paint_width)
        }
        DanmakuType::ScrollLR => {
            (elapsed / duration) * (view_width + entry.paint_width) - entry.paint_width
        }
        _ => 0.0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dfm_core::model::DanmakuItem;

    #[test]
    fn test_first_item_placed_at_top() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut item = DanmakuItem::new(0, "test".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
        item.paint_width = 100.0;
        item.paint_height = 30.0;

        let (placed, _) = retainer.fix(&mut item, 1920.0, 1080.0, &flags, 1.0);
        assert!(placed);
        assert!(item.is_shown);
        assert!((item.y - 2.0).abs() < 1.0, "first item y={} should be ~2.0", item.y);
    }

    #[test]
    fn test_same_time_items_different_tracks() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items = vec![
            DanmakuItem::new(0, "first".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000),
            DanmakuItem::new(0, "second".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000),
        ];
        items[0].paint_width = 100.0;
        items[0].paint_height = 30.0;
        items[1].paint_width = 100.0;
        items[1].paint_height = 30.0;

        let (placed1, _) = retainer.fix(&mut items[0], 1920.0, 1080.0, &flags, 1.0);
        assert!(placed1);
        let first_y = items[0].y;

        let (placed2, _) = retainer.fix(&mut items[1], 1920.0, 1080.0, &flags, 1.0);
        assert!(placed2);
        assert!(items[1].y > first_y, "same-time items should be on different tracks: first_y={}, second_y={}", first_y, items[1].y);
    }

    #[test]
    fn test_non_overlapping_items_same_track() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items = vec![
            DanmakuItem::new(0, "early".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 3000),
            DanmakuItem::new(10000, "late".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 3000),
        ];
        items[0].paint_width = 100.0;
        items[0].paint_height = 30.0;
        items[1].paint_width = 100.0;
        items[1].paint_height = 30.0;

        retainer.fix(&mut items[0], 1920.0, 1080.0, &flags, 1.0);
        let first_y = items[0].y;

        retainer.fix(&mut items[1], 1920.0, 1080.0, &flags, 1.0);
        assert!((items[1].y - first_y).abs() < 1.0,
            "non-overlapping items should share track: first_y={}, second_y={}", first_y, items[1].y);
    }

    #[test]
    fn test_fixed_items_separate_tracks() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items = vec![
            DanmakuItem::new(0, "top1".into(), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800),
            DanmakuItem::new(0, "top2".into(), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800),
        ];
        items[0].paint_width = 100.0;
        items[0].paint_height = 30.0;
        items[1].paint_width = 100.0;
        items[1].paint_height = 30.0;

        retainer.fix(&mut items[0], 1920.0, 1080.0, &flags, 1.0);
        let first_y = items[0].y;

        retainer.fix(&mut items[1], 1920.0, 1080.0, &flags, 1.0);
        assert!(items[1].y > first_y, "same-time fixed items should be on different tracks");
    }

    #[test]
    fn test_fixed_expired_item_replaced() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items = vec![
            DanmakuItem::new(0, "first".into(), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800),
            DanmakuItem::new(5000, "second".into(), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800),
        ];
        items[0].paint_width = 100.0;
        items[0].paint_height = 30.0;
        items[1].paint_width = 100.0;
        items[1].paint_height = 30.0;

        retainer.fix(&mut items[0], 1920.0, 1080.0, &flags, 1.0);
        let first_y = items[0].y;

        retainer.fix(&mut items[1], 1920.0, 1080.0, &flags, 1.0);
        assert!((items[1].y - first_y).abs() < 1.0,
            "expired fixed item should be replaced: first_y={}, second_y={}", first_y, items[1].y);
    }

    #[test]
    fn test_scroll_collision_same_time() {
        let d1 = TrackEntry { time_ms: 0, duration_ms: 5000, paint_width: 100.0, danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
        let d2 = TrackEntry { time_ms: 0, duration_ms: 5000, paint_width: 100.0, danmaku_type: DanmakuType::ScrollRL, danmaku_index: 1 };
        assert!(scroll_entries_collide(&d1, &d2, 1920.0));
    }

    #[test]
    fn test_scroll_no_collision_far_apart() {
        let d1 = TrackEntry { time_ms: 0, duration_ms: 3000, paint_width: 100.0, danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
        let d2 = TrackEntry { time_ms: 10000, duration_ms: 3000, paint_width: 100.0, danmaku_type: DanmakuType::ScrollRL, danmaku_index: 1 };
        assert!(!scroll_entries_collide(&d1, &d2, 1920.0));
    }

    #[test]
    fn test_scroll_x_position() {
        let entry = TrackEntry { time_ms: 0, duration_ms: 5000, paint_width: 100.0, danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
        let x0 = entry_x_at(&entry, 0, 1920.0);
        assert!((x0 - 1920.0).abs() < 1.0);
        let x5 = entry_x_at(&entry, 5000, 1920.0);
        assert!((x5 - (-100.0)).abs() < 1.0);
    }

    #[test]
    fn test_overflow_queues_item() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items = vec![
            DanmakuItem::new(0, "a".into(), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800),
            DanmakuItem::new(0, "b".into(), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800),
        ];
        items[0].paint_width = 100.0;
        items[0].paint_height = 30.0;
        items[1].paint_width = 100.0;
        items[1].paint_height = 30.0;

        retainer.fix(&mut items[0], 1920.0, 60.0, &flags, 1.0);
        let (_, displaced1) = retainer.fix(&mut items[1], 1920.0, 60.0, &flags, 1.0);

        assert_eq!(items[1].time_ms, 3800,
            "queued item should start when the track frees up");
        if let Some(displaced) = displaced1 {
            items[displaced].is_filtered = true;
            items[displaced].filter_param = 99;
        }
        assert_eq!(displaced1, Some(0), "item 0 should be displaced");
        assert!(items[0].is_filtered, "displaced item should be filtered");
    }

    #[test]
    fn test_different_width_same_time_different_tracks() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items = vec![
            DanmakuItem::new(0, "wide".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000),
            DanmakuItem::new(0, "narrow".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000),
        ];

        items[0].paint_width = 500.0;
        items[0].paint_height = 30.0;
        items[1].paint_width = 28.0;
        items[1].paint_height = 30.0;

        retainer.fix(&mut items[0], 1920.0, 1080.0, &flags, 1.0);
        retainer.fix(&mut items[1], 1920.0, 1080.0, &flags, 1.0);
        assert!((items[0].y - items[1].y).abs() > 1.0,
            "different-width same-time items must be on different tracks: wide_y={}, narrow_y={}", items[0].y, items[1].y);
    }

    #[test]
    fn test_many_same_time_no_y_overlap() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);

        let texts: Vec<String> = (0..15).map(|i| format!("弹幕{}", i)).collect();
        let mut items: Vec<DanmakuItem> = texts.iter().map(|text| {
            let mut item = DanmakuItem::new(1000, text.clone(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
            item.paint_width = 150.0;
            item.paint_height = 30.0;
            item
        }).collect();

        let mut placed_ys = Vec::new();
        for item in &mut items {
            let (placed, _) = retainer.fix(item, 1920.0, 1080.0, &flags, 1.0);
            if placed {
                placed_ys.push(item.y);
            }
        }

        for i in 0..placed_ys.len() {
            for j in (i+1)..placed_ys.len() {
                assert!((placed_ys[i] - placed_ys[j]).abs() > 1.0,
                    "items {} and {} share y={}", i, j, placed_ys[i]);
            }
        }
    }

    #[test]
    fn test_chain_queue_fixed_items() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items: Vec<DanmakuItem> = (0..4).map(|i| {
            let mut item = DanmakuItem::new(0, format!("top{}", i), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800);
            item.paint_width = 100.0;
            item.paint_height = 30.0;
            item
        }).collect();

        for i in 0..items.len() {
            items[i].index = i as u32;
            let (_, displaced) = retainer.fix(&mut items[i], 1920.0, 60.0, &flags, 1.0);
            if let Some(d) = displaced {
                items[d].is_filtered = true;
                items[d].filter_param = 99;
            }
        }
        assert_eq!(items[0].time_ms, 0);
        assert_eq!(items[1].time_ms, 3800);
        assert_eq!(items[2].time_ms, 7600);
        assert_eq!(items[3].time_ms, 11400);

        assert!(items[0].is_filtered, "item 0 should be filtered after being displaced by item 1");
        assert!(items[1].is_filtered, "item 1 should be filtered after being displaced by item 2");
        assert!(items[2].is_filtered, "item 2 should be filtered after being displaced by item 3");
        assert!(!items[3].is_filtered, "item 3 should not be filtered (last item, shows from 11400-15200)");
    }

    #[test]
    fn test_staggered_items_tracks() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);

        let mut items: Vec<DanmakuItem> = (0..10).map(|i| {
            let mut item = DanmakuItem::new(i * 100, format!("item_{}", i), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
            item.paint_width = 150.0;
            item.paint_height = 30.0;
            item
        }).collect();

        for item in &mut items {
            retainer.fix(item, 1920.0, 1080.0, &flags, 1.0);
        }

        for i in 0..items.len() {
            for j in (i+1)..items.len() {
                let time_diff = (items[j].time_ms - items[i].time_ms).abs();
                if time_diff < 5000 {
                    let y_diff = (items[i].y - items[j].y).abs();
                    if y_diff < 1.0 && items[i].y >= 0.0 && items[j].y >= 0.0 {
                        println!("Same track: item_{} (t={}) and item_{} (t={}), y={}",
                            i, items[i].time_ms, j, items[j].time_ms, items[i].y);
                    }
                }
            }
        }
    }

    #[test]
    fn test_fixed_top_overlap_no_visual_overlap() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items: Vec<DanmakuItem> = (0..5).map(|i| {
            let mut item = DanmakuItem::new(0, format!("top{}", i), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800);
            item.paint_width = 100.0;
            item.paint_height = 30.0;
            item
        }).collect();

        for i in 0..items.len() {
            let (_, displaced) = retainer.fix(&mut items[i], 1920.0, 1080.0, &flags, 1.0);
            if let Some(d) = displaced {
                items[d].is_filtered = true;
                items[d].filter_param = 99;
            }
        }

        let mut visible_ys = Vec::new();
        for item in &items {
            if item.is_shown && !item.is_filtered {
                visible_ys.push(item.y);
            }
        }

        for i in 0..visible_ys.len() {
            for j in (i+1)..visible_ys.len() {
                assert!((visible_ys[i] - visible_ys[j]).abs() > 1.0,
                    "visible items {} and {} share y={}, causing visual overlap", i, j, visible_ys[i]);
            }
        }
    }

    #[test]
    fn test_fix_bottom_overflow_queues_correctly() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items: Vec<DanmakuItem> = (0..4).map(|i| {
            let mut item = DanmakuItem::new(0, format!("bottom{}", i), 0xFFFFFFFF, 25.0, DanmakuType::FixBottom, 3800);
            item.paint_width = 100.0;
            item.paint_height = 30.0;
            item
        }).collect();

        for i in 0..items.len() {
            items[i].index = i as u32;
            let (_, displaced) = retainer.fix(&mut items[i], 1920.0, 60.0, &flags, 1.0);
            if let Some(d) = displaced {
                items[d].is_filtered = true;
                items[d].filter_param = 99;
            }
        }

        assert_eq!(items[0].time_ms, 0);
        assert_eq!(items[1].time_ms, 3800);
        assert_eq!(items[2].time_ms, 7600);
        assert_eq!(items[3].time_ms, 11400);

        assert!(items[0].is_filtered, "item 0 should be filtered");
        assert!(items[1].is_filtered, "item 1 should be filtered");
        assert!(items[2].is_filtered, "item 2 should be filtered");
        assert!(!items[3].is_filtered, "item 3 should not be filtered");
    }
}
