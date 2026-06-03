/// Adaptive frame rate timer.
/// Ported from DrawHandler.syncTimer() to handle frame drops and maintain smooth animation.
use std::collections::VecDeque;

/// Maximum number of frame times to track for averaging.
const MAX_DRAW_TIMES: usize = 500;

/// Adaptive timer that adjusts time increment based on rendering performance.
/// Ported from DrawHandler.syncTimer().
#[derive(Debug)]
pub struct AdaptiveTimer {
    /// Recent frame render times (ms).
    draw_times: VecDeque<f64>,
    /// Target frame update rate (ms per frame).
    frame_update_rate: f64,
    /// Cordon time: maximum acceptable frame time before jumping ahead.
    cordon_time: f64,
    /// Accumulated time debt from previous frames.
    remaining_time: f64,
    /// Previous time increment (for smoothing).
    prev_increment: f64,
}

impl Default for AdaptiveTimer {
    fn default() -> Self {
        Self {
            draw_times: VecDeque::with_capacity(MAX_DRAW_TIMES),
            frame_update_rate: 16.67, // ~60fps
            cordon_time: 33.33,       // ~30fps
            remaining_time: 0.0,
            prev_increment: 16.67,
        }
    }
}

impl AdaptiveTimer {
    pub fn new(target_fps: f64) -> Self {
        let rate = 1000.0 / target_fps;
        Self {
            frame_update_rate: rate,
            cordon_time: rate * 2.0,
            prev_increment: rate,
            ..Default::default()
        }
    }

    /// Record a frame's render time.
    pub fn record_frame_time(&mut self, render_time_ms: f64) {
        if self.draw_times.len() >= MAX_DRAW_TIMES {
            self.draw_times.pop_front();
        }
        self.draw_times.push_back(render_time_ms);
    }

    /// Compute the average render time.
    fn average_time(&self) -> f64 {
        if self.draw_times.is_empty() {
            return self.frame_update_rate;
        }
        let sum: f64 = self.draw_times.iter().sum();
        sum / self.draw_times.len() as f64
    }

    /// Compute the time increment for the current frame.
    /// Ported from DrawHandler.syncTimer() active rendering mode.
    pub fn compute_increment(&mut self, real_time: f64, timer_time: f64) -> f64 {
        let gap_time = real_time - timer_time;

        // If gap > 2 seconds or rendering is way too slow, jump ahead
        if gap_time > 2000.0 || self.average_time() > self.cordon_time * 2.0 {
            self.remaining_time = 0.0;
            return gap_time;
        }

        let avg_time = self.average_time();
        let frame_rate = if self.frame_update_rate > 0.0 {
            self.frame_update_rate
        } else {
            16.67
        };

        // Base increment: average render time + proportional gap catch-up
        let mut d = avg_time + gap_time / (1000.0 / frame_rate);

        // Clamp to [frame_update_rate, cordon_time]
        d = d.max(frame_rate);
        d = d.min(self.cordon_time);

        // Smoothing: if delta change is small, maintain previous increment
        let delta_change = (d - self.prev_increment).abs();
        if delta_change >= 3.0 && delta_change <= 8.0 {
            d = self.prev_increment;
        }

        self.prev_increment = d;
        self.remaining_time = gap_time - d;
        d
    }

    /// Get the remaining time debt.
    pub fn remaining_time(&self) -> f64 {
        self.remaining_time
    }

    /// Reset the timer (e.g., on seek).
    pub fn reset(&mut self) {
        self.draw_times.clear();
        self.remaining_time = 0.0;
        self.prev_increment = self.frame_update_rate;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_timer() {
        let timer = AdaptiveTimer::default();
        assert!((timer.frame_update_rate - 16.67).abs() < 0.1);
    }

    #[test]
    fn test_record_and_average() {
        let mut timer = AdaptiveTimer::default();
        timer.record_frame_time(16.0);
        timer.record_frame_time(17.0);
        timer.record_frame_time(16.5);
        let avg = timer.average_time();
        assert!((avg - 16.5).abs() < 0.1);
    }

    #[test]
    fn test_gap_jump() {
        let mut timer = AdaptiveTimer::default();
        // Large gap → should jump ahead
        let d = timer.compute_increment(5000.0, 0.0);
        assert!((d - 5000.0).abs() < 1.0);
    }

    #[test]
    fn test_normal_increment() {
        let mut timer = AdaptiveTimer::new(60.0);
        timer.record_frame_time(16.0);
        timer.record_frame_time(16.0);
        // Small gap, normal rendering
        let d = timer.compute_increment(100.0, 90.0);
        // Should be clamped to frame_update_rate
        assert!(d >= timer.frame_update_rate - 1.0);
    }

    #[test]
    fn test_reset() {
        let mut timer = AdaptiveTimer::default();
        timer.record_frame_time(50.0);
        timer.remaining_time = 100.0;
        timer.reset();
        assert!(timer.draw_times.is_empty());
        assert!((timer.remaining_time).abs() < 0.01);
    }
}
