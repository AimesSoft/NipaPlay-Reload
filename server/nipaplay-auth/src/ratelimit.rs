use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

/// Fixed-window rate limiter keyed by arbitrary strings.
///
/// A single `check` call evaluates every `(key, limit)` pair atomically: the
/// request is rejected if any bucket is exhausted, and counters only advance
/// when the whole check succeeds. A limit of `0` disables that key.
#[derive(Clone)]
pub struct RateLimiter {
    buckets: Arc<Mutex<HashMap<String, WindowBucket>>>,
}

struct WindowBucket {
    started_at: Instant,
    last_seen: Instant,
    window: Duration,
    count: u32,
}

impl Default for RateLimiter {
    fn default() -> Self {
        Self::new()
    }
}

impl RateLimiter {
    pub fn new() -> Self {
        Self {
            buckets: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Fixed-window check with an explicit window length.
    pub fn check_window(&self, window: Duration, keys: &[(&str, u32)]) -> bool {
        let now = Instant::now();
        let mut buckets = self
            .buckets
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());

        if buckets.len() > 50_000 {
            buckets.retain(|_, bucket| {
                now.duration_since(bucket.last_seen) < Duration::from_secs(600)
            });
        }

        for (key, limit) in keys {
            if *limit == 0 {
                continue;
            }
            let bucket = buckets.entry((*key).to_owned()).or_insert(WindowBucket {
                started_at: now,
                last_seen: now,
                window,
                count: 0,
            });
            if bucket.window != window {
                bucket.window = window;
                bucket.started_at = now;
                bucket.count = 0;
            } else if now.duration_since(bucket.started_at) >= window {
                bucket.started_at = now;
                bucket.count = 0;
            }
            bucket.last_seen = now;
            if bucket.count >= *limit {
                return false;
            }
        }

        for (key, limit) in keys {
            if *limit == 0 {
                continue;
            }
            if let Some(bucket) = buckets.get_mut(*key) {
                bucket.count += 1;
            }
        }
        true
    }

    /// Fixed one-minute window check.
    pub fn check(&self, keys: &[(&str, u32)]) -> bool {
        self.check_window(Duration::from_secs(60), keys)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_once_the_window_is_exhausted() {
        let limiter = RateLimiter::new();
        assert!(limiter.check(&[("ip:1", 2)]));
        assert!(limiter.check(&[("ip:1", 2)]));
        assert!(!limiter.check(&[("ip:1", 2)]));
    }

    #[test]
    fn zero_limit_disables_the_key() {
        let limiter = RateLimiter::new();
        for _ in 0..100 {
            assert!(limiter.check(&[("account:none", 0)]));
        }
    }

    #[test]
    fn exhausted_key_blocks_even_when_others_have_room() {
        let limiter = RateLimiter::new();
        assert!(limiter.check(&[("global", 10), ("ip:1", 1)]));
        assert!(!limiter.check(&[("global", 10), ("ip:1", 1)]));
    }
}
