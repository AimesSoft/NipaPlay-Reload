//! Continuous media clock. Scene delivery and animation sampling are independent.
use std::time::{Duration, Instant};

pub(super) struct MotionClock {
    origin: Instant,
    media: f64,
    rate: f64,
    correction_rate: f64,
    correction_duration: f64,
    epoch: Option<u64>,
    pub playing: bool,
    pub snapshot_media: f64,
    pub valid_until: f64,
    pub period: Duration,
    pub revision: u64,
}

impl MotionClock {
    pub fn new(now: Instant) -> Self {
        Self {
            origin: now,
            media: 0.0,
            rate: 1.0,
            correction_rate: 0.0,
            correction_duration: 0.0,
            epoch: None,
            playing: false,
            snapshot_media: 0.0,
            valid_until: 0.0,
            period: Duration::from_secs_f64(1.0 / 60.0),
            revision: 0,
        }
    }

    pub fn media_at(&self, now: Instant) -> f64 {
        let dt = now.saturating_duration_since(self.origin).as_secs_f64();
        self.media
            + if self.playing {
                self.rate * dt + self.correction_rate * dt.min(self.correction_duration)
            } else {
                0.0
            }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn anchor(
        &mut self,
        now: Instant,
        epoch: u64,
        media: f64,
        age: f64,
        rate: f64,
        playing: bool,
        refresh: f64,
        valid_until: f64,
    ) {
        let rate = if rate.is_finite() {
            rate.clamp(0.01, 16.0)
        } else {
            1.0
        };
        let age = if age.is_finite() {
            age.clamp(0.0, 1.0)
        } else {
            0.0
        };
        let target = media + if playing { age * rate } else { 0.0 };
        let current = self.media_at(now);
        let reset = self.epoch != Some(epoch);
        if reset || self.playing != playing || self.rate != rate {
            self.revision = self.revision.wrapping_add(1);
        }
        self.media = if reset { target } else { current };
        self.origin = now;
        self.epoch = Some(epoch);
        self.playing = playing;
        self.rate = rate;
        // Never step position for ordinary anchors. Correct phase at <=1% speed
        // for at most 0.5s; seek/resume is an explicit epoch change instead.
        let error = target - self.media;
        self.correction_rate = if playing && !reset {
            (error / 0.5).clamp(-rate * 0.01, rate * 0.01)
        } else {
            0.0
        };
        self.correction_duration = 0.5;
        self.snapshot_media = media;
        self.valid_until = valid_until;
        let hz = if refresh.is_finite() && refresh >= 30.0 {
            refresh.clamp(30.0, 1000.0)
        } else {
            60.0
        };
        self.period = Duration::from_secs_f64(1.0 / hz);
    }

    pub fn active(&self, now: Instant) -> bool {
        self.playing && self.media_at(now) < self.valid_until
    }
}

/// Advance the absolute deadline, dropping missed slots rather than producing
/// a burst or accumulating draw/submit overhead into every frame period.
pub(super) fn next_deadline(deadline: Instant, period: Duration, now: Instant) -> Instant {
    if deadline > now {
        return deadline;
    }
    let slots = now.duration_since(deadline).as_nanos() / period.as_nanos() + 1;
    deadline + period.mul_f64(slots as f64)
}

pub(super) fn sample_x(
    x: f64,
    speed: f64,
    snapshot_media: f64,
    media: f64,
    start: Option<f64>,
    end: Option<f64>,
) -> Option<f64> {
    if start.is_some_and(|t| media < t) || end.is_some_and(|t| media >= t) {
        return None;
    }
    Some(x + speed * (media - snapshot_media))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dart_gap_does_not_freeze_or_reset_motion() {
        let start = Instant::now();
        let mut clock = MotionClock::new(start);
        clock.anchor(start, 1, 10.0, 0.0, 1.0, true, 180.0, 10.25);
        let mut previous = 10.0;
        for tick in 1..=4 {
            let now = start + Duration::from_secs_f64(tick as f64 / 180.0);
            let media = clock.media_at(now);
            assert!((media - previous - 1.0 / 180.0).abs() < 1e-8);
            previous = media;
        }
        let now = start + Duration::from_millis(23);
        let before = clock.media_at(now);
        clock.anchor(now, 1, 10.020, 0.0, 1.0, true, 180.0, 10.27);
        assert_eq!(before, clock.media_at(now));
        assert!(clock.active(now));
    }
    #[test]
    fn pause_rate_seek_and_expiration_are_explicit() {
        let start = Instant::now();
        let mut clock = MotionClock::new(start);
        clock.anchor(start, 1, 10.0, 0.0, 2.0, true, 240.0, 10.5);
        let now = start + Duration::from_millis(100);
        assert!((clock.media_at(now) - 10.2).abs() < 1e-8);
        clock.anchor(now, 1, 10.2, 0.0, 2.0, false, 240.0, 10.5);
        assert!((clock.media_at(now + Duration::from_secs(1)) - 10.2).abs() < 1e-8);
        clock.anchor(now, 2, 40.0, 0.0, 1.0, true, 240.0, 40.25);
        assert_eq!(clock.media_at(now), 40.0);
        assert!(!clock.active(now + Duration::from_millis(300)));
    }
    #[test]
    fn late_wakeup_skips_deadlines_without_phase_drift() {
        let start = Instant::now();
        let period = Duration::from_millis(5);
        assert_eq!(
            next_deadline(start, period, start + Duration::from_millis(18)),
            start + Duration::from_millis(20)
        );
    }
    #[test]
    fn replacing_a_delayed_snapshot_does_not_change_position() {
        // Both packets describe the same trajectory at different media times.
        // A 17ms Dart pause must not re-baseline motion at packet arrival.
        let old = sample_x(500.0, -200.0, 10.0, 10.067, None, None).unwrap();
        let new = sample_x(490.0, -200.0, 10.050, 10.067, None, None).unwrap();
        assert!((old - new).abs() < 1e-9);
    }
    #[test]
    fn future_items_activate_and_expire_without_dart_submissions() {
        assert_eq!(
            sample_x(-110.0, 100.0, 10.0, 10.05, Some(10.1), Some(11.0)),
            None
        );
        assert!(
            (sample_x(-110.0, 100.0, 10.0, 10.1, Some(10.1), Some(11.0)).unwrap() + 100.0).abs()
                < 1e-9
        );
        assert_eq!(
            sample_x(300.0, 0.0, 10.0, 10.2, Some(10.1), Some(11.0)),
            Some(300.0)
        );
        assert_eq!(
            sample_x(300.0, 0.0, 10.0, 11.0, Some(10.1), Some(11.0)),
            None
        );
    }
    #[test]
    fn ordinary_clock_correction_is_bounded_and_rate_is_applied_once() {
        let start = Instant::now();
        let mut clock = MotionClock::new(start);
        clock.anchor(start, 1, 10.0, 0.0, 2.0, true, 180.0, 11.0);
        let now = start + Duration::from_millis(50);
        let before = clock.media_at(now);
        clock.anchor(now, 1, 10.11, 0.0, 2.0, true, 180.0, 11.0);
        assert_eq!(before, clock.media_at(now));
        let later = clock.media_at(now + Duration::from_millis(100));
        assert!((later - before - 0.202).abs() < 1e-9);
        let x = sample_x(500.0, -200.0, before, later, None, None).unwrap();
        assert!((x - 459.6).abs() < 1e-8);
    }
}
