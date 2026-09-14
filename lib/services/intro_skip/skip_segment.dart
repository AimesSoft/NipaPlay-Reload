/// 可跳过区间的类型。当前只有片头，片尾留出扩展位。
enum SkipSegmentKind {
  /// 片头（OP / 开场）。
  opening,

  /// 片尾（ED / 结尾）。暂未接入，保留语义避免将来改动模型。
  ending,
}

/// 区间来源。合并多路信号时按 [SkipSegmentSourceRank.rank] 取舍，
/// 数字越大越可信：服务端/社区标注的精确区间 > 本地推导 > 启发式猜测。
enum SkipSegmentSource {
  /// 媒体服务器（Jellyfin / Emby）服务端智能识别的 MediaSegments。
  mediaServer,

  /// AniSkip 社区标注库。
  aniskip,

  /// 弹幕报点推导（DanmakuIntroDetector）。
  danmaku,

  /// 章节名 / 时间位置启发式。
  chapterHeuristic,

  /// 用户手动标记。
  manual,
}

/// 来源可信度排序。用于多路信号合并时决定谁覆盖谁。
extension SkipSegmentSourceRank on SkipSegmentSource {
  /// 数字越大越可信。
  int get rank {
    switch (this) {
      case SkipSegmentSource.manual:
        return 100;
      case SkipSegmentSource.mediaServer:
        return 40;
      case SkipSegmentSource.aniskip:
        return 30;
      case SkipSegmentSource.danmaku:
        return 20;
      case SkipSegmentSource.chapterHeuristic:
        return 10;
    }
  }
}

/// 一段可跳过的片头 / 片尾区间（秒）。
///
/// 同一时刻播放器只保留每种 [SkipSegmentKind] 一个区间，多路信号按
/// [SkipSegmentSource] 的可信度合并（见 `VideoPlayerStateSkipSegments.applySkipSegment`）。
class SkipSegment {
  final SkipSegmentKind kind;
  final SkipSegmentSource source;

  /// 区间起点（秒）。无把握时为 0（不猜冷开场）。
  final double startSeconds;

  /// 区间终点（秒），即「跳过」按钮要跳转到的位置。
  final double endSeconds;

  /// 支撑证据条数（报点数 + 着陆确认数），用于日志与置信展示。
  final int evidenceCount;

  const SkipSegment({
    required this.kind,
    required this.source,
    required this.startSeconds,
    required this.endSeconds,
    this.evidenceCount = 0,
  });

  /// 给定播放位置是否落在该区间内。
  bool containsSeconds(double seconds) =>
      seconds >= startSeconds && seconds < endSeconds;

  /// 区间起点（Duration 形式，供 seek 使用）。
  Duration get start => Duration(milliseconds: (startSeconds * 1000).round());

  /// 区间终点（Duration 形式，供 seek 使用）。
  Duration get end => Duration(milliseconds: (endSeconds * 1000).round());

  @override
  String toString() => 'SkipSegment(${kind.name} src=${source.name} '
      '${startSeconds.toStringAsFixed(1)}-${endSeconds.toStringAsFixed(1)}s '
      'evidence=$evidenceCount)';
}

/// 槽位合并结果：[segment] 是合并后槽位应有的值（候选被拒时仍是原值），
/// [accepted] 标记候选是否生效。
typedef SkipSlotMerge = ({SkipSegment segment, bool accepted});

/// 槽位合并规则——rank 取舍的**唯一实现**，生产代码与测试共用。
///
/// 候选当且仅当可信度**不低于**现有值时生效：同级覆盖是合法的（同源结果的
/// 刷新），仅严格更低才被拒。
SkipSlotMerge mergeSkipSegmentSlot(
    SkipSegment? existing, SkipSegment candidate) {
  if (existing != null && existing.source.rank > candidate.source.rank) {
    return (segment: existing, accepted: false);
  }
  return (segment: candidate, accepted: true);
}
