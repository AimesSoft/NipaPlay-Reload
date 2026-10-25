/// Positive offsets advance a track, matching the global danmaku offset.
class DanmakuTrackTiming {
  static double offsetOf(Map<String, dynamic> track) {
    final value = track['timeOffset'];
    return value is num && value.isFinite ? value.toDouble() : 0;
  }

  static Map<String, dynamic> shift(
    Map<String, dynamic> comment,
    double offset,
  ) {
    if (offset == 0 || !offset.isFinite) return comment;
    final rawTime = comment['time'] ?? comment['t'];
    final time = rawTime is num
        ? rawTime.toDouble()
        : double.tryParse(rawTime?.toString() ?? '') ?? 0;
    return {
      ...comment,
      'time': time - offset,
      if (comment.containsKey('t')) 't': time - offset,
    };
  }
}
