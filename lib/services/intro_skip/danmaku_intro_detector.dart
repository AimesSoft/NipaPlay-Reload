import 'skip_segment.dart';

/// 弹幕推导片头所需的极简弹幕条目。
///
/// 只取检测需要的两个字段，避免检测器依赖播放器的具体数据结构
/// （弹弹play 原始 JSON、缓存条目、第三方弹幕轨都能适配进来）。
class DanmakuTextEntry {
  /// 弹幕在视频内的出现时间（秒）。报点类弹幕的出现时刻 ≈ 观众当时的播放位置。
  final double timeSeconds;

  /// 弹幕正文。
  final String text;

  const DanmakuTextEntry({required this.timeSeconds, required this.text});

  /// 从播放器内部的弹幕 Map 构造。
  ///
  /// 字段兼容 `time`/`t` 与 `content`/`c`（与 `dfm_plus_layout_bridge._resolveTime`
  /// 同一套口径）。时间解析失败时返回 null，由调用方丢弃该条。
  factory DanmakuTextEntry.fromMap(Map<dynamic, dynamic> raw) {
    final timeValue = raw['time'] ?? raw['t'];
    final double time;
    if (timeValue is num) {
      time = timeValue.toDouble();
    } else {
      time = double.tryParse(timeValue?.toString() ?? '') ?? double.nan;
    }
    if (time.isNaN || !time.isFinite || time < 0) {
      return const DanmakuTextEntry(timeSeconds: double.nan, text: '');
    }
    final text = (raw['content'] ?? raw['c'])?.toString() ?? '';
    return DanmakuTextEntry(timeSeconds: time, text: text);
  }

  /// 该条目是否可用（时间有效且正文非空）。
  bool get isValid =>
      text.isNotEmpty && timeSeconds.isFinite && !timeSeconds.isNaN;
}

/// 从弹幕正文推导片头结束点。
///
/// 信号源是弹幕文化里的「跳过报点」：观众跳过 OP 时发「跳伞/空降 02:12」报出落点，
/// 落地后再发「空降成功」确认。两批独立行为在真实数据上会收敛到同一秒，因此取
/// 报点目标的主簇中位数作为片头结束点，用着陆/正片标记做交叉确认。
///
/// 判定全部基于文本 + 弹幕出现时间，无网络、无文件 IO；证据不足时返回 null，
/// 消费侧静默降级（不给跳过按钮），不做位置启发式兜底。
///
/// 算法与阈值来自 OcPlayer 的 DanmakuIntroDetector（54 集真实缓存弹幕标定），
/// 详见 https://github.com/1824239290/OcPlayer 。
class DanmakuIntroDetector {
  DanmakuIntroDetector._();

  // MARK: 阈值（沿用 OcPlayer 2026-09-13 的标定值）

  /// 报点目标的合理区间（秒）：片头不会在 30s 内结束，也不该超过 5 分钟
  /// （超过的「空降」多半是跳前情回顾/中段剧情，不是跳片头）。
  static const double targetMin = 30;
  static const double targetMax = 300;

  /// 主簇聚合间距：目标值相差 ≤25s 视为同一落点。
  static const double clusterGap = 25;

  /// 着陆确认与主簇中位数的最大偏差。
  static const double confirmationTolerance = 15;

  /// 主簇需要的最少报点条数。
  ///
  /// **按条数而非「不同目标值数」统计**（2026-09-14 修正）：现实中观众几乎总是
  /// 报同一个落点，实测恶女不才 S1E6 的 5 条报点目标值全是 170，
  /// distinctCount 恒为 1。用「不同值 ≥2」当门槛会把绝大多数真实数据挡在门外，
  /// 逼着流程回落到不估起点的仅着陆路径，起点因此塌成 0。
  static const int minJumpTargets = 2;

  /// 有交叉确认时主簇所需的最少报点条数。
  static const int minJumpTargetsWithConfirmation = 2;

  /// 无交叉确认时主簇所需的最少报点条数（纯报点自证需要更多样本）。
  static const int minJumpTargetsWithoutConfirmation = 3;

  /// 起点无从估计时的兜底 OP 长度（秒）。日本 TV 动画 OP 多为 1 分半。
  ///
  /// 仅着陆确认路径（无报点）拿不到起点信息，硬回落 0 会让按钮从第一帧就弹出；
  /// 按典型 OP 长度反推虽然粗糙，但比 0 靠谱得多。
  static const double typicalIntroLength = 90;

  /// 判定「报点是预告型」的阈值（秒）。
  ///
  /// 有些观众会在视频刚开始就刷「跳伞 01:35」，把落点**预告**给后面的人——
  /// 这类弹幕的 postTime 接近 0，并不代表片头从 0 开始。拿它当中位数会把起点
  /// 整个拽到 0，按钮又变成从第一帧弹出。
  ///
  /// 实测四集：正常情况（观众确实在片头里发）报点中位数在 46~81s，
  /// 预告型低到 1.9s，两者分隔很开，取 30 有充足余量。
  static const double previewReportThreshold = 30;

  /// 片头起点估计允许的最大片头长度。
  static const double maxIntroLength = 240;

  /// 起点估计有意义的最小片头长度：更短的窗口说明观众看完了大半片头才报点，
  /// 起点没有信息量，回 null（消费侧回落到 0，按钮窗口反而更完整）。
  static const double minIntroLengthForStartEstimate = 20;

  /// 仅靠着陆确认判定时需要的最少确认条数（须聚在同一落点附近）。
  static const int minLandingOnlyConfirmations = 3;

  /// 报点关键词后扫描时间戳的窗口长度（「跳伞至3:17」「空降：02：12」都能覆盖）。
  static const int targetScanWindow = 12;

  /// 跳过报点关键词（后跟落点时间戳）。
  static const List<String> jumpKeywords = <String>[
    '跳伞',
    '空降',
    '跳至',
    '跳到',
    '空投',
    '跳過',
  ];

  /// 着陆确认关键词（出现时刻 ≈ 落地时刻，即片头结束点）。
  static const List<String> landingKeywords = <String>[
    '空降成功',
    '空降完成',
    '已空降',
    '着陆成功',
    '降落成功',
    '感谢指挥',
    '感谢塔台',
    '感谢空降',
    '空降部隊',
    '空降部队',
  ];

  /// 正片开始标记（出现时刻 ≈ 片头结束点）。
  static const List<String> startKeywords = <String>[
    '正片开始',
    '正片開始',
    '开始正片',
    '開始正片',
  ];

  /// 匹配 `MM:SS` 型时间戳，兼容 `1:23:45` 三段。
  /// 分隔符同时接受半角/全角冒号与点号（归一化后统一处理）。
  static final RegExp _timestampPattern =
      RegExp(r'(\d{1,2})([:.])(\d{1,2})(?::(\d{1,2}))?');

  /// 从弹幕列表推导片头区间。证据不足返回 null。
  ///
  /// [durationSeconds] 可选，传入后用于把结束点钳制在片长内，
  /// 避免越界的落点让播放器 seek 到文件末尾。
  static SkipSegment? detect(
    List<DanmakuTextEntry> comments, {
    double? durationSeconds,
  }) {
    if (comments.isEmpty) return null;

    final targets = <_JumpTarget>[];
    final confirmations = <double>[];

    for (final comment in comments) {
      if (!comment.isValid) continue;
      final text = comment.text;
      final time = comment.timeSeconds;

      final target = jumpTarget(text: text);
      if (target != null) {
        targets.add(_JumpTarget(postTime: time, target: target));
      }
      if (_containsAny(text, landingKeywords) ||
          _containsAny(text, startKeywords)) {
        confirmations.add(time);
      }
    }

    final fromTargets = _hintFromTargets(targets, confirmations);
    final hint = fromTargets ?? _landingOnlyHint(targets, confirmations);
    if (hint == null) return null;

    double endSeconds = hint.endSeconds;
    if (durationSeconds != null && durationSeconds > 0) {
      final limit = durationSeconds - 0.5;
      if (endSeconds > limit) endSeconds = limit < 0 ? 0 : limit;
    }
    var startSeconds = hint.startSeconds ?? 0;
    if (startSeconds < 0) startSeconds = 0;
    final startLimit = endSeconds - 1;
    if (startSeconds > startLimit) {
      startSeconds = startLimit < 0 ? 0 : startLimit;
    }
    if (endSeconds <= 1 || startSeconds >= endSeconds - 1) return null;

    return SkipSegment(
      kind: SkipSegmentKind.opening,
      source: SkipSegmentSource.danmaku,
      startSeconds: startSeconds,
      endSeconds: endSeconds,
      evidenceCount: hint.evidenceCount,
    );
  }

  /// 提取报点落点：关键词之后紧跟的时间戳。无关键词或时间戳不合法返回 null。
  static double? jumpTarget({required String text}) {
    for (final keyword in jumpKeywords) {
      final index = text.indexOf(keyword);
      if (index < 0) continue;
      final from = index + keyword.length;
      if (from > text.length) continue;
      final extended = from + targetScanWindow;
      final to = extended > text.length ? text.length : extended;
      final seconds = parseTimestamp(text.substring(from, to));
      if (seconds != null) return seconds;
    }
    return null;
  }

  /// 解析 `MM:SS` 型时间戳，兼容全角冒号、`2.21` 点分隔、`3:9` 单数字秒、
  /// `1:23:45` 三段。
  ///
  /// `1.5` 这类小数不可能是时间戳，拒绝（点分隔要求秒必须两位，否则
  /// 「跳伞1.5倍」会被解析成 90s）。
  static double? parseTimestamp(String text) {
    if (text.isEmpty) return null;
    final normalized = text.replaceAll('：', ':').replaceAll('．', '.');
    final match = _timestampPattern.firstMatch(normalized);
    if (match == null) return null;

    // 前后不能紧贴数字：避免从 "22:17" 里截出 "2:17" 之类的碎片段。
    final start = match.start;
    final end = match.end;
    if (start > 0 && _isDigit(normalized.codeUnitAt(start - 1))) return null;
    if (end < normalized.length && _isDigit(normalized.codeUnitAt(end))) {
      return null;
    }

    final rawMinute = match.group(1);
    final separator = match.group(2);
    final rawSecond = match.group(3);
    final rawHour = match.group(4);
    if (rawMinute == null || separator == null || rawSecond == null) {
      return null;
    }

    final int hour;
    final int minute;
    final int second;
    if (rawHour != null) {
      // 三段式 H:MM:SS：正则的第一段才是小时（上游 OcPlayer 在这里把三段
      // 当成 M:SS:H 解释，1:23:45 会算成 45 小时，本端按标准语义修正）。
      hour = int.tryParse(rawMinute) ?? 0;
      minute = int.tryParse(rawSecond) ?? 0;
      second = int.tryParse(rawHour) ?? 0;
    } else {
      hour = 0;
      minute = int.tryParse(rawMinute) ?? 0;
      second = int.tryParse(rawSecond) ?? 0;
      // 点分隔要求秒必须两位：「跳伞1.5倍」不能被解析成 90s。
      if (separator == '.' && rawSecond.length != 2) return null;
    }
    if (second >= 60 || minute >= 60) return null;

    return (hour * 3600 + minute * 60 + second).toDouble();
  }

  /// 文本是否包含任一关键词。
  static bool _containsAny(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }

  // MARK: 报点主簇 → 片头结束点

  static _IntroHint? _hintFromTargets(
    List<_JumpTarget> targets,
    List<double> confirmations,
  ) {
    if (targets.isEmpty) return null;

    final inRange = targets
        .where((t) => t.target >= targetMin && t.target <= targetMax)
        .toList();
    final cluster = _largestCluster(
      inRange.map((t) => t.target).toList(),
      gap: clusterGap,
    );
    if (cluster == null) return null;
    // 用报点条数衡量证据强度（详见 minJumpTargets 的注释）。
    if (cluster.count < minJumpTargets) return null;

    final end = _roundedMedian(cluster.values);
    final nearConfirmations = confirmations
        .where((c) =>
            c <= targetMax + 60 && (c - end).abs() <= confirmationTolerance)
        .length;
    final confirmed = nearConfirmations > 0;
    final required = confirmed
        ? minJumpTargetsWithConfirmation
        : minJumpTargetsWithoutConfirmation;
    if (cluster.count < required) return null;

    return _IntroHint(
      startSeconds:
          _estimatedStart(targets: inRange, cluster: cluster, end: end),
      endSeconds: end,
      evidenceCount: cluster.count + nearConfirmations,
    );
  }

  /// 把起点钳制在合理范围内。
  ///
  /// 起点过近（片头过短）说明估计没有意义，过远（超过 [maxIntroLength]）
  /// 说明把前情回顾也算进去了。两害相权取其轻：**宁可稍早也不要回到 0**——
  /// 起点 0 会让「跳过片头」按钮从视频第一帧就弹出，而那一段往往是正片。
  static double _clampStart(double candidate, double end) {
    if (end <= minIntroLengthForStartEstimate) return 0.0;
    final latest = end - minIntroLengthForStartEstimate;
    final earliest = end - maxIntroLength;
    var start = candidate;
    if (start > latest) start = latest;
    if (start < earliest) start = earliest;
    if (start < 0) start = 0;
    return start;
  }

  /// 从报点弹幕的出现时刻估计片头起点，无可用信息返回 null。
  ///
  /// 取**中位数**而非最早时刻（2026-09-14 修正）。实测恶女不才 S1E6 的报点
  /// 出现时刻为 68.3 / 72.0 / 80.5 / 81.3 / 86.8，真值（AniSkip）起点 80.2：
  /// 最早值给出 66（偏早 14s），中位数给出 78.5（几乎正中）。原因是少数观众
  /// 会在片头开始前就提前「预告」落点，最小值对这种离群点毫无抵抗力。
  ///
  /// 但中位数也防不住**整批都是预告型**的情况（见 [previewReportThreshold]）：
  /// 碧蓝之海 S3E10 的六条报点全在 0~14s 发出，中位数 1.9s。此时改用
  /// 「end - 典型 OP 长度」反推更接近事实。
  static double? _startFromPostTimes(List<double> postTimes, double end) {
    if (postTimes.isEmpty) return null;
    final sorted = List<double>.of(postTimes)..sort();
    final cluster = _largestCluster(sorted, gap: clusterGap);
    final values = cluster?.values ?? sorted;
    final median = _roundedMedian(values);

    if (median < previewReportThreshold) {
      return _clampStart(end - typicalIntroLength, end);
    }
    return _clampStart((median - 2 < 0 ? 0.0 : median - 2), end);
  }

  /// 片头起点估计：主簇报点弹幕出现时刻的中位数。观众在片头播到一半前后就会
  /// 发报点，因此中位数 ≈ 片头内某点；有冷开场的集该值明显大于 0。
  ///
  /// 取中位数的理由与离群点处理见 [_startFromPostTimes]。
  static double? _estimatedStart({
    required List<_JumpTarget> targets,
    required _Cluster cluster,
    required double end,
  }) {
    final clusterTargets = cluster.values.map(_rounded).toSet();
    final postTimes = <double>[];
    for (final target in targets) {
      if (!clusterTargets.contains(_rounded(target.target))) continue;
      postTimes.add(target.postTime);
    }
    if (postTimes.isEmpty) return null;

    final start = _startFromPostTimes(postTimes, end);
    if (start == null) return null;
    // 片头长度本身也要合理，否则这个起点没有参考价值。
    final length = end - start;
    if (length < minIntroLengthForStartEstimate) return null;
    if (length > maxIntroLength) return null;
    return start;
  }

  // MARK: 仅着陆确认路径

  /// 报点不足时，≥3 条着陆确认聚在一起也能定位片头结束点。
  ///
  /// 着陆弹幕都发在片头末尾，本身不含起点信息。但**不能直接回落 0**——那会让
  /// 按钮从第一帧就弹出（正是用户反馈的问题）。退而求其次：有报点弹幕就用它们的
  /// 出现时刻估（哪怕条数不够主路径门槛），实在没有再按典型 OP 长度反推。
  static _IntroHint? _landingOnlyHint(
    List<_JumpTarget> targets,
    List<double> confirmations,
  ) {
    if (confirmations.length < minLandingOnlyConfirmations) return null;
    final candidates = confirmations.where((c) => c <= targetMax + 60).toList();
    final cluster = _largestCluster(candidates, gap: clusterGap);
    if (cluster == null) return null;
    if (cluster.count < minLandingOnlyConfirmations) return null;

    final end = _roundedMedian(cluster.values);
    if (end < targetMin || end > targetMax) return null;

    final inRange = targets
        .where((t) => t.target >= targetMin && t.target <= targetMax)
        .toList();
    final start = _startFromPostTimes(
          inRange.map((t) => t.postTime).toList(),
          end,
        ) ??
        _clampStart(end - typicalIntroLength, end);

    return _IntroHint(
        startSeconds: start, endSeconds: end, evidenceCount: cluster.count);
  }

  // MARK: 聚合

  /// 把数值按间距聚成簇（排序后相邻差 ≤ gap 归同簇），返回最大的簇。
  /// 并列时取最早的簇：靠前的簇更可能是片头落点。
  static _Cluster? _largestCluster(List<double> values, {required double gap}) {
    if (values.isEmpty) return null;
    final sorted = List<double>.of(values)..sort();
    final clusters = <List<double>>[
      <double>[sorted.first],
    ];
    for (final value in sorted.skip(1)) {
      final last = clusters.last;
      if (value - last.last <= gap) {
        last.add(value);
      } else {
        clusters.add(<double>[value]);
      }
    }
    var best = clusters.first;
    for (final cluster in clusters.skip(1)) {
      if (cluster.length > best.length) best = cluster;
    }
    return _Cluster(values: best, count: best.length);
  }

  static double _rounded(double value) => (value * 10).round() / 10;

  static double _roundedMedian(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isEven
        ? (sorted[mid - 1] + sorted[mid]) / 2
        : sorted[mid];
    return median.roundToDouble();
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;
}

/// 一条报点：弹幕出现时刻 + 报出的落点。
class _JumpTarget {
  final double postTime;
  final double target;

  const _JumpTarget({required this.postTime, required this.target});
}

/// 聚合出的数值簇。
class _Cluster {
  final List<double> values;
  final int count;

  const _Cluster({
    required this.values,
    required this.count,
  });
}

/// 检测器内部结果（尚未转成对外区间）。
class _IntroHint {
  final double? startSeconds;
  final double endSeconds;
  final int evidenceCount;

  const _IntroHint({
    required this.startSeconds,
    required this.endSeconds,
    required this.evidenceCount,
  });
}
