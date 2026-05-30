/// Danmaku filtering system.
/// Ported from DanmakuFilters.java with support for:
/// - Type blocking
/// - Quantity density control
/// - Elapsed time protection
/// - Maximum lines
/// - Duplicate merging
/// - Overlapping detection
/// - Keyword/user blocking

use rustc_hash::{FxHashMap, FxHashSet};
use regex::Regex;

use crate::dfm_core::model::{DanmakuItem, DanmakuType, Duration, GlobalFlags};

/// Context passed to filters during the rendering loop.
#[derive(Debug)]
pub struct FilterContext {
    pub timer_ms: i64,
    pub index_in_screen: usize,
    pub screen_size: usize,
    pub frame_elapsed_ms: u64,
    pub global_flags: GlobalFlags,
    pub scroll_duration: Duration,
}

/// Secondary filter state from the retainer.
#[derive(Debug, Clone)]
pub struct RetainerState {
    pub will_hit: bool,
    pub line_number: u32,
}

/// Complete filter system.
#[derive(Debug)]
pub struct FilterSystem {
    pub blocked_types: FxHashSet<DanmakuType>,
    pub max_quantity: Option<u32>,
    pub max_lines: FxHashMap<DanmakuType, u32>,
    pub overlapping_filter: FxHashMap<DanmakuType, bool>,
    pub blocked_users: FxHashSet<String>,
    pub blocked_keywords: Vec<String>,
    pub blocked_regexes: Vec<Regex>,
    pub duplicate_merge: bool,
    pub elapsed_time_limit_ms: u64,
    last_skipped_time: Option<i64>,
    current_duplicates: FxHashMap<String, i64>,
    blocked_duplicates: FxHashSet<String>,
    passed_duplicates: FxHashSet<String>,
}

impl Default for FilterSystem {
    fn default() -> Self {
        Self {
            blocked_types: FxHashSet::default(),
            max_quantity: None,
            max_lines: FxHashMap::default(),
            overlapping_filter: FxHashMap::default(),
            blocked_users: FxHashSet::default(),
            blocked_keywords: Vec::new(),
            blocked_regexes: Vec::new(),
            duplicate_merge: false,
            elapsed_time_limit_ms: 20,
            last_skipped_time: None,
            current_duplicates: FxHashMap::default(),
            blocked_duplicates: FxHashSet::default(),
            passed_duplicates: FxHashSet::default(),
        }
    }
}

impl FilterSystem {
    /// Primary filter: runs before layout during the main rendering loop.
    /// Returns true if the danmaku should be filtered (hidden).
    /// Ported from DanmakuFilters.filter().
    pub fn filter_primary(&mut self, item: &mut DanmakuItem, ctx: &FilterContext) -> bool {
        // Type filter
        if self.blocked_types.contains(&item.danmaku_type) {
            item.is_filtered = true;
            item.filter_param = 1;
            item.flags.filter = ctx.global_flags.filter_flag;
            return true;
        }

        // Quantity density filter (only for scroll types)
        if item.danmaku_type.is_scroll() {
            if self.filter_quantity(item, ctx) {
                item.is_filtered = true;
                item.filter_param = 2;
                item.flags.filter = ctx.global_flags.filter_flag;
                return true;
            }
        }

        // Elapsed time filter (performance protection)
        if ctx.frame_elapsed_ms >= self.elapsed_time_limit_ms && item.is_outside(ctx.timer_ms, &ctx.global_flags) {
            item.is_filtered = true;
            item.filter_param = 3;
            item.flags.filter = ctx.global_flags.filter_flag;
            return true;
        }

        // Keyword filter
        if self.filter_keywords(item) {
            item.is_filtered = true;
            item.filter_param = 4;
            item.flags.filter = ctx.global_flags.filter_flag;
            return true;
        }

        // Duplicate merging filter
        if self.duplicate_merge && self.filter_duplicate(item, ctx) {
            item.is_filtered = true;
            item.filter_param = 5;
            item.flags.filter = ctx.global_flags.filter_flag;
            return true;
        }

        item.is_filtered = false;
        item.filter_param = 0;
        false
    }

    /// Secondary filter: runs after collision avoidance.
    /// Returns true if the danmaku should be filtered.
    /// Ported from DanmakuFilters.filterSecondary().
    pub fn filter_secondary(&self, item: &mut DanmakuItem, state: &RetainerState, _flags: &GlobalFlags) -> bool {
        // Maximum lines filter
        if let Some(&max) = self.max_lines.get(&item.danmaku_type) {
            if state.line_number >= max {
                return true;
            }
        }

        // Overlapping filter
        if let Some(&enabled) = self.overlapping_filter.get(&item.danmaku_type) {
            if enabled && state.will_hit {
                return true;
            }
        }

        false
    }

    /// Quantity density filter.
    /// Ported from QuantityDanmakuFilter.needFilter().
    fn filter_quantity(&mut self, item: &DanmakuItem, ctx: &FilterContext) -> bool {
        let Some(max_size) = self.max_quantity else {
            return false;
        };

        if max_size == 0 {
            return false;
        }

        let filter_factor = 1.0 / (max_size as f64 + max_size as f64 / 5.0);

        if let Some(last_time) = self.last_skipped_time {
            let gap = item.get_actual_time(&ctx.global_flags) - last_time;
            let max_duration = ctx.scroll_duration.value;
            if gap >= 0 && (gap as f64) < (max_duration as f64 * filter_factor) {
                return true;
            }
        }

        if ctx.index_in_screen as u32 > max_size + max_size / 5 {
            return true;
        }

        self.last_skipped_time = Some(item.get_actual_time(&ctx.global_flags));
        false
    }

    /// Keyword and regex filter.
    fn filter_keywords(&self, item: &DanmakuItem) -> bool {
        for keyword in &self.blocked_keywords {
            if item.text.contains(keyword.as_str()) {
                return true;
            }
        }
        for re in &self.blocked_regexes {
            if re.is_match(&item.text) {
                return true;
            }
        }
        false
    }

    /// Duplicate merging filter.
    /// Ported from DuplicateMergingFilter.needFilter().
    fn filter_duplicate(&mut self, item: &DanmakuItem, ctx: &FilterContext) -> bool {
        let text = &item.text;

        if self.current_duplicates.len() > 128 {
            self.current_duplicates.retain(|_, &mut time| {
                ctx.timer_ms - time < 10000
            });
        }

        if self.blocked_duplicates.contains(text) {
            return true;
        }

        if self.passed_duplicates.contains(text) {
            return false;
        }

        if self.current_duplicates.contains_key(text) {
            self.blocked_duplicates.insert(text.clone());
            return true;
        }

        self.current_duplicates.insert(text.clone(), item.get_actual_time(&ctx.global_flags));
        self.passed_duplicates.insert(text.clone());
        false
    }

    /// Reset filter state (e.g., on seek).
    pub fn reset(&mut self) {
        self.last_skipped_time = None;
        self.current_duplicates.clear();
        self.blocked_duplicates.clear();
        self.passed_duplicates.clear();
    }

    /// Parse block_words list into keywords and regex patterns.
    /// Format: plain text → keyword, "规则名称/表达式/" → regex
    pub fn set_block_words(&mut self, words: &[String]) {
        self.blocked_keywords.clear();
        self.blocked_regexes.clear();
        for word in words {
            if let Some(regex_str) = parse_regex_rule(word) {
                if let Ok(re) = Regex::new(&regex_str) {
                    self.blocked_regexes.push(re);
                }
            } else {
                self.blocked_keywords.push(word.clone());
            }
        }
    }
}

/// Parse "规则名称/表达式/" format into just the regex pattern string.
/// Returns None if not in this format.
fn parse_regex_rule(word: &str) -> Option<String> {
    if !word.contains('/') {
        return None;
    }
    let first_slash = word.find('/')?;
    let last_slash = word.rfind('/')?;
    if first_slash == last_slash || last_slash != word.len() - 1 {
        return None;
    }
    let pattern = &word[first_slash + 1..last_slash];
    if pattern.is_empty() {
        return None;
    }
    Some(pattern.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dfm_core::model::Duration;

    fn make_ctx(timer_ms: i64) -> FilterContext {
        FilterContext {
            timer_ms,
            index_in_screen: 0,
            screen_size: 10,
            frame_elapsed_ms: 0,
            global_flags: GlobalFlags::default(),
            scroll_duration: Duration::new(5000),
        }
    }

    #[test]
    fn test_type_filter() {
        let mut filters = FilterSystem::default();
        filters.blocked_types.insert(DanmakuType::FixTop);
        let ctx = make_ctx(0);
        let mut item = DanmakuItem::new(0, "test".into(), 0xFFFFFFFF, 25.0, DanmakuType::FixTop, 3800);
        assert!(filters.filter_primary(&mut item, &ctx));
    }

    #[test]
    fn test_keyword_filter() {
        let mut filters = FilterSystem::default();
        filters.blocked_keywords.push("bad".to_string());
        let ctx = make_ctx(0);
        let mut item = DanmakuItem::new(0, "this is bad content".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
        assert!(filters.filter_primary(&mut item, &ctx));
    }

    #[test]
    fn test_elapsed_time_filter() {
        let mut filters = FilterSystem::default();
        filters.elapsed_time_limit_ms = 20;
        let mut ctx = make_ctx(0);
        ctx.frame_elapsed_ms = 25; // exceeded limit
        let mut item = DanmakuItem::new(10000, "future".into(), 0xFFFFFFFF, 25.0, DanmakuType::ScrollRL, 5000);
        // item.is_outside(0) = true (time 10000 > 0, dtime > 0 and dtime < duration → not outside)
        // Actually is_outside checks dtime <= 0 || dtime >= duration
        // dtime = 0 - 10000 = -10000 <= 0 → outside
        assert!(filters.filter_primary(&mut item, &ctx));
    }
}
