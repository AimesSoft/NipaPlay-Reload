class CanvasDanmakuTimeline {
  static const double fallbackSeekThresholdSeconds = 2.0;

  static bool didSeek({
    required int previousRevision,
    required int currentRevision,
    required double previousTime,
    required double currentTime,
  }) {
    if (previousRevision >= 0 && currentRevision >= 0) {
      return previousRevision != currentRevision;
    }
    return (currentTime - previousTime).abs() >
        fallbackSeekThresholdSeconds;
  }

  /// 返回 entries 中第一个 timeOf(entry) >= target 的下标。
  /// 要求 entries 已按 timeOf 升序排列（上游弹幕列表按 time 排序）。
  static int lowerBound<T>(
    List<T> entries,
    double target, {
    required double Function(T entry) timeOf,
  }) {
    var low = 0;
    var high = entries.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (timeOf(entries[mid]) < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// 收集 [currentTime - lookBackSeconds, currentTime] 窗口内的条目，
  /// 按 timeOf 升序返回。输入不要求有序（恢复调用低频，全量过滤可接受）。
  static List<T> activeEntries<T>(
    Iterable<T> entries, {
    required double Function(T entry) timeOf,
    required double currentTime,
    required double lookBackSeconds,
  }) {
    final windowStart = currentTime - lookBackSeconds;
    final active = entries.where((entry) {
      final time = timeOf(entry);
      return time >= windowStart && time <= currentTime;
    }).toList();
    active.sort((a, b) => timeOf(a).compareTo(timeOf(b)));
    return active;
  }

  static double scrollProgress({
    required double scheduledTime,
    required double currentTime,
    required double durationSeconds,
  }) {
    if (durationSeconds <= 0 || !durationSeconds.isFinite) {
      return 1;
    }
    return ((currentTime - scheduledTime) / durationSeconds)
        .clamp(0.0, 1.0);
  }

  static double remainingLifetime({
    required double scheduledTime,
    required double currentTime,
    required double durationSeconds,
  }) {
    return (durationSeconds - (currentTime - scheduledTime))
        .clamp(0.0, durationSeconds);
  }

  static double advanceScrollX({
    required double currentX,
    required int previousTick,
    required int currentTick,
    required double viewWidth,
    required double danmakuWidth,
    required double durationSeconds,
    required double playbackRate,
  }) {
    if (currentTick <= previousTick ||
        durationSeconds <= 0 ||
        playbackRate <= 0) {
      return currentX;
    }
    final wallSeconds = (currentTick - previousTick) / 1000.0;
    final distance = viewWidth + danmakuWidth;
    return currentX -
        wallSeconds * playbackRate * distance / durationSeconds;
  }

  static double consumeLifetime({
    required double remainingSeconds,
    required double wallSeconds,
    required double playbackRate,
  }) {
    if (wallSeconds <= 0 || playbackRate <= 0) {
      return remainingSeconds;
    }
    return remainingSeconds - wallSeconds * playbackRate;
  }
}

class ScrollDanmakuCollision {
  static bool canPlace({
    required Iterable<({double x, double width})> existing,
    required double candidateX,
    required double candidateWidth,
    required double viewWidth,
    required double durationSeconds,
    double gap = 0,
  }) {
    if (durationSeconds <= 0 || viewWidth <= 0) {
      return false;
    }

    final candidateSpeed =
        (viewWidth + candidateWidth) / durationSeconds;
    for (final item in existing) {
      final existingRight = item.x + item.width;
      if (candidateX < existingRight + gap) {
        return false;
      }

      final existingSpeed = (viewWidth + item.width) / durationSeconds;
      if (candidateSpeed <= existingSpeed) {
        continue;
      }

      final separation = candidateX - existingRight - gap;
      final catchUpSeconds = separation / (candidateSpeed - existingSpeed);
      final existingExitSeconds = existingRight / existingSpeed;
      if (catchUpSeconds < existingExitSeconds) {
        return false;
      }
    }
    return true;
  }
}
