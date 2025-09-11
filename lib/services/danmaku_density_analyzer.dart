import 'dart:math' as math;
import '../widgets/danmaku_density_chart.dart';

/// 弹幕密度统计服务
/// 负责分析弹幕数据并生成密度图表数据
class DanmakuDensityAnalyzer {
  /// 分析弹幕列表，生成密度数据
  /// 
  /// [danmakuList] 弹幕数据列表，每个元素应包含time字段
  /// [videoDurationSeconds] 视频总时长（秒）
  /// [segmentCount] 分段数量，默认100段
  /// [minSegmentDuration] 最小段时长（秒），默认1秒
  static List<DanmakuDensityPoint> analyzeDensity({
    required List<Map<String, dynamic>> danmakuList,
    required int videoDurationSeconds,
    int segmentCount = 100,
    double minSegmentDuration = 1.0,
  }) {
    if (danmakuList.isEmpty || videoDurationSeconds <= 0) {
      return [];
    }

    // 确保分段数量合理
    final actualSegmentCount = math.min(
      segmentCount,
      (videoDurationSeconds / minSegmentDuration).ceil(),
    );

    if (actualSegmentCount <= 0) return [];

    // 计算每段的时长
    final segmentDuration = videoDurationSeconds / actualSegmentCount;
    
    // 初始化每段的弹幕计数
    final segmentCounts = List<int>.filled(actualSegmentCount, 0);

    // 统计每段的弹幕数量
    for (final danmaku in danmakuList) {
      final time = _extractTime(danmaku);
      if (time == null || time < 0 || time > videoDurationSeconds) continue;

      // 计算该弹幕属于哪一段
      final segmentIndex = math.min(
        (time / segmentDuration).floor(),
        actualSegmentCount - 1,
      );

      segmentCounts[segmentIndex]++;
    }

    // 生成密度数据点
    final densityPoints = <DanmakuDensityPoint>[];
    for (int i = 0; i < actualSegmentCount; i++) {
      final timePosition = (i + 0.5) / actualSegmentCount; // 使用段的中点时间
      densityPoints.add(DanmakuDensityPoint(
        timePosition: timePosition,
        count: segmentCounts[i],
      ));
    }

    return densityPoints;
  }

  /// 分析弹幕高峰时段
  /// 
  /// [densityPoints] 密度数据点
  /// [peakThreshold] 高峰阈值（相对于最大值的比例，0.0-1.0）
  static List<DanmakuPeakSegment> findPeakSegments({
    required List<DanmakuDensityPoint> densityPoints,
    double peakThreshold = 0.6,
  }) {
    if (densityPoints.isEmpty) return [];

    final maxCount = densityPoints.map((p) => p.count).reduce(math.max);
    if (maxCount == 0) return [];

    final threshold = maxCount * peakThreshold;
    final peaks = <DanmakuPeakSegment>[];
    
    DanmakuPeakSegment? currentPeak;

    for (int i = 0; i < densityPoints.length; i++) {
      final point = densityPoints[i];
      
      if (point.count >= threshold) {
        if (currentPeak == null) {
          // 开始新的高峰段
          currentPeak = DanmakuPeakSegment(
            startPosition: point.timePosition,
            endPosition: point.timePosition,
            maxCount: point.count,
            totalCount: point.count,
          );
        } else {
          // 扩展当前高峰段
          currentPeak = DanmakuPeakSegment(
            startPosition: currentPeak.startPosition,
            endPosition: point.timePosition,
            maxCount: math.max(currentPeak.maxCount, point.count),
            totalCount: currentPeak.totalCount + point.count,
          );
        }
      } else {
        if (currentPeak != null) {
          // 结束当前高峰段
          peaks.add(currentPeak);
          currentPeak = null;
        }
      }
    }

    // 添加最后一个高峰段（如果存在）
    if (currentPeak != null) {
      peaks.add(currentPeak);
    }

    return peaks;
  }

  /// 获取弹幕密度统计信息
  static DanmakuDensityStats getDensityStats(List<DanmakuDensityPoint> densityPoints) {
    if (densityPoints.isEmpty) {
      return const DanmakuDensityStats(
        totalCount: 0,
        averageCount: 0.0,
        maxCount: 0,
        minCount: 0,
        peakPositions: [],
      );
    }

    final counts = densityPoints.map((p) => p.count).toList();
    final totalCount = counts.reduce((a, b) => a + b);
    final maxCount = counts.reduce(math.max);
    final minCount = counts.reduce(math.min);
    final averageCount = totalCount / counts.length;

    // 找到峰值位置（局部最大值）
    final peakPositions = <double>[];
    for (int i = 1; i < densityPoints.length - 1; i++) {
      final current = densityPoints[i];
      final prev = densityPoints[i - 1];
      final next = densityPoints[i + 1];
      
      if (current.count > prev.count && current.count > next.count) {
        peakPositions.add(current.timePosition);
      }
    }

    return DanmakuDensityStats(
      totalCount: totalCount,
      averageCount: averageCount,
      maxCount: maxCount,
      minCount: minCount,
      peakPositions: peakPositions,
    );
  }

  /// 平滑密度数据（移动平均）
  static List<DanmakuDensityPoint> smoothDensityData({
    required List<DanmakuDensityPoint> densityPoints,
    int windowSize = 3,
  }) {
    if (densityPoints.length <= windowSize || windowSize <= 1) {
      return List.from(densityPoints);
    }

    final smoothedPoints = <DanmakuDensityPoint>[];
    final halfWindow = windowSize ~/ 2;

    for (int i = 0; i < densityPoints.length; i++) {
      final start = math.max(0, i - halfWindow);
      final end = math.min(densityPoints.length - 1, i + halfWindow);
      
      int sum = 0;
      int count = 0;
      
      for (int j = start; j <= end; j++) {
        sum += densityPoints[j].count;
        count++;
      }
      
      final smoothedCount = (sum / count).round();
      smoothedPoints.add(DanmakuDensityPoint(
        timePosition: densityPoints[i].timePosition,
        count: smoothedCount,
      ));
    }

    return smoothedPoints;
  }

  /// 从弹幕数据中提取时间信息
  static double? _extractTime(Map<String, dynamic> danmaku) {
    // 尝试多种可能的时间字段名
    final timeFields = ['time', 't', 'timestamp', 'stime'];
    
    for (final field in timeFields) {
      final value = danmaku[field];
      if (value != null) {
        if (value is num) {
          return value.toDouble();
        } else if (value is String) {
          final parsed = double.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
    }
    
    return null;
  }
}

/// 弹幕高峰时段数据
class DanmakuPeakSegment {
  final double startPosition; // 开始位置 (0.0-1.0)
  final double endPosition;   // 结束位置 (0.0-1.0)
  final int maxCount;         // 该段最大弹幕数
  final int totalCount;       // 该段总弹幕数

  const DanmakuPeakSegment({
    required this.startPosition,
    required this.endPosition,
    required this.maxCount,
    required this.totalCount,
  });

  /// 获取持续时长（相对于总时长的比例）
  double get duration => endPosition - startPosition;

  /// 获取中心位置
  double get centerPosition => (startPosition + endPosition) / 2;

  @override
  String toString() {
    return 'DanmakuPeakSegment('
        'start: ${(startPosition * 100).toStringAsFixed(1)}%, '
        'end: ${(endPosition * 100).toStringAsFixed(1)}%, '
        'maxCount: $maxCount, '
        'totalCount: $totalCount)';
  }
}

/// 弹幕密度统计信息
class DanmakuDensityStats {
  final int totalCount;           // 总弹幕数
  final double averageCount;      // 平均每段弹幕数
  final int maxCount;             // 单段最大弹幕数
  final int minCount;             // 单段最小弹幕数
  final List<double> peakPositions; // 峰值位置列表

  const DanmakuDensityStats({
    required this.totalCount,
    required this.averageCount,
    required this.maxCount,
    required this.minCount,
    required this.peakPositions,
  });

  @override
  String toString() {
    return 'DanmakuDensityStats('
        'total: $totalCount, '
        'avg: ${averageCount.toStringAsFixed(1)}, '
        'max: $maxCount, '
        'min: $minCount, '
        'peaks: ${peakPositions.length})';
  }
}