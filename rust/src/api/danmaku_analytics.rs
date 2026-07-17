#[derive(Clone, Debug)]
pub struct RustDensityPoint {
    pub time_position: f64,
    pub count: i32,
}

#[derive(Clone, Debug)]
pub struct RustPeakSegment {
    pub start_position: f64,
    pub end_position: f64,
    pub max_count: i32,
    pub total_count: i32,
}

#[derive(Clone, Debug)]
pub struct RustDensityStats {
    pub total_count: i32,
    pub average_count: f64,
    pub max_count: i32,
    pub min_count: i32,
    pub peak_positions: Vec<f64>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn analyze_density(
    times: Vec<f64>,
    video_duration_seconds: i32,
    segment_count: i32,
    min_segment_duration: f64,
) -> Vec<RustDensityPoint> {
    if times.is_empty() || video_duration_seconds <= 0 || segment_count <= 0 {
        return Vec::new();
    }
    let duration = video_duration_seconds as f64;
    let duration_limited_count = (duration / min_segment_duration).ceil() as i32;
    let actual_segment_count = segment_count.min(duration_limited_count);
    if actual_segment_count <= 0 {
        return Vec::new();
    }

    let segment_duration = duration / actual_segment_count as f64;
    let mut counts = vec![0i32; actual_segment_count as usize];
    for time in times {
        if !time.is_finite() || time < 0.0 || time > duration {
            continue;
        }
        let index = ((time / segment_duration).floor() as usize).min(counts.len() - 1);
        counts[index] += 1;
    }

    counts
        .into_iter()
        .enumerate()
        .map(|(index, count)| RustDensityPoint {
            time_position: (index as f64 + 0.5) / actual_segment_count as f64,
            count,
        })
        .collect()
}

#[flutter_rust_bridge::frb(sync)]
pub fn find_peak_segments(
    points: Vec<RustDensityPoint>,
    peak_threshold: f64,
) -> Vec<RustPeakSegment> {
    let Some(max_count) = points.iter().map(|point| point.count).max() else {
        return Vec::new();
    };
    if max_count == 0 {
        return Vec::new();
    }
    let threshold = max_count as f64 * peak_threshold;
    let mut peaks = Vec::new();
    let mut current: Option<RustPeakSegment> = None;
    for point in points {
        if point.count as f64 >= threshold {
            current = Some(match current {
                None => RustPeakSegment {
                    start_position: point.time_position,
                    end_position: point.time_position,
                    max_count: point.count,
                    total_count: point.count,
                },
                Some(existing) => RustPeakSegment {
                    start_position: existing.start_position,
                    end_position: point.time_position,
                    max_count: existing.max_count.max(point.count),
                    total_count: existing.total_count + point.count,
                },
            });
        } else if let Some(peak) = current.take() {
            peaks.push(peak);
        }
    }
    if let Some(peak) = current {
        peaks.push(peak);
    }
    peaks
}

#[flutter_rust_bridge::frb(sync)]
pub fn density_stats(points: Vec<RustDensityPoint>) -> RustDensityStats {
    if points.is_empty() {
        return RustDensityStats {
            total_count: 0,
            average_count: 0.0,
            max_count: 0,
            min_count: 0,
            peak_positions: Vec::new(),
        };
    }
    let total_count = points.iter().map(|point| point.count).sum();
    let max_count = points.iter().map(|point| point.count).max().unwrap_or(0);
    let min_count = points.iter().map(|point| point.count).min().unwrap_or(0);
    let peak_positions = points
        .windows(3)
        .filter_map(|window| {
            let current = &window[1];
            (current.count > window[0].count && current.count > window[2].count)
                .then_some(current.time_position)
        })
        .collect();
    RustDensityStats {
        total_count,
        average_count: total_count as f64 / points.len() as f64,
        max_count,
        min_count,
        peak_positions,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn smooth_density(points: Vec<RustDensityPoint>, window_size: i32) -> Vec<RustDensityPoint> {
    if points.len() <= window_size.max(0) as usize || window_size <= 1 {
        return points;
    }
    let half_window = window_size as usize / 2;
    (0..points.len())
        .map(|index| {
            let start = index.saturating_sub(half_window);
            let end = (index + half_window).min(points.len() - 1);
            let slice = &points[start..=end];
            let sum: i32 = slice.iter().map(|point| point.count).sum();
            RustDensityPoint {
                time_position: points[index].time_position,
                count: (sum as f64 / slice.len() as f64).round() as i32,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn analyzes_and_smooths_density() {
        let points = analyze_density(vec![0.0, 1.0, 1.2, 9.9], 10, 5, 1.0);
        assert_eq!(points.iter().map(|point| point.count).sum::<i32>(), 4);
        assert_eq!(smooth_density(points, 3).len(), 5);
    }
}
