/// Core data model for DFM+ danmaku engine.
/// Ported from Bilibili DanmakuFlameMaster's BaseDanmaku, Duration, GlobalFlagValues.

/// Danmaku type enumeration.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DanmakuType {
    ScrollRL = 1,
    ScrollLR = 6,
    FixTop = 5,
    FixBottom = 4,
    Special = 7,
}

impl DanmakuType {
    pub fn from_code(code: i32) -> Self {
        match code {
            1 => DanmakuType::ScrollRL,
            6 => DanmakuType::ScrollLR,
            5 => DanmakuType::FixTop,
            4 => DanmakuType::FixBottom,
            7 => DanmakuType::Special,
            _ => DanmakuType::ScrollRL,
        }
    }

    pub fn is_scroll(&self) -> bool {
        matches!(self, DanmakuType::ScrollRL | DanmakuType::ScrollLR)
    }

    pub fn is_fixed(&self) -> bool {
        matches!(self, DanmakuType::FixTop | DanmakuType::FixBottom)
    }
}

/// Duration with multiplicative speed factor.
/// Ported from Duration.java: value = initial_duration * factor.
#[derive(Debug, Clone, Copy)]
pub struct Duration {
    initial_duration: i64,
    factor: f32,
    pub value: i64,
}

impl Duration {
    pub fn new(initial_duration: i64) -> Self {
        Self {
            initial_duration,
            factor: 1.0,
            value: initial_duration,
        }
    }

    pub fn set_factor(&mut self, f: f32) {
        if (self.factor - f).abs() > f32::EPSILON {
            self.factor = f;
            self.value = (self.initial_duration as f32 * f) as i64;
        }
    }

    pub fn factor(&self) -> f32 {
        self.factor
    }
}

/// Epoch-based dirty flags, grouped for cache locality.
/// Ported from GlobalFlagValues.java. Incrementing a flag invalidates all
/// danmaku items whose per-instance flag doesn't match, without iteration.
#[derive(Debug, Clone, Copy)]
pub struct GlobalFlags {
    pub measure_flag: u64,
    pub visible_flag: u64,
    pub filter_flag: u64,
    pub first_shown_flag: u64,
    pub sync_offset_flag: u64,
    pub prepare_flag: u64,
}

impl Default for GlobalFlags {
    fn default() -> Self {
        Self {
            measure_flag: 1,
            visible_flag: 1,
            filter_flag: 1,
            first_shown_flag: 1,
            sync_offset_flag: 1,
            prepare_flag: 1,
        }
    }
}

impl GlobalFlags {
    pub fn reset_all(&mut self) {
        self.measure_flag = 0;
        self.visible_flag = 0;
        self.filter_flag = 0;
        self.first_shown_flag = 0;
        self.sync_offset_flag = 0;
        self.prepare_flag = 0;
    }

    pub fn update_measure(&mut self) {
        self.measure_flag += 1;
    }
    pub fn update_visible(&mut self) {
        self.visible_flag += 1;
    }
    pub fn update_filter(&mut self) {
        self.filter_flag += 1;
    }
    pub fn update_first_shown(&mut self) {
        self.first_shown_flag += 1;
    }
    pub fn update_sync_offset(&mut self) {
        self.sync_offset_flag += 1;
    }
    pub fn update_prepare(&mut self) {
        self.prepare_flag += 1;
    }
}

/// Per-item epoch flags, matching GlobalFlags for dirty-checking.
#[derive(Debug, Clone, Default)]
pub struct EpochFlags {
    pub measure: u64,
    pub visible: u64,
    pub filter: u64,
    pub first_shown: u64,
    pub sync_offset: u64,
    pub prepare: u64,
}

/// Special danmaku path segment for linear interpolation.
#[derive(Debug, Clone)]
pub struct LinePath {
    pub begin_x: f32,
    pub begin_y: f32,
    pub end_x: f32,
    pub end_y: f32,
    pub begin_time: i64,
    pub end_time: i64,
}

/// Core danmaku item data structure.
/// Ported from BaseDanmaku.java with all fields needed for layout and rendering.
#[derive(Debug, Clone)]
pub struct DanmakuItem {
    // -- Identity & content --
    pub time_ms: i64,
    pub time_offset: i64,
    pub text: String,
    pub text_color: u32,
    pub border_color: u32,
    pub text_size: f32,
    pub danmaku_type: DanmakuType,
    pub index: u32,
    pub priority: u8,
    pub alpha: u8,

    // -- Duration --
    pub duration_ms: i64,

    // -- Measured dimensions (set after measure) --
    pub paint_width: f32,
    pub paint_height: f32,

    // -- Layout results --
    pub x: f32,
    pub y: f32,
    pub is_shown: bool,

    // -- Filtering state --
    pub is_filtered: bool,
    pub filter_param: u32,

    // -- Epoch-based dirty flags --
    pub flags: EpochFlags,

    // -- Scroll physics (computed after measure) --
    pub step_x: f32, // pixels per millisecond

    // -- Special danmaku fields --
    pub line_paths: Option<Vec<LinePath>>,
    pub begin_alpha: u8,
    pub end_alpha: u8,
    pub alpha_duration_ms: i64,
}

impl DanmakuItem {
    pub fn new(
        time_ms: i64,
        text: String,
        text_color: u32,
        text_size: f32,
        danmaku_type: DanmakuType,
        duration_ms: i64,
    ) -> Self {
        Self {
            time_ms,
            time_offset: 0,
            text,
            text_color,
            border_color: 0xFF000000,
            text_size,
            danmaku_type,
            index: 0,
            priority: 0,
            alpha: 255,
            duration_ms,
            paint_width: -1.0,
            paint_height: -1.0,
            x: 0.0,
            y: -1.0,
            is_shown: false,
            is_filtered: false,
            filter_param: 0,
            flags: EpochFlags::default(),
            step_x: 0.0,
            line_paths: None,
            begin_alpha: 255,
            end_alpha: 255,
            alpha_duration_ms: 0,
        }
    }

    /// Get the actual display time, accounting for sync offset.
    /// Ported from BaseDanmaku.getActualTime().
    pub fn get_actual_time(&self, global_flags: &GlobalFlags) -> i64 {
        if self.flags.sync_offset == global_flags.sync_offset_flag {
            self.time_ms + self.time_offset
        } else {
            self.time_ms
        }
    }

    /// Check if this danmaku has been measured.
    pub fn is_measured(&self, global_flags: &GlobalFlags) -> bool {
        self.paint_width > -1.0
            && self.paint_height > -1.0
            && self.flags.measure == global_flags.measure_flag
    }

    /// Check if this danmaku is timed out at the given time.
    pub fn is_time_out(&self, ctime: i64, global_flags: &GlobalFlags) -> bool {
        ctime - self.get_actual_time(global_flags) >= self.duration_ms
    }

    /// Check if this danmaku is outside the visible time window.
    pub fn is_outside(&self, ctime: i64, global_flags: &GlobalFlags) -> bool {
        let dtime = ctime - self.get_actual_time(global_flags);
        dtime <= 0 || dtime >= self.duration_ms
    }

    /// Check if this danmaku's start time is in the future.
    pub fn is_late(&self, timer_ms: i64, global_flags: &GlobalFlags) -> bool {
        timer_ms < self.get_actual_time(global_flags)
    }

    /// Check if this danmaku is visible.
    pub fn is_shown_state(&self, global_flags: &GlobalFlags) -> bool {
        self.is_shown && self.flags.visible == global_flags.visible_flag
    }

    /// Check if the filter state is current.
    pub fn has_passed_filter(&mut self, global_flags: &GlobalFlags) -> bool {
        if self.flags.filter != global_flags.filter_flag {
            self.filter_param = 0;
            return false;
        }
        true
    }

    /// Check if this danmaku is filtered.
    pub fn is_filtered_state(&self, global_flags: &GlobalFlags) -> bool {
        self.flags.filter == global_flags.filter_flag && self.filter_param != 0
    }

    /// Measure the danmaku dimensions based on text content.
    /// Uses a heuristic similar to Next2's measure_text_width.
    /// `outline_width` is added to paint_width to account for text outline rendering.
    pub fn measure(&mut self, view_width: f32, _view_height: f32, global_flags: &GlobalFlags) {
        self.measure_with_outline(view_width, _view_height, global_flags, 0.0);
    }

    /// Measure with explicit outline width for accurate collision detection.
    pub fn measure_with_outline(
        &mut self,
        view_width: f32,
        _view_height: f32,
        global_flags: &GlobalFlags,
        outline_width: f32,
    ) {
        if self.is_measured(global_flags) {
            return;
        }
        let raw_width = measure_text_width(&self.text, self.text_size) * 1.15;
        self.paint_width = raw_width + outline_width * 2.0;
        self.paint_height = self.text_size * 1.2;

        // Compute scroll step
        if self.danmaku_type.is_scroll() {
            let distance = view_width + self.paint_width;
            self.step_x = distance / self.duration_ms as f32;
        }

        self.flags.measure = global_flags.measure_flag;
    }

    /// Get the bounding rectangle at a specific time.
    /// Returns [left, top, right, bottom].
    pub fn get_rect_at_time(
        &self,
        view_width: f32,
        time_ms: i64,
        global_flags: &GlobalFlags,
    ) -> [f32; 4] {
        let actual_time = self.get_actual_time(global_flags);
        let elapsed = time_ms - actual_time;
        let left = match self.danmaku_type {
            DanmakuType::ScrollRL => {
                if elapsed >= self.duration_ms {
                    -self.paint_width
                } else {
                    view_width - elapsed as f32 * self.step_x
                }
            }
            DanmakuType::ScrollLR => {
                if elapsed >= self.duration_ms {
                    view_width
                } else {
                    elapsed as f32 * self.step_x - self.paint_width
                }
            }
            DanmakuType::FixTop | DanmakuType::FixBottom => (view_width - self.paint_width) / 2.0,
            DanmakuType::Special => self.get_special_x_at_time(view_width, time_ms, global_flags),
        };
        [
            left,
            self.y,
            left + self.paint_width,
            self.y + self.paint_height,
        ]
    }

    fn get_special_x_at_time(
        &self,
        _view_width: f32,
        time_ms: i64,
        global_flags: &GlobalFlags,
    ) -> f32 {
        let actual_time = self.get_actual_time(global_flags);
        let elapsed = (time_ms - actual_time).max(0) as f32;
        let Some(ref paths) = self.line_paths else {
            return self.x;
        };
        let progress = if self.duration_ms > 0 {
            elapsed / self.duration_ms as f32
        } else {
            1.0
        }
        .clamp(0.0, 1.0);

        // Find the current path segment
        let total_len: f32 = paths
            .iter()
            .map(|p| ((p.end_x - p.begin_x).powi(2) + (p.end_y - p.begin_y).powi(2)).sqrt())
            .sum();
        if total_len <= 0.0 {
            return self.x;
        }

        let target_dist = progress * total_len;
        let mut accumulated = 0.0f32;
        for path in paths {
            let seg_len =
                ((path.end_x - path.begin_x).powi(2) + (path.end_y - path.begin_y).powi(2)).sqrt();
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
        paths.last().map_or(self.x, |p| p.end_x)
    }
}

/// Heuristic text width measurement.
/// Ported from Next2's measure_text_width: CJK=1.0em, ASCII=0.55em, whitespace=0.35em.
pub fn measure_text_width(text: &str, font_size: f32) -> f32 {
    let mut width = 0.0f32;
    for ch in text.chars() {
        width += char_width(ch) * font_size;
    }
    width.max(1.0)
}

fn char_width(ch: char) -> f32 {
    let cp = ch as u32;
    if ch.is_whitespace() {
        0.35
    } else if is_wide_char(cp) {
        1.0
    } else {
        0.55
    }
}

fn is_wide_char(cp: u32) -> bool {
    matches!(cp,
        0x4E00..=0x9FFF |   // CJK Unified Ideographs
        0x3400..=0x4DBF |   // CJK Extension A
        0x3000..=0x303F |   // CJK Symbols
        0x3040..=0x309F |   // Hiragana
        0x30A0..=0x30FF |   // Katakana
        0xAC00..=0xD7AF |   // Hangul
        0xFF00..=0xFFEF |   // Fullwidth Forms
        0xF900..=0xFAFF |   // CJK Compatibility Ideographs
        0x2E80..=0x2EFF |   // CJK Radicals
        0xFE30..=0xFE4F |   // CJK Compatibility Forms
        0x20000..=0x2A6DF | // CJK Extension B
        0x2A700..=0x2B73F | // CJK Extension C
        0x2B740..=0x2B81F   // CJK Extension D
    )
}

/// Configuration for DFM+ engine.
#[derive(Debug, Clone)]
pub struct DfmConfig {
    pub view_width: f32,
    pub view_height: f32,
    pub font_size: f32,
    pub display_area: f32,
    pub scroll_speed_factor: f32,
    pub max_lines: Option<u32>,
    pub max_quantity: Option<u32>,
    pub merge_duplicate: bool,
    pub merge_window_seconds: f32,
    pub allow_stacking: bool,
}

impl Default for DfmConfig {
    fn default() -> Self {
        Self {
            view_width: 1920.0,
            view_height: 1080.0,
            font_size: 25.0,
            display_area: 1.0,
            scroll_speed_factor: 1.0,
            max_lines: None,
            max_quantity: None,
            merge_duplicate: false,
            merge_window_seconds: 45.0,
            allow_stacking: false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_duration_factor() {
        let mut d = Duration::new(3800);
        assert_eq!(d.value, 3800);
        d.set_factor(1.5);
        assert_eq!(d.value, 5700);
    }

    #[test]
    fn test_measure_text_width() {
        let w = measure_text_width("你好世界", 25.0);
        assert!((w - 100.0).abs() < 1.0); // 4 CJK chars * 1.0em * 25px
        let w2 = measure_text_width("Hello", 25.0);
        assert!((w2 - 68.75).abs() < 1.0); // 5 ASCII * 0.55em * 25px
    }

    #[test]
    fn test_r2l_position() {
        let flags = GlobalFlags::default();
        let mut item = DanmakuItem::new(
            0,
            "test".into(),
            0xFFFFFFFF,
            25.0,
            DanmakuType::ScrollRL,
            5000,
        );
        item.measure(1920.0, 1080.0, &flags);
        // At time 0, x should be at the right edge
        let rect = item.get_rect_at_time(1920.0, 0, &flags);
        assert!((rect[0] - 1920.0).abs() < 1.0);
        // At time 5000ms, x should be at -paint_width
        let rect = item.get_rect_at_time(1920.0, 5000, &flags);
        assert!(rect[0] <= 0.0);
    }

    #[test]
    fn test_danmaku_type_from_code() {
        assert_eq!(DanmakuType::from_code(1), DanmakuType::ScrollRL);
        assert_eq!(DanmakuType::from_code(6), DanmakuType::ScrollLR);
        assert_eq!(DanmakuType::from_code(5), DanmakuType::FixTop);
        assert_eq!(DanmakuType::from_code(4), DanmakuType::FixBottom);
    }
}
