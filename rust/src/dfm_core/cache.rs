/// Frame-level danmaku cache with three-tier reuse strategy.
/// Inspired by CacheManagingDrawTask.java's buildCache() approach.
///
/// This cache stores pre-computed layout results (not rendered bitmaps),
/// since the GPU rendering is handled by Next2's pipeline.

use std::collections::HashMap;

/// Cache key for strict reuse: identical text, color, size.
#[derive(Debug, Clone, Hash, PartialEq, Eq)]
struct CacheKey {
    text_hash: u64,
    text_color: u32,
    font_size_bits: u32,
    danmaku_type: u8,
}

impl CacheKey {
    fn from_item(text: &str, text_color: u32, text_size: f32, danmaku_type: u8) -> Self {
        Self {
            text_hash: fnv1a_hash(text),
            text_color,
            font_size_bits: text_size.to_bits(),
            danmaku_type,
        }
    }
}

/// Cached layout data for a danmaku item.
#[derive(Debug, Clone)]
pub struct CachedLayout {
    pub paint_width: f32,
    pub paint_height: f32,
    pub step_x: f32,
}

/// Three-tier danmaku layout cache.
/// Tier 1 (strict): exact match on text+color+size → zero-cost reuse.
/// Tier 2 (fuzzy): dimension-similar entry → reuse buffer.
/// Tier 3 (miss): compute fresh.
#[derive(Debug)]
pub struct DanmakuLayoutCache {
    /// Strict cache: CacheKey → CachedLayout
    strict: HashMap<CacheKey, CachedLayout>,
    /// Fuzzy pool: indexed by approximate dimensions
    fuzzy_pool: Vec<CachedLayout>,
    max_strict_entries: usize,
    _max_fuzzy_entries: usize,
}

impl Default for DanmakuLayoutCache {
    fn default() -> Self {
        Self {
            strict: HashMap::new(),
            fuzzy_pool: Vec::new(),
            max_strict_entries: 2000,
            _max_fuzzy_entries: 500,
        }
    }
}

impl DanmakuLayoutCache {
    /// Try to find a cached layout for the given item.
    /// Returns Some(CachedLayout) on hit, None on miss.
    pub fn lookup(&self, text: &str, text_color: u32, text_size: f32, danmaku_type: u8) -> Option<&CachedLayout> {
        // Tier 1: strict match
        let key = CacheKey::from_item(text, text_color, text_size, danmaku_type);
        if let Some(cached) = self.strict.get(&key) {
            return Some(cached);
        }

        // Tier 2: fuzzy match (dimension within tolerance)
        let target_w = text_size * 0.55 * text.len() as f32; // rough estimate
        let target_h = text_size * 1.2;
        for cached in &self.fuzzy_pool {
            if (cached.paint_width - target_w).abs() < 4.0
                && (cached.paint_height - target_h).abs() < 2.0
            {
                return Some(cached);
            }
        }

        None
    }

    /// Insert a layout result into the cache.
    pub fn insert(&mut self, text: &str, text_color: u32, text_size: f32, danmaku_type: u8, layout: CachedLayout) {
        // Try strict cache first
        let key = CacheKey::from_item(text, text_color, text_size, danmaku_type);
        if self.strict.len() < self.max_strict_entries {
            self.strict.insert(key, layout);
        }
    }

    /// Clear all caches (e.g., on viewport resize).
    pub fn clear(&mut self) {
        self.strict.clear();
        self.fuzzy_pool.clear();
    }

    /// Get cache statistics.
    pub fn stats(&self) -> (usize, usize) {
        (self.strict.len(), self.fuzzy_pool.len())
    }
}

/// FNV-1a hash for text.
fn fnv1a_hash(s: &str) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in s.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cache_hit() {
        let mut cache = DanmakuLayoutCache::default();
        let layout = CachedLayout {
            paint_width: 100.0,
            paint_height: 30.0,
            step_x: 0.4,
        };
        cache.insert("hello", 0xFFFFFFFF, 25.0, 1, layout);

        let hit = cache.lookup("hello", 0xFFFFFFFF, 25.0, 1);
        assert!(hit.is_some());
        assert!((hit.unwrap().paint_width - 100.0).abs() < 0.01);
    }

    #[test]
    fn test_cache_miss() {
        let cache = DanmakuLayoutCache::default();
        let hit = cache.lookup("hello", 0xFFFFFFFF, 25.0, 1);
        assert!(hit.is_none());
    }

    #[test]
    fn test_fnv1a_consistency() {
        assert_eq!(fnv1a_hash("hello"), fnv1a_hash("hello"));
        assert_ne!(fnv1a_hash("hello"), fnv1a_hash("world"));
    }
}
