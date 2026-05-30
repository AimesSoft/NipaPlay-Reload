/// Track-based collision avoidance layout engine.
/// Inspired by Next2's track + compaction approach for correct pre-computed layout.
///
/// Key design: per-type track arrays storing lightweight collision records,
/// compact expired items before each placement, assign to first non-colliding track,
/// compute Y from track index.

use smallvec::SmallVec;

use crate::dfm_core::model::{DanmakuItem, DanmakuType, GlobalFlags};

type DisplacedIndices = SmallVec<[usize; 4]>;

/// Lightweight record stored in tracks for collision detection.
/// Avoids needing to look up items by index from an external array.
/// For fixed danmaku, `time_ms` is used as the track's END time (not start time),
/// so that Pass 1 can correctly check if a new danmaku starts after the track is free.
#[derive(Debug, Clone)]
struct TrackEntry {
    time_ms: i64,
    duration_ms: i64,
    paint_width: f32,
    step_x: f32,
    danmaku_type: DanmakuType,
    danmaku_index: usize,
}

impl TrackEntry {
    fn from_item(item: &DanmakuItem, index: usize) -> Self {
        Self {
            time_ms: item.time_ms,
            duration_ms: item.duration_ms,
            paint_width: item.paint_width,
            step_x: item.step_x,
            danmaku_type: item.danmaku_type,
            danmaku_index: index,
        }
    }

    fn end_ms(&self) -> i64 {
        self.time_ms + self.duration_ms
    }
}

#[derive(Debug, Clone)]
struct TrackData {
    tracks: Vec<Vec<TrackEntry>>,
}

impl TrackData {
    fn new() -> Self {
        Self {
            tracks: Vec::new(),
        }
    }

    fn ensure_track_count(&mut self, count: usize) {
        if self.tracks.len() != count {
            self.tracks.resize_with(count, Vec::new);
        }
    }

    fn compact(&mut self, current_time_ms: i64, current_duration_ms: i64) {
        for track in self.tracks.iter_mut() {
            track.retain(|existing| {
                current_time_ms < existing.end_ms() + current_duration_ms
                    && current_time_ms > existing.time_ms - existing.duration_ms
            });
        }
    }

    fn clear(&mut self) {
        self.tracks.clear();
    }
}

/// Track-based collision avoidance engine.
#[derive(Debug, Clone)]
pub struct DanmakuRetainer {
    r2l_tracks: TrackData,
    lr_tracks: TrackData,
    top_tracks: TrackData,
    bottom_tracks: TrackData,
    margin: f32,
    track_gap_ratio: f32,
}

impl DanmakuRetainer {
    pub fn new(margin: f32, track_gap_ratio: f32) -> Self {
        Self {
            r2l_tracks: TrackData::new(),
            lr_tracks: TrackData::new(),
            top_tracks: TrackData::new(),
            bottom_tracks: TrackData::new(),
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
    /// Returns indices of any displaced danmaku that should be marked as filtered.
    pub fn fix(
        &mut self,
        item: &mut DanmakuItem,
        view_width: f32,
        view_height: f32,
        flags: &GlobalFlags,
        display_area: f32,
        is_me: bool,
    ) -> (bool, DisplacedIndices) {
        let capped_display = if item.danmaku_type.is_scroll() {
            display_area.min(0.75)
        } else {
            display_area
        };
        let effective_height = view_height * capped_display;
        let track_height = item.paint_height + item.paint_height * self.track_gap_ratio;
        let mut track_count = (effective_height / track_height).floor().max(1.0) as usize;
        if item.danmaku_type.is_scroll() && (capped_display - 1.0).abs() < 0.001 && track_count > 1 {
            track_count -= 1;
        }
        let danmaku_index = item.index as usize;

        let entry = TrackEntry::from_item(item, danmaku_index);

        match item.danmaku_type {
            DanmakuType::ScrollRL => {
                self.r2l_tracks.ensure_track_count(track_count);
                match select_scroll_track(&entry, &mut self.r2l_tracks, track_count, view_width, is_me) {
                    Some((row, displaced)) => {
                        item.y = self.margin + row as f32 * track_height;
                        item.is_shown = true;
                        item.flags.visible = flags.visible_flag;
                        (true, displaced)
                    }
                    None => (false, SmallVec::new()),
                }
            }
            DanmakuType::ScrollLR => {
                self.lr_tracks.ensure_track_count(track_count);
                match select_scroll_track(&entry, &mut self.lr_tracks, track_count, view_width, is_me) {
                    Some((row, displaced)) => {
                        item.y = self.margin + row as f32 * track_height;
                        item.is_shown = true;
                        item.flags.visible = flags.visible_flag;
                        (true, displaced)
                    }
                    None => (false, SmallVec::new()),
                }
            }
            DanmakuType::FixTop => {
                self.top_tracks.ensure_track_count(track_count);
                match select_fixed_track(&entry, &mut self.top_tracks.tracks, track_count) {
                    Some((row, was_queued, displaced_index)) => {
                        if was_queued {
                            let last = self.top_tracks.tracks[row].last().unwrap();
                            item.time_ms = last.time_ms;
                        }
                        item.y = self.margin + row as f32 * track_height;
                        item.is_shown = true;
                        item.flags.visible = flags.visible_flag;
                        (true, displaced_index.into_iter().collect())
                    }
                    None => (false, SmallVec::new()),
                }
            }
            DanmakuType::FixBottom => {
                self.bottom_tracks.ensure_track_count(track_count);
                match select_fixed_track(&entry, &mut self.bottom_tracks.tracks, track_count) {
                    Some((row, was_queued, displaced_index)) => {
                        if was_queued {
                            let last = self.bottom_tracks.tracks[row].last().unwrap();
                            item.time_ms = last.time_ms;
                        }
                        item.y = effective_height - (row as f32 + 1.0) * track_height;
                        item.is_shown = true;
                        item.flags.visible = flags.visible_flag;
                        (true, displaced_index.into_iter().collect())
                    }
                    None => (false, SmallVec::new()),
                }
            }
            DanmakuType::Special => {
                item.y = 0.0;
                item.is_shown = true;
                item.flags.visible = flags.visible_flag;
                (true, SmallVec::new())
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Track selection
// ---------------------------------------------------------------------------

/// Select a track for a scroll danmaku.
/// Returns (track_index, displaced_indices) or None if the item should be dropped.
/// When all tracks collide, uses DFM's overwriteInsert strategy: pick the track
/// whose items have the smallest right edge (furthest left), clear it, and place
/// the new danmaku there. Returns indices of all cleared entries so the caller
/// can mark them as filtered.
fn select_scroll_track(
    new_entry: &TrackEntry,
    track_data: &mut TrackData,
    track_count: usize,
    view_width: f32,
    is_me: bool,
) -> Option<(usize, DisplacedIndices)> {
    track_data.compact(new_entry.time_ms, new_entry.duration_ms);

    for i in 0..track_count {
        let collides = track_data.tracks[i].iter().any(|existing| {
            scroll_entries_collide(new_entry, existing, view_width)
        });
        if !collides {
            track_data.tracks[i].push(new_entry.clone());
            return Some((i, SmallVec::new()));
        }
    }

    if is_me && track_count > 0 {
        let displaced: DisplacedIndices = track_data.tracks[0].iter().map(|e| e.danmaku_index).collect();
        track_data.tracks[0].clear();
        track_data.tracks[0].push(new_entry.clone());
        return Some((0, displaced));
    }

    let upper_limit = ((track_count as f32 * 0.6).ceil() as usize).max(1).min(track_count);

    let mut best_track = 0;
    let mut min_right_edge = f32::MAX;
    for i in 0..upper_limit {
        for entry in &track_data.tracks[i] {
            let right_edge = entry_right_edge_at(entry, new_entry.time_ms, view_width);
            if right_edge < min_right_edge {
                min_right_edge = right_edge;
                best_track = i;
            }
        }
    }

    if min_right_edge < f32::MAX {
        let displaced: DisplacedIndices = track_data.tracks[best_track].iter().map(|e| e.danmaku_index).collect();
        track_data.tracks[best_track].clear();
        track_data.tracks[best_track].push(new_entry.clone());
        return Some((best_track, displaced));
    }

    None
}

fn entry_right_edge_at(entry: &TrackEntry, time_ms: i64, view_width: f32) -> f32 {
    entry_x_at(entry, time_ms, view_width) + entry.paint_width
}

fn select_fixed_track(
    new_entry: &TrackEntry,
    tracks: &mut [Vec<TrackEntry>],
    track_count: usize,
) -> Option<(usize, bool, Option<usize>)> {
    let new_start = new_entry.time_ms;
    
    for i in 0..track_count {
        if tracks[i].is_empty() {
            tracks[i].push(new_entry.clone());
            return Some((i, false, None));
        }
        let last = tracks[i].last().unwrap();
        let last_end = last.end_ms();
        if new_start >= last_end {
            tracks[i].push(new_entry.clone());
            return Some((i, false, None));
        }
    }
    
    let mut best_track = 0;
    let mut earliest_end = i64::MAX;
    for i in 0..track_count {
        let last = tracks[i].last().unwrap();
        let end = last.end_ms();
        if end < earliest_end {
            earliest_end = end;
            best_track = i;
        }
    }
    let last = tracks[best_track].last().unwrap();
    let displaced_index = last.danmaku_index;
    let queued_start = earliest_end;
    let queued = TrackEntry {
        time_ms: queued_start,
        duration_ms: new_entry.duration_ms,
        paint_width: new_entry.paint_width,
        step_x: new_entry.step_x,
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
#[inline]
fn scroll_entries_collide(entry_a: &TrackEntry, entry_b: &TrackEntry, view_width: f32) -> bool {
    if entry_a.danmaku_type != entry_b.danmaku_type {
        return false;
    }

    let (d1, d2) = if entry_a.time_ms <= entry_b.time_ms {
        (entry_a, entry_b)
    } else {
        (entry_b, entry_a)
    };

    let d_time = d2.time_ms - d1.time_ms;
    
    if d_time <= 0 {
        return true;
    }
    
    if d_time >= d1.duration_ms as i64 {
        return false;
    }

    let d1_left_at_d2_start = entry_left_at(d1, d2.time_ms, view_width);
    let d1_right_at_d2_start = d1_left_at_d2_start + d1.paint_width;
    let d2_left_at_start = entry_left_at_start(d2, view_width);

    if check_hit_same_type(d1.danmaku_type, d1_left_at_d2_start, d1_right_at_d2_start, d2_left_at_start, d2_left_at_start + d2.paint_width) {
        return true;
    }

    let d1_left_at_d1_end = entry_left_at(d1, d1.end_ms(), view_width);
    let d1_right_at_d1_end = d1_left_at_d1_end + d1.paint_width;
    let d2_left_at_d1_end = entry_left_at(d2, d1.end_ms(), view_width);

    check_hit_same_type(d1.danmaku_type, d1_left_at_d1_end, d1_right_at_d1_end, d2_left_at_d1_end, d2_left_at_d1_end + d2.paint_width)
}

#[inline]
fn check_hit_same_type(
    danmaku_type: DanmakuType,
    left1: f32,
    right1: f32,
    left2: f32,
    right2: f32,
) -> bool {
    debug_assert!(danmaku_type.is_scroll());
    match danmaku_type {
        DanmakuType::ScrollRL => left2 < right1,
        DanmakuType::ScrollLR => right2 > left1,
        _ => false,
    }
}

#[inline]
fn entry_left_at_start(entry: &TrackEntry, view_width: f32) -> f32 {
    match entry.danmaku_type {
        DanmakuType::ScrollRL => view_width,
        DanmakuType::ScrollLR => -entry.paint_width,
        _ => 0.0,
    }
}

#[inline]
fn entry_left_at(entry: &TrackEntry, time_ms: i64, view_width: f32) -> f32 {
    if entry.danmaku_type == DanmakuType::ScrollLR {
        return entry_x_at(entry, time_ms, view_width);
    }
    
    let elapsed = (time_ms - entry.time_ms).max(0) as f32;
    
    if entry.step_x <= 0.0 {
        return view_width;
    }
    
    if elapsed >= entry.duration_ms as f32 {
        return -entry.paint_width;
    }
    
    let pos = view_width - elapsed * entry.step_x;
    pos.max(-entry.paint_width)
}

#[inline]
fn entry_right_at(entry: &TrackEntry, time_ms: i64, view_width: f32) -> f32 {
    entry_left_at(entry, time_ms, view_width) + entry.paint_width
}

#[inline]
fn entry_x_at(entry: &TrackEntry, time_ms: i64, view_width: f32) -> f32 {
    let elapsed = (time_ms - entry.time_ms).max(0) as f32;
    if entry.step_x <= 0.0 {
        return match entry.danmaku_type {
            DanmakuType::ScrollRL => view_width,
            DanmakuType::ScrollLR => -entry.paint_width,
            _ => 0.0,
        };
    }
    match entry.danmaku_type {
        DanmakuType::ScrollRL => {
            view_width - elapsed * entry.step_x
        }
        DanmakuType::ScrollLR => {
            elapsed * entry.step_x - entry.paint_width
        }
        _ => 0.0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dfm_core::model::DanmakuItem;

    fn calc_step_x(paint_width: f32, duration_ms: i64, view_width: f32) -> f32 {
        (view_width + paint_width) / duration_ms as f32
    }

    fn make_scroll_item(time_ms: i64, text: &str, paint_width: f32, danmaku_type: DanmakuType, duration_ms: i64, view_width: f32) -> DanmakuItem {
        let mut item = DanmakuItem::new(time_ms, text.into(), 0xFFFFFFFF, 25.0, danmaku_type, duration_ms);
        item.paint_width = paint_width;
        item.paint_height = 30.0;
        item.step_x = calc_step_x(paint_width, duration_ms, view_width);
        item
    }

    fn make_fixed_item(time_ms: i64, text: &str, danmaku_type: DanmakuType, duration_ms: i64) -> DanmakuItem {
        let mut item = DanmakuItem::new(time_ms, text.into(), 0xFFFFFFFF, 25.0, danmaku_type, duration_ms);
        item.paint_width = 100.0;
        item.paint_height = 30.0;
        item
    }

    #[test]
    fn test_first_item_placed_at_top() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut item = make_scroll_item(0, "test", 100.0, DanmakuType::ScrollRL, 5000, 1920.0);

        let (placed, _) = retainer.fix(&mut item, 1920.0, 1080.0, &flags, 1.0, false);
        assert!(placed);
        assert!(item.is_shown);
        assert!((item.y - 2.0).abs() < 1.0, "first item y={} should be ~2.0", item.y);
    }

    #[test]
    fn test_same_time_items_different_tracks() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items = vec![
            make_scroll_item(0, "first", 100.0, DanmakuType::ScrollRL, 5000, 1920.0),
            make_scroll_item(0, "second", 100.0, DanmakuType::ScrollRL, 5000, 1920.0),
        ];

        let (placed1, _) = retainer.fix(&mut items[0], 1920.0, 1080.0, &flags, 1.0, false);
        assert!(placed1);
        let first_y = items[0].y;

        let (placed2, _) = retainer.fix(&mut items[1], 1920.0, 1080.0, &flags, 1.0, false);
        assert!(placed2);
        assert!(items[1].y > first_y, "same-time items should be on different tracks: first_y={}, second_y={}", first_y, items[1].y);
    }

    #[test]
    fn test_non_overlapping_items_same_track() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items = vec![
            make_scroll_item(0, "early", 100.0, DanmakuType::ScrollRL, 3000, 1920.0),
            make_scroll_item(10000, "late", 100.0, DanmakuType::ScrollRL, 3000, 1920.0),
        ];

        retainer.fix(&mut items[0], 1920.0, 1080.0, &flags, 1.0, false);
        let first_y = items[0].y;

        retainer.fix(&mut items[1], 1920.0, 1080.0, &flags, 1.0, false);
        assert!((items[1].y - first_y).abs() < 1.0,
            "non-overlapping items should share track: first_y={}, second_y={}", first_y, items[1].y);
    }

    #[test]
    fn test_fixed_items_separate_tracks() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items = vec![
            make_fixed_item(0, "top1", DanmakuType::FixTop, 3800),
            make_fixed_item(0, "top2", DanmakuType::FixTop, 3800),
        ];

        retainer.fix(&mut items[0], 1920.0, 1080.0, &flags, 1.0, false);
        let first_y = items[0].y;

        retainer.fix(&mut items[1], 1920.0, 1080.0, &flags, 1.0, false);
        assert!(items[1].y > first_y, "same-time fixed items should be on different tracks");
    }

    #[test]
    fn test_fixed_expired_item_replaced() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items = vec![
            make_fixed_item(0, "first", DanmakuType::FixTop, 3800),
            make_fixed_item(5000, "second", DanmakuType::FixTop, 3800),
        ];

        retainer.fix(&mut items[0], 1920.0, 1080.0, &flags, 1.0, false);
        let first_y = items[0].y;

        retainer.fix(&mut items[1], 1920.0, 1080.0, &flags, 1.0, false);
        assert!((items[1].y - first_y).abs() < 1.0,
            "expired fixed item should be replaced: first_y={}, second_y={}", first_y, items[1].y);
    }

    #[test]
    fn test_scroll_collision_same_time() {
        let d1 = TrackEntry { time_ms: 0, duration_ms: 5000, paint_width: 100.0, step_x: calc_step_x(100.0, 5000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
        let d2 = TrackEntry { time_ms: 0, duration_ms: 5000, paint_width: 100.0, step_x: calc_step_x(100.0, 5000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 1 };
        assert!(scroll_entries_collide(&d1, &d2, 1920.0));
    }

    #[test]
    fn test_scroll_no_collision_far_apart() {
        let d1 = TrackEntry { time_ms: 0, duration_ms: 3000, paint_width: 100.0, step_x: calc_step_x(100.0, 3000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
        let d2 = TrackEntry { time_ms: 10000, duration_ms: 3000, paint_width: 100.0, step_x: calc_step_x(100.0, 3000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 1 };
        assert!(!scroll_entries_collide(&d1, &d2, 1920.0));
    }

    #[test]
    fn test_scroll_x_position() {
        let entry = TrackEntry { time_ms: 0, duration_ms: 5000, paint_width: 100.0, step_x: calc_step_x(100.0, 5000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
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
            make_fixed_item(0, "a", DanmakuType::FixTop, 3800),
            make_fixed_item(0, "b", DanmakuType::FixTop, 3800),
        ];

        retainer.fix(&mut items[0], 1920.0, 60.0, &flags, 1.0, false);
        let (_, displaced1) = retainer.fix(&mut items[1], 1920.0, 60.0, &flags, 1.0, false);

        assert_eq!(items[1].time_ms, 3800,
            "queued item should start when the track frees up");
        for &d in &displaced1 {
            items[d].is_filtered = true;
            items[d].filter_param = 99;
        }
        assert!(displaced1.contains(&0), "item 0 should be in displaced list");
        assert!(items[0].is_filtered, "displaced item should be filtered");
    }

    #[test]
    fn test_different_width_same_time_different_tracks() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items = vec![
            make_scroll_item(0, "wide", 500.0, DanmakuType::ScrollRL, 5000, 1920.0),
            make_scroll_item(0, "narrow", 28.0, DanmakuType::ScrollRL, 5000, 1920.0),
        ];

        retainer.fix(&mut items[0], 1920.0, 1080.0, &flags, 1.0, false);
        retainer.fix(&mut items[1], 1920.0, 1080.0, &flags, 1.0, false);
        assert!((items[0].y - items[1].y).abs() > 1.0,
            "different-width same-time items must be on different tracks: wide_y={}, narrow_y={}", items[0].y, items[1].y);
    }

    #[test]
    fn test_many_same_time_no_y_overlap() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);

        let texts: Vec<String> = (0..15).map(|i| format!("弹幕{}", i)).collect();
        let mut items: Vec<DanmakuItem> = texts.iter().map(|text| {
            make_scroll_item(1000, text, 150.0, DanmakuType::ScrollRL, 5000, 1920.0)
        }).collect();

        let mut placed_ys = Vec::new();
        for item in &mut items {
            let (placed, _) = retainer.fix(item, 1920.0, 1080.0, &flags, 1.0, false);
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
            let mut item = make_fixed_item(0, &format!("top{}", i), DanmakuType::FixTop, 3800);
            item.index = i as u32;
            item
        }).collect();

        for i in 0..items.len() {
            items[i].index = i as u32;
            let (_, displaced) = retainer.fix(&mut items[i], 1920.0, 60.0, &flags, 1.0, false);
            for &d in &displaced {
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
            make_scroll_item(i * 100, &format!("item_{}", i), 150.0, DanmakuType::ScrollRL, 5000, 1920.0)
        }).collect();

        for item in &mut items {
            retainer.fix(item, 1920.0, 1080.0, &flags, 1.0, false);
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
            make_fixed_item(0, &format!("top{}", i), DanmakuType::FixTop, 3800)
        }).collect();

        for i in 0..items.len() {
            let (_, displaced) = retainer.fix(&mut items[i], 1920.0, 1080.0, &flags, 1.0, false);
            for &d in &displaced {
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
            let mut item = make_fixed_item(0, &format!("bottom{}", i), DanmakuType::FixBottom, 3800);
            item.index = i as u32;
            item
        }).collect();

        for i in 0..items.len() {
            items[i].index = i as u32;
            let (_, displaced) = retainer.fix(&mut items[i], 1920.0, 60.0, &flags, 1.0, false);
            for &d in &displaced {
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

    #[test]
    fn test_long_danmaku_catches_short() {
        let short = TrackEntry { time_ms: 0, duration_ms: 8000, paint_width: 50.0, step_x: calc_step_x(50.0, 8000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
        let long = TrackEntry { time_ms: 1000, duration_ms: 8000, paint_width: 400.0, step_x: calc_step_x(400.0, 8000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 1 };
        assert!(scroll_entries_collide(&short, &long, 1920.0),
            "long danmaku starting later should catch up to short danmaku on same track");
    }

    #[test]
    fn test_no_false_positive_at_start() {
        let short = TrackEntry { time_ms: 0, duration_ms: 8000, paint_width: 50.0, step_x: calc_step_x(50.0, 8000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
        let long = TrackEntry { time_ms: 1000, duration_ms: 8000, paint_width: 400.0, step_x: calc_step_x(400.0, 8000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 1 };
        let short_left = entry_left_at(&short, 1000, 1920.0);
        let short_right = short_left + short.paint_width;
        let long_left = entry_left_at(&long, 1000, 1920.0);
        assert!(long_left >= short_right,
            "at d2 start: long.left={} should be >= short.right={} (no overlap yet)",
            long_left, short_right);
    }

    #[test]
    fn test_catch_up_at_end() {
        let short = TrackEntry { time_ms: 0, duration_ms: 8000, paint_width: 50.0, step_x: calc_step_x(50.0, 8000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
        let long = TrackEntry { time_ms: 1000, duration_ms: 8000, paint_width: 400.0, step_x: calc_step_x(400.0, 8000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 1 };
        let short_left = entry_left_at(&short, 8000, 1920.0);
        let short_right = short_left + short.paint_width;
        let long_left = entry_left_at(&long, 8000, 1920.0);
        assert!(long_left < short_right,
            "at d1 end: long.left={} should be < short.right={} (catch-up happened)",
            long_left, short_right);
    }

    #[test]
    fn test_no_collision_when_far_apart_in_time() {
        let short = TrackEntry { time_ms: 0, duration_ms: 8000, paint_width: 50.0, step_x: calc_step_x(50.0, 8000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
        let long = TrackEntry { time_ms: 7000, duration_ms: 8000, paint_width: 400.0, step_x: calc_step_x(400.0, 8000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 1 };
        assert!(!scroll_entries_collide(&short, &long, 1920.0),
            "long danmaku starting 7s later should not catch short (short ends at 8s, only 1s overlap window not enough)");
    }

    #[test]
    fn test_long_short_different_tracks() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.15);
        let mut short_item = make_scroll_item(0, "短", 50.0, DanmakuType::ScrollRL, 8000, 1920.0);
        let mut long_item = make_scroll_item(1000, "很长很长的弹幕内容在这里", 400.0, DanmakuType::ScrollRL, 8000, 1920.0);

        retainer.fix(&mut short_item, 1920.0, 1080.0, &flags, 1.0, false);
        retainer.fix(&mut long_item, 1920.0, 1080.0, &flags, 1.0, false);

        assert!((short_item.y - long_item.y).abs() > 1.0,
            "long danmaku (y={}) should be on different track from short (y={}) to avoid catch-up",
            long_item.y, short_item.y);
    }

    #[test]
    fn test_check_hit_direction_rtl() {
        let d1 = TrackEntry { time_ms: 0, duration_ms: 5000, paint_width: 100.0, step_x: calc_step_x(100.0, 5000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
        let d2 = TrackEntry { time_ms: 500, duration_ms: 5000, paint_width: 100.0, step_x: calc_step_x(100.0, 5000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 1 };

        assert!(!scroll_entries_collide(&d1, &d2, 1920.0),
            "same-speed danmaku 500ms apart should NOT collide (they maintain distance)");

        let d1_fast = TrackEntry { time_ms: 0, duration_ms: 8000, paint_width: 50.0, step_x: calc_step_x(50.0, 8000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 0 };
        let d2_slow = TrackEntry { time_ms: 1000, duration_ms: 8000, paint_width: 400.0, step_x: calc_step_x(400.0, 8000, 1920.0), danmaku_type: DanmakuType::ScrollRL, danmaku_index: 1 };

        let t_start = 1000;
        let d1_right_at_start = entry_left_at(&d1_fast, t_start, 1920.0) + d1_fast.paint_width;
        let d2_left_at_start = entry_left_at(&d2_slow, t_start, 1920.0);
        assert!(d2_left_at_start >= d1_right_at_start,
            "at d2 start: d2.left={} should be >= d1.right={} (no overlap yet, d2 just entered)",
            d2_left_at_start, d1_right_at_start);

        let t_end = 8000;
        let d1_right_at_end = entry_left_at(&d1_fast, t_end, 1920.0) + d1_fast.paint_width;
        let d2_left_at_end = entry_left_at(&d2_slow, t_end, 1920.0);
        assert!(d2_left_at_end < d1_right_at_end,
            "at d1 end: d2.left={} should be < d1.right={} (long danmaku caught up!)",
            d2_left_at_end, d1_right_at_end);

        assert!(scroll_entries_collide(&d1_fast, &d2_slow, 1920.0),
            "long fast danmaku should collide with short slow danmaku");
    }
}
