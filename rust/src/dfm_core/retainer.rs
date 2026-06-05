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
    last_compact_ms: i64,
}

impl TrackData {
    fn new() -> Self {
        Self {
            tracks: Vec::new(),
            last_compact_ms: i64::MIN,
        }
    }

    fn ensure_track_count(&mut self, count: usize) {
        if self.tracks.len() != count {
            self.tracks.resize_with(count, Vec::new);
        }
    }

    /// Compact expired entries from a track.
    /// DFM original keeps entries for start+2*duration, which is unnecessarily long.
    /// We match Next2's approach: an entry is expired when its full duration has elapsed
    /// since it started (i.e., it has scrolled completely off screen).
    fn compact(&mut self, current_time_ms: i64, _current_duration_ms: i64) {
        if current_time_ms == self.last_compact_ms {
            return;
        }
        self.last_compact_ms = current_time_ms;
        for track in self.tracks.iter_mut() {
            track.retain(|existing| current_time_ms < existing.end_ms());
        }
    }

    fn clear(&mut self) {
        self.tracks.clear();
        self.last_compact_ms = i64::MIN;
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
        // Scroll danmaku is capped at 75% of the display area to prevent
        // blocking subtitles at the bottom of the screen.
        // Fixed danmaku can use the full display area.
        // Each type has independent track systems (r2l_tracks, top_tracks, etc.).
        let capped_display = if item.danmaku_type.is_scroll() {
            display_area.min(0.75)
        } else {
            display_area
        };
        let effective_height = view_height * capped_display;
        let track_height = item.paint_height + item.paint_height * self.track_gap_ratio;
        let mut track_count = (effective_height / track_height).floor().max(1.0) as usize;
        // Reserve one track at the bottom for screen-edge padding when using full display area.
        // Check against the original display_area so scroll danmaku also benefits when
        // the user sets display_area to 1.0 (capped_display would be 0.75 which would
        // skip this check).
        if (display_area - 1.0).abs() < 0.001 && track_count > 1 {
            track_count -= 1;
        }
        let danmaku_index = item.index as usize;

        let entry = TrackEntry::from_item(item, danmaku_index);

        match item.danmaku_type {
            DanmakuType::ScrollRL => {
                self.r2l_tracks.ensure_track_count(track_count);
                match select_scroll_track(
                    &entry,
                    &mut self.r2l_tracks,
                    track_count,
                    view_width,
                    is_me,
                ) {
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
                match select_scroll_track(
                    &entry,
                    &mut self.lr_tracks,
                    track_count,
                    view_width,
                    is_me,
                ) {
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
                match select_fixed_track(&entry, &mut self.top_tracks, track_count) {
                    Some(row) => {
                        item.y = self.margin + row as f32 * track_height;
                        item.is_shown = true;
                        item.flags.visible = flags.visible_flag;
                        (true, SmallVec::new())
                    }
                    None => (false, SmallVec::new()),
                }
            }
            DanmakuType::FixBottom => {
                self.bottom_tracks.ensure_track_count(track_count);
                match select_fixed_track(&entry, &mut self.bottom_tracks, track_count) {
                    Some(row) => {
                        item.y = effective_height - (row as f32 + 1.0) * track_height;
                        item.is_shown = true;
                        item.flags.visible = flags.visible_flag;
                        (true, SmallVec::new())
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
///
/// Track selection uses a two-phase strategy to implement overwriteInsert:
///
/// **Phase 1 — Stable zone** (upper 40% of tracks):
///   Place danmaku in the first empty or non-colliding track in the top 40%.
///   These tracks are NEVER overwritten, ensuring visual stability for the
///   upper portion of the screen even under extreme density.
///
/// **Phase 2 — Overflow zone** (bottom 60% of tracks):
///   When the stable zone is completely full (all tracks collide), overflow
///   danmaku into the lower 60%. Within this zone, placement works the same
///   way (empty track → non-colliding track), but also tracks the best
///   overwrite candidate (track with minimum right edge — the danmaku furthest
///   along its scroll path).
///
/// **Phase 3 — Overwrite** (all tracks full):
///   Clear the best candidate track in the overflow zone and place the new
///   danmaku there. The displaced (cleared) danmaku items are returned as
///   indices so the caller can mark them filtered.
///
/// **Special: is_me** — user's own danmaku always forces placement on track 0.
///
/// Ported from DanmakuFlameMaster's DanmakusRetainer with the top-40%-stable
/// extension to match Bilibili's overwriteInsert visual behavior.
fn select_scroll_track(
    new_entry: &TrackEntry,
    track_data: &mut TrackData,
    track_count: usize,
    view_width: f32,
    is_me: bool,
) -> Option<(usize, DisplacedIndices)> {
    track_data.compact(new_entry.time_ms, new_entry.duration_ms);

    let overwrite_count = ((track_count as f32 * 0.6).ceil() as usize)
        .max(1)
        .min(track_count);
    let overwrite_start = track_count - overwrite_count;

    let mut best_track = overwrite_start;
    let mut min_right_edge = f32::MAX;

    // Phase 1: Place in stable zone (upper 40% of tracks)
    // These tracks are never overwritten — danmaku here stay until they
    // naturally exit the screen, providing visual stability.
    for i in 0..overwrite_start {
        if track_data.tracks[i].is_empty() {
            track_data.tracks[i].push(new_entry.clone());
            return Some((i, SmallVec::new()));
        }
        let mut collides = false;
        for existing in &track_data.tracks[i] {
            if scroll_entries_collide(new_entry, existing, view_width) {
                collides = true;
                break;
            }
        }
        if !collides {
            track_data.tracks[i].push(new_entry.clone());
            return Some((i, SmallVec::new()));
        }
    }

    // Phase 2: Stable zone full — overflow to sacrifice zone (bottom 60%)
    // These tracks can be overwritten when capacity is exhausted.
    for i in overwrite_start..track_count {
        if track_data.tracks[i].is_empty() {
            track_data.tracks[i].push(new_entry.clone());
            return Some((i, SmallVec::new()));
        }
        let mut collides = false;
        let mut track_min_right = f32::MAX;
        for existing in &track_data.tracks[i] {
            if scroll_entries_collide(new_entry, existing, view_width) {
                collides = true;
            }
            let right_edge = entry_right_edge_at(existing, new_entry.time_ms, view_width);
            if right_edge < track_min_right {
                track_min_right = right_edge;
            }
        }
        if !collides {
            track_data.tracks[i].push(new_entry.clone());
            return Some((i, SmallVec::new()));
        }
        // Track best overwrite candidate in this zone
        if track_min_right < min_right_edge {
            min_right_edge = track_min_right;
            best_track = i;
        }
    }

    // Phase 3: All tracks collide — overwrite the best candidate in sacrifice zone.
    // The overwrite picks the track whose danmaku has the smallest right edge
    // (closest to exiting the screen), minimizing visual disruption.
    if is_me && track_count > 0 {
        let displaced: DisplacedIndices = track_data.tracks[0]
            .iter()
            .map(|e| e.danmaku_index)
            .collect();
        track_data.tracks[0].clear();
        track_data.tracks[0].push(new_entry.clone());
        return Some((0, displaced));
    }

    if min_right_edge < f32::MAX {
        let displaced: DisplacedIndices = track_data.tracks[best_track]
            .iter()
            .map(|e| e.danmaku_index)
            .collect();
        track_data.tracks[best_track].clear();
        track_data.tracks[best_track].push(new_entry.clone());
        return Some((best_track, displaced));
    }

    None
}

fn entry_right_edge_at(entry: &TrackEntry, time_ms: i64, view_width: f32) -> f32 {
    entry_x_at(entry, time_ms, view_width) + entry.paint_width
}

/// Compact expired entries from fixed tracks.
/// Unlike scroll tracks which compact based on time windows, fixed tracks chain items
/// sequentially (each starts when the previous ends). This removes items from the front
/// of each track's chain whose end time has passed, freeing tracks for new items.
/// Mirrors Next2's `compact_static_tracks` (which clears entire tracks when the item ends).
fn compact_fixed_tracks(tracks: &mut [Vec<TrackEntry>], current_time_ms: i64) {
    for track in tracks.iter_mut() {
        // Remove all entries from the front that have fully expired.
        // The chain structure guarantees entries are in time order and
        // entries[i].end_ms() == entries[i+1].time_ms (no gaps).
        let mut remove_count = 0;
        for entry in track.iter() {
            if entry.end_ms() <= current_time_ms {
                remove_count += 1;
            } else {
                break;
            }
        }
        if remove_count > 0 {
            track.drain(0..remove_count);
        }
    }
}

fn select_fixed_track(
    new_entry: &TrackEntry,
    track_data: &mut TrackData,
    track_count: usize,
) -> Option<usize> {
    let new_start = new_entry.time_ms;

    if new_start != track_data.last_compact_ms {
        track_data.last_compact_ms = new_start;
        compact_fixed_tracks(&mut track_data.tracks, new_start);
    }

    let tracks = &mut track_data.tracks;
    for i in 0..track_count {
        if tracks[i].is_empty() {
            tracks[i].push(new_entry.clone());
            return Some(i);
        }
        let last = tracks[i].last().unwrap();
        let last_end = last.end_ms();
        if new_start >= last_end {
            tracks[i].push(new_entry.clone());
            return Some(i);
        }
    }

    None
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

    if check_hit_same_type(
        d1.danmaku_type,
        d1_left_at_d2_start,
        d1_right_at_d2_start,
        d2_left_at_start,
        d2_left_at_start + d2.paint_width,
    ) {
        return true;
    }

    let d1_left_at_d1_end = entry_left_at(d1, d1.end_ms(), view_width);
    let d1_right_at_d1_end = d1_left_at_d1_end + d1.paint_width;
    let d2_left_at_d1_end = entry_left_at(d2, d1.end_ms(), view_width);

    check_hit_same_type(
        d1.danmaku_type,
        d1_left_at_d1_end,
        d1_right_at_d1_end,
        d2_left_at_d1_end,
        d2_left_at_d1_end + d2.paint_width,
    )
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
        DanmakuType::ScrollRL => view_width - elapsed * entry.step_x,
        DanmakuType::ScrollLR => elapsed * entry.step_x - entry.paint_width,
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

    fn make_scroll_item(
        time_ms: i64,
        text: &str,
        paint_width: f32,
        danmaku_type: DanmakuType,
        duration_ms: i64,
        view_width: f32,
    ) -> DanmakuItem {
        let mut item = DanmakuItem::new(
            time_ms,
            text.into(),
            0xFFFFFFFF,
            25.0,
            danmaku_type,
            duration_ms,
        );
        item.paint_width = paint_width;
        item.paint_height = 30.0;
        item.step_x = calc_step_x(paint_width, duration_ms, view_width);
        item
    }

    fn make_fixed_item(
        time_ms: i64,
        text: &str,
        danmaku_type: DanmakuType,
        duration_ms: i64,
    ) -> DanmakuItem {
        let mut item = DanmakuItem::new(
            time_ms,
            text.into(),
            0xFFFFFFFF,
            25.0,
            danmaku_type,
            duration_ms,
        );
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
        assert!(
            (item.y - 2.0).abs() < 1.0,
            "first item y={} should be ~2.0",
            item.y
        );
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
        assert!(
            items[1].y > first_y,
            "same-time items should be on different tracks: first_y={}, second_y={}",
            first_y,
            items[1].y
        );
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
        assert!(
            (items[1].y - first_y).abs() < 1.0,
            "non-overlapping items should share track: first_y={}, second_y={}",
            first_y,
            items[1].y
        );
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
        assert!(
            items[1].y > first_y,
            "same-time fixed items should be on different tracks"
        );
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
        assert!(
            (items[1].y - first_y).abs() < 1.0,
            "expired fixed item should be replaced: first_y={}, second_y={}",
            first_y,
            items[1].y
        );
    }

    #[test]
    fn test_scroll_collision_same_time() {
        let d1 = TrackEntry {
            time_ms: 0,
            duration_ms: 5000,
            paint_width: 100.0,
            step_x: calc_step_x(100.0, 5000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 0,
        };
        let d2 = TrackEntry {
            time_ms: 0,
            duration_ms: 5000,
            paint_width: 100.0,
            step_x: calc_step_x(100.0, 5000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 1,
        };
        assert!(scroll_entries_collide(&d1, &d2, 1920.0));
    }

    #[test]
    fn test_scroll_no_collision_far_apart() {
        let d1 = TrackEntry {
            time_ms: 0,
            duration_ms: 3000,
            paint_width: 100.0,
            step_x: calc_step_x(100.0, 3000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 0,
        };
        let d2 = TrackEntry {
            time_ms: 10000,
            duration_ms: 3000,
            paint_width: 100.0,
            step_x: calc_step_x(100.0, 3000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 1,
        };
        assert!(!scroll_entries_collide(&d1, &d2, 1920.0));
    }

    #[test]
    fn test_scroll_x_position() {
        let entry = TrackEntry {
            time_ms: 0,
            duration_ms: 5000,
            paint_width: 100.0,
            step_x: calc_step_x(100.0, 5000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 0,
        };
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

        // Only one track fits (view_height=60, track_height=45, track_count=1).
        let (placed0, _) = retainer.fix(&mut items[0], 1920.0, 60.0, &flags, 1.0, false);
        assert!(placed0, "first item should be placed in the only track");

        // Second item: track still occupied → dropped (Next2 behavior).
        let (placed1, _) = retainer.fix(&mut items[1], 1920.0, 60.0, &flags, 1.0, false);
        assert!(
            !placed1,
            "second item should be dropped when all tracks are full"
        );
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
        assert!(
            (items[0].y - items[1].y).abs() > 1.0,
            "different-width same-time items must be on different tracks: wide_y={}, narrow_y={}",
            items[0].y,
            items[1].y
        );
    }

    #[test]
    fn test_many_same_time_no_y_overlap() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);

        let texts: Vec<String> = (0..15).map(|i| format!("弹幕{}", i)).collect();
        let mut items: Vec<DanmakuItem> = texts
            .iter()
            .map(|text| make_scroll_item(1000, text, 150.0, DanmakuType::ScrollRL, 5000, 1920.0))
            .collect();

        let mut placed_ys = Vec::new();
        for item in &mut items {
            let (placed, _) = retainer.fix(item, 1920.0, 1080.0, &flags, 1.0, false);
            if placed {
                placed_ys.push(item.y);
            }
        }

        for i in 0..placed_ys.len() {
            for j in (i + 1)..placed_ys.len() {
                assert!(
                    (placed_ys[i] - placed_ys[j]).abs() > 1.0,
                    "items {} and {} share y={}",
                    i,
                    j,
                    placed_ys[i]
                );
            }
        }
    }

    #[test]
    fn test_chain_queue_fixed_items() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items: Vec<DanmakuItem> = (0..4)
            .map(|i| {
                let mut item = make_fixed_item(0, &format!("top{}", i), DanmakuType::FixTop, 3800);
                item.index = i as u32;
                item
            })
            .collect();

        // Only one track fits (view_height=60, track_height=45).
        // First item gets placed; subsequent items are dropped (Next2 behavior).
        for i in 0..items.len() {
            items[i].index = i as u32;
            let (placed, _) = retainer.fix(&mut items[i], 1920.0, 60.0, &flags, 1.0, false);
            if i == 0 {
                assert!(placed, "item 0 should be placed (first on empty track)");
                assert_eq!(items[0].time_ms, 0);
            } else {
                assert!(
                    !placed,
                    "item {} should be dropped when all tracks are full",
                    i
                );
            }
        }
    }

    #[test]
    fn test_staggered_items_tracks() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);

        let mut items: Vec<DanmakuItem> = (0..10)
            .map(|i| {
                make_scroll_item(
                    i * 100,
                    &format!("item_{}", i),
                    150.0,
                    DanmakuType::ScrollRL,
                    5000,
                    1920.0,
                )
            })
            .collect();

        for item in &mut items {
            retainer.fix(item, 1920.0, 1080.0, &flags, 1.0, false);
        }

        for i in 0..items.len() {
            for j in (i + 1)..items.len() {
                let time_diff = (items[j].time_ms - items[i].time_ms).abs();
                if time_diff < 5000 {
                    let y_diff = (items[i].y - items[j].y).abs();
                    if y_diff < 1.0 && items[i].y >= 0.0 && items[j].y >= 0.0 {
                        println!(
                            "Same track: item_{} (t={}) and item_{} (t={}), y={}",
                            i, items[i].time_ms, j, items[j].time_ms, items[i].y
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn test_fixed_top_overlap_no_visual_overlap() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items: Vec<DanmakuItem> = (0..5)
            .map(|i| make_fixed_item(0, &format!("top{}", i), DanmakuType::FixTop, 3800))
            .collect();

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
            for j in (i + 1)..visible_ys.len() {
                assert!(
                    (visible_ys[i] - visible_ys[j]).abs() > 1.0,
                    "visible items {} and {} share y={}, causing visual overlap",
                    i,
                    j,
                    visible_ys[i]
                );
            }
        }
    }

    #[test]
    fn test_fix_bottom_overflow_queues_correctly() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let mut items: Vec<DanmakuItem> = (0..4)
            .map(|i| {
                let mut item =
                    make_fixed_item(0, &format!("bottom{}", i), DanmakuType::FixBottom, 3800);
                item.index = i as u32;
                item
            })
            .collect();

        // Only one track fits (view_height=60, track_height=45).
        // First item gets placed in the only track; rest are dropped.
        for i in 0..items.len() {
            items[i].index = i as u32;
            let (placed, _) = retainer.fix(&mut items[i], 1920.0, 60.0, &flags, 1.0, false);
            if i == 0 {
                assert!(placed, "item 0 should be placed");
                assert_eq!(items[0].time_ms, 0);
            } else {
                assert!(
                    !placed,
                    "item {} should be dropped when all tracks are full",
                    i
                );
            }
        }
    }

    #[test]
    fn test_long_danmaku_catches_short() {
        let short = TrackEntry {
            time_ms: 0,
            duration_ms: 8000,
            paint_width: 50.0,
            step_x: calc_step_x(50.0, 8000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 0,
        };
        let long = TrackEntry {
            time_ms: 1000,
            duration_ms: 8000,
            paint_width: 400.0,
            step_x: calc_step_x(400.0, 8000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 1,
        };
        assert!(
            scroll_entries_collide(&short, &long, 1920.0),
            "long danmaku starting later should catch up to short danmaku on same track"
        );
    }

    #[test]
    fn test_no_false_positive_at_start() {
        let short = TrackEntry {
            time_ms: 0,
            duration_ms: 8000,
            paint_width: 50.0,
            step_x: calc_step_x(50.0, 8000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 0,
        };
        let long = TrackEntry {
            time_ms: 1000,
            duration_ms: 8000,
            paint_width: 400.0,
            step_x: calc_step_x(400.0, 8000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 1,
        };
        let short_left = entry_left_at(&short, 1000, 1920.0);
        let short_right = short_left + short.paint_width;
        let long_left = entry_left_at(&long, 1000, 1920.0);
        assert!(
            long_left >= short_right,
            "at d2 start: long.left={} should be >= short.right={} (no overlap yet)",
            long_left,
            short_right
        );
    }

    #[test]
    fn test_catch_up_at_end() {
        let short = TrackEntry {
            time_ms: 0,
            duration_ms: 8000,
            paint_width: 50.0,
            step_x: calc_step_x(50.0, 8000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 0,
        };
        let long = TrackEntry {
            time_ms: 1000,
            duration_ms: 8000,
            paint_width: 400.0,
            step_x: calc_step_x(400.0, 8000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 1,
        };
        let short_left = entry_left_at(&short, 8000, 1920.0);
        let short_right = short_left + short.paint_width;
        let long_left = entry_left_at(&long, 8000, 1920.0);
        assert!(
            long_left < short_right,
            "at d1 end: long.left={} should be < short.right={} (catch-up happened)",
            long_left,
            short_right
        );
    }

    #[test]
    fn test_no_collision_when_far_apart_in_time() {
        let short = TrackEntry {
            time_ms: 0,
            duration_ms: 8000,
            paint_width: 50.0,
            step_x: calc_step_x(50.0, 8000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 0,
        };
        let long = TrackEntry {
            time_ms: 7000,
            duration_ms: 8000,
            paint_width: 400.0,
            step_x: calc_step_x(400.0, 8000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 1,
        };
        assert!(!scroll_entries_collide(&short, &long, 1920.0),
            "long danmaku starting 7s later should not catch short (short ends at 8s, only 1s overlap window not enough)");
    }

    #[test]
    fn test_long_short_different_tracks() {
        let flags = GlobalFlags::default();
        let mut retainer = DanmakuRetainer::new(2.0, 0.15);
        let mut short_item = make_scroll_item(0, "短", 50.0, DanmakuType::ScrollRL, 8000, 1920.0);
        let mut long_item = make_scroll_item(
            1000,
            "很长很长的弹幕内容在这里",
            400.0,
            DanmakuType::ScrollRL,
            8000,
            1920.0,
        );

        retainer.fix(&mut short_item, 1920.0, 1080.0, &flags, 1.0, false);
        retainer.fix(&mut long_item, 1920.0, 1080.0, &flags, 1.0, false);

        assert!(
            (short_item.y - long_item.y).abs() > 1.0,
            "long danmaku (y={}) should be on different track from short (y={}) to avoid catch-up",
            long_item.y,
            short_item.y
        );
    }

    #[test]
    fn test_check_hit_direction_rtl() {
        let d1 = TrackEntry {
            time_ms: 0,
            duration_ms: 5000,
            paint_width: 100.0,
            step_x: calc_step_x(100.0, 5000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 0,
        };
        let d2 = TrackEntry {
            time_ms: 500,
            duration_ms: 5000,
            paint_width: 100.0,
            step_x: calc_step_x(100.0, 5000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 1,
        };

        assert!(
            !scroll_entries_collide(&d1, &d2, 1920.0),
            "same-speed danmaku 500ms apart should NOT collide (they maintain distance)"
        );

        let d1_fast = TrackEntry {
            time_ms: 0,
            duration_ms: 8000,
            paint_width: 50.0,
            step_x: calc_step_x(50.0, 8000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 0,
        };
        let d2_slow = TrackEntry {
            time_ms: 1000,
            duration_ms: 8000,
            paint_width: 400.0,
            step_x: calc_step_x(400.0, 8000, 1920.0),
            danmaku_type: DanmakuType::ScrollRL,
            danmaku_index: 1,
        };

        let t_start = 1000;
        let d1_right_at_start = entry_left_at(&d1_fast, t_start, 1920.0) + d1_fast.paint_width;
        let d2_left_at_start = entry_left_at(&d2_slow, t_start, 1920.0);
        assert!(
            d2_left_at_start >= d1_right_at_start,
            "at d2 start: d2.left={} should be >= d1.right={} (no overlap yet, d2 just entered)",
            d2_left_at_start,
            d1_right_at_start
        );

        let t_end = 8000;
        let d1_right_at_end = entry_left_at(&d1_fast, t_end, 1920.0) + d1_fast.paint_width;
        let d2_left_at_end = entry_left_at(&d2_slow, t_end, 1920.0);
        assert!(
            d2_left_at_end < d1_right_at_end,
            "at d1 end: d2.left={} should be < d1.right={} (long danmaku caught up!)",
            d2_left_at_end,
            d1_right_at_end
        );

        assert!(
            scroll_entries_collide(&d1_fast, &d2_slow, 1920.0),
            "long fast danmaku should collide with short slow danmaku"
        );
    }

    #[test]
    fn test_overwrite_insert_overflow_to_lower_60_percent() {
        // Verifies that when the upper 40% of tracks (stable zone) is full,
        // danmaku overflow into the lower 60% (overflow zone), creating the
        // expected visual pattern: stable upper region, dynamic lower region.
        let flags = GlobalFlags::default();
        // track_height = 30 + 30*0.5 = 45, effective_height = 1080 * 0.75 = 810
        // track_count = floor(810 / 45) = 18
        let mut retainer = DanmakuRetainer::new(2.0, 0.5);
        let view_width = 1920.0f32;
        let view_height = 1080.0f32;
        let display_area = 1.0f32;

        // Generate many same-time danmaku to force overflow
        let mut items: Vec<DanmakuItem> = (0..30)
            .map(|i| {
                let mut item = make_scroll_item(
                    0,
                    &format!("dm{}", i),
                    150.0,
                    DanmakuType::ScrollRL,
                    5000,
                    view_width,
                );
                item.index = i;
                item
            })
            .collect();

        // Place all items through the retainer, collecting displaced indices
        // to apply filtering afterwards (avoids borrow conflicts).
        let mut displaced_all: Vec<usize> = Vec::new();
        for item in &mut items {
            let (placed, displaced) = retainer.fix(item, view_width, view_height, &flags, display_area, false);
            if !placed {
                item.is_filtered = true;
                item.filter_param = 99;
            }
            displaced_all.extend(displaced.iter().copied());
        }
        for &displaced_idx in &displaced_all {
            if displaced_idx < items.len() {
                items[displaced_idx].is_filtered = true;
                items[displaced_idx].filter_param = 99;
            }
        }

        // Collect Y positions of non-filtered (visible) items
        let visible: Vec<(&str, f32)> = items
            .iter()
            .filter(|i| !i.is_filtered)
            .map(|i| (i.text.as_str(), i.y))
            .collect();

        eprintln!("Visible {} items out of {}", visible.len(), items.len());
        for (text, y) in &visible {
            eprintln!("  {}: y={}", text, y);
        }

        // Compute track properties for assertions
        let track_height = 30.0 + 30.0 * 0.5; // 45.0
        let effective_height = view_height * display_area.min(0.75); // 810.0
        let track_count = (effective_height / track_height).floor() as usize; // 18
        let overwrite_count = ((track_count as f32 * 0.6).ceil() as usize)
            .max(1)
            .min(track_count);
        let overwrite_start = track_count - overwrite_count;
        let stable_zone_max_y = 2.0 + (overwrite_start - 1) as f32 * track_height;
        let overflow_zone_min_y = 2.0 + overwrite_start as f32 * track_height;

        eprintln!(
            "track_count={}, overwrite_start={}, overwrite_count={}, stable_max_y={:.0}, overflow_min_y={:.0}",
            track_count, overwrite_start, overwrite_count, stable_zone_max_y, overflow_zone_min_y
        );

        // Verify overflow: at least one VISIBLE item should be placed in the overflow zone
        // (y >= overflow_zone_min_y). This is the key behavior the fix enables:
        // when the stable zone is full, danmaku must appear in the lower 60%.
        let overflow_visible: Vec<_> = visible
            .iter()
            .filter(|(_, y)| *y >= overflow_zone_min_y)
            .collect();

        assert!(
            !overflow_visible.is_empty(),
            "Expected danmaku in overflow zone (y >= {:.0}), but all {} visible items are in stable zone only. \
             This means the overwriteInsert overflow mechanism is not working correctly.",
            overflow_zone_min_y,
            visible.len(),
        );

        eprintln!(
            "Overflow zone contains {} visible items (expected > 0)",
            overflow_visible.len()
        );

        // Verify the stable zone still has items (protected from overwrite)
        let stable_visible: Vec<_> = visible
            .iter()
            .filter(|(_, y)| *y <= stable_zone_max_y)
            .collect();
        eprintln!("Stable zone contains {} visible items", stable_visible.len());
        assert!(
            !stable_visible.is_empty(),
            "Stable zone should also contain items"
        );

        // Verify no more items than tracks can be simultaneously visible
        // (each track can host at most one visible item at a time with all-same-time danmaku)
        assert!(
            visible.len() <= track_count,
            "Expected at most {} visible items (one per track), got {}",
            track_count,
            visible.len()
        );
    }
}
