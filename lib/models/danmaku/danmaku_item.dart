
// lib/models/danmaku/danmaku_item.dart
// 弹幕模型

import 'package:nipaplay/constants/danmaku/mode.dart';


/// 应用层中的一条弹幕.
///
/// 该模型只保存源弹幕及其业务元数据.
/// 轨道, 坐标, 速度, 合并状态等渲染期
/// 数据应由对应的布局或渲染模型保存.
///
/// 当前旧代码仍使用 `Map<String, dynamic>`; [fromMap] 与 [toMap] 用于后续
/// 渐进迁移, 本模型暂不改变既有数据流.
class DanmakuItem {

  /// 用于标记 [copyWith] 中未提供的参数, 与 `null` 区分.
  static const Object _notProvided = Object();

  DanmakuItem({
    required this.time,
    required this.content,
    this.mode = DanmakuMode.scroll,
    int colorRgb = 0xFFFFFF,
    this.isMe = false,
    this.senderId,
    this.danmakuId,
    this.sentAt,
    this.source,
    this.fontSize,
    this.pool,
    this.weight,
    Map<String, dynamic> extra = const {},
  }) :
    colorRgb = colorRgb & 0xFFFFFF,
    extra = Map<String, dynamic>.unmodifiable(extra)
  ;


  // ------------------------------
  // -------- 弹幕数据字段 --------
  // ------------------------------

  final  Duration     time;       // 弹幕在视频时间轴中的出现时间
  final  String       content;    // 弹幕文本内容
  final  DanmakuMode  mode;       // 弹幕协议模式
  final  int          colorRgb;   // 24 位 RGB 颜色, 格式为 `0xRRGGBB`
  final  bool         isMe;       // 是否由当前用户发送
  final  String?      senderId;   // 数据源提供的发送者身份标识或匿名哈希
  final  String?      danmakuId;  // 数据源提供的弹幕 ID, 不等同于发送者身份
  final  DateTime?    sentAt;     // 弹幕实际发送时间
  final  String?      source;     // 弹幕来源或轨道名称
  final  double?      fontSize;   // 数据源指定的原始字号
  final  int?         pool;       // 数据源中的弹幕池编号
  final  int?         weight;     // 数据源中的弹幕权重

  /// 尚未建模的插件或数据源扩展字段
  final Map<String, dynamic> extra;


  // ------------------------------
  // -------- 辅助计算字段 --------
  // ------------------------------

  /// 弹幕出现时间, 单位为秒
  double get timeSeconds => time.inMicroseconds / Duration.microsecondsPerSecond;

  /// 弹幕颜色的 CSS 十六进制表示, 格式为 `#RRGGBB`
  String get colorHex => '#${colorRgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// 弹幕颜色的 CSS RGB 表示, 格式为 `rgb(R,G,B)`
  String get colorCss {
    final red   = (colorRgb >> 16) & 0xFF;
    final green = (colorRgb >> 8) & 0xFF;
    final blue  = colorRgb & 0xFF;
    return 'rgb($red,$green,$blue)';
  }

  /// 从已经进入应用层的旧 Map 创建强类型弹幕.
  ///
  /// 支持 `time/t`, `content/c/m`, `type/y`, `color/r` 等旧字段别名.
  /// 网络协议中的复合字段 (例如 `p`) 应先由对应数据源解析器拆解.
  factory DanmakuItem.fromMap(Map<dynamic, dynamic> map) {
    final raw = Map<String, dynamic>.from(map);
    final extra = Map<String, dynamic>.from(raw);
    const Set<String> modeledMapKeys = {
      'time',
      't',
      'content',
      'c',
      'm',
      'type',
      'y',
      'mode',
      'originalType',
      'color',
      'r',
      'isMe',
      'senderId',
      'danmakuId',
      'cid',
      'id',
      'sentAt',
      'sendTimestamp',
      'timestamp',
      'source',
      'trackName',
      'track',
      'fontSize',
      'size',
      'fontsize',
      'pool',
      'weight',
      'visible',
    };
    for (final key in modeledMapKeys) {
      extra.remove(key);
    }

    return DanmakuItem(
      time: _parseTime(raw['time'] ?? raw['t']),
      content: (raw['content'] ?? raw['c'] ?? raw['m'])?.toString() ?? '',
      mode: _parseMode(raw),
      colorRgb: _parseColor(raw['color'] ?? raw['r']),
      isMe: _parseBool(raw['isMe']),
      senderId: _resolveSenderId(raw),
      danmakuId: _nonEmptyString(
        raw['danmakuId'] ?? raw['cid'] ?? raw['id'],
      ),
      sentAt: _parseDateTime(
        raw['sentAt'] ?? raw['sendTimestamp'] ?? raw['timestamp'],
      ),
      source: _nonEmptyString(
        raw['source'] ?? raw['trackName'] ?? raw['track'],
      ),
      fontSize: _parseDouble(
        raw['fontSize'] ?? raw['size'] ?? raw['fontsize'],
      ),
      pool: _parseInt(raw['pool']),
      weight: _parseInt(raw['weight']),
      extra: extra,
    );
  }

  /// 转换为当前旧代码使用的标准 Map 结构.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      ...extra,
      'time': timeSeconds,
      'content': content,
      'type': mode.typeName,
      'originalType': mode.code,
      'color': colorCss,
      'isMe': isMe,
      if (senderId != null) 'senderId': senderId,
      if (danmakuId != null) 'danmakuId': danmakuId,
      if (sentAt != null)
        'timestamp': sentAt!.millisecondsSinceEpoch ~/ 1000,
      if (source != null) 'source': source,
      if (fontSize != null) 'fontSize': fontSize,
      if (pool != null) 'pool': pool,
      if (weight != null) 'weight': weight,
    };
  }

  /// 创建一个新的弹幕对象, 仅修改指定字段.
  DanmakuItem copyWith({
    Duration? time,
    String? content,
    DanmakuMode? mode,
    int? colorRgb,
    bool? isMe,
    Object? senderId = _notProvided,
    Object? danmakuId = _notProvided,
    Object? sentAt = _notProvided,
    Object? source = _notProvided,
    Object? fontSize = _notProvided,
    Object? pool = _notProvided,
    Object? weight = _notProvided,
    Map<String, dynamic>? extra,
  }) {
    return DanmakuItem(
      time: time ?? this.time,
      content: content ?? this.content,
      mode: mode ?? this.mode,
      colorRgb: colorRgb ?? this.colorRgb,
      isMe: isMe ?? this.isMe,
      senderId: identical(senderId, _notProvided)
          ? this.senderId
          : senderId as String?,
      danmakuId: identical(danmakuId, _notProvided)
          ? this.danmakuId
          : danmakuId as String?,
      sentAt: identical(sentAt, _notProvided)
          ? this.sentAt
          : sentAt as DateTime?,
      source: identical(source, _notProvided)
          ? this.source
          : source as String?,
      fontSize: identical(fontSize, _notProvided)
          ? this.fontSize
          : fontSize as double?,
      pool: identical(pool, _notProvided) ? this.pool : pool as int?,
      weight: identical(weight, _notProvided)
          ? this.weight
          : weight as int?,
      extra: extra ?? this.extra,
    );
  }

  static Duration _parseTime(dynamic value) {
    if (value is Duration) return value;
    final seconds = _parseDouble(value);
    if (seconds == null || seconds.isNaN || seconds.isInfinite) {
      return Duration.zero;
    }
    return Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
  }

  static DanmakuMode _parseMode(Map<String, dynamic> raw) {
    final value = raw['originalType'] ?? raw['mode'] ?? raw['type'] ?? raw['y'];
    if (value is DanmakuMode) return value;
    if (value is num) return DanmakuMode.fromCode(value.toInt());

    final text = value?.toString().trim();
    final code = int.tryParse(text ?? '');
    if (code != null) return DanmakuMode.fromCode(code);
    return DanmakuMode.fromTypeName(text?.split('.').last);
  }

  static int _parseColor(dynamic value) {
    if (value is num) return value.toInt() & 0xFFFFFF;
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return 0xFFFFFF;

    final rgb = RegExp(
      r'^rgb\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (rgb != null) {
      final red = (int.tryParse(rgb.group(1) ?? '') ?? 255).clamp(0, 255);
      final green = (int.tryParse(rgb.group(2) ?? '') ?? 255).clamp(0, 255);
      final blue = (int.tryParse(rgb.group(3) ?? '') ?? 255).clamp(0, 255);
      return (red << 16) | (green << 8) | blue;
    }

    final hexText = text.startsWith('#')
        ? text.substring(1)
        : text.toLowerCase().startsWith('0x')
            ? text.substring(2)
            : null;
    final parsed = hexText == null
        ? int.tryParse(text)
        : int.tryParse(hexText, radix: 16);
    return (parsed ?? 0xFFFFFF) & 0xFFFFFF;
  }

  static String? _resolveSenderId(Map<String, dynamic> raw) {
    for (final key in const [
      'senderId',
      'sender',
      'userId',
      'userID',
      'uid',
      'midHash',
      'userHash',
      'hash',
    ]) {
      final value = _nonEmptyString(raw[key]);
      if (value != null) return value;
    }

    for (final nested in [raw['user'], raw['sender']]) {
      if (nested is! Map) continue;
      for (final key in const ['id', 'uid', 'hash']) {
        final value = _nonEmptyString(nested[key]);
        if (value != null) return value;
      }
    }

    // 弹弹 play 原始弹幕的 p 字段格式为 时间,模式,颜色,发送者标识.
    // C++ 标准化路径会透传 p, 但不会额外生成 senderId.
    final p = raw['p']?.toString().split(',');
    if (p != null && p.length > 3) {
      final value = _nonEmptyString(p[3]);
      if (value != null) return value;
    }
    return _nonEmptyString(raw['cid']);
  }

  static String? _nonEmptyString(dynamic value) {
    if (value == null || value is Map || value is Iterable) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == '0' || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  static double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int? _parseInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value?.toString().toLowerCase() == 'true';
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    final numeric = value is num ? value.toInt() : int.tryParse('$value');
    if (numeric != null) {
      final milliseconds = numeric.abs() >= 100000000000
          ? numeric
          : numeric * Duration.millisecondsPerSecond;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    return DateTime.tryParse(value?.toString() ?? '');
  }
}

/// 用于显示的弹幕数据项,
/// 定义一个在 UI 中渲染的弹幕实例, 包含弹幕元数据和渲染期状态.
class DisplayDanmakuItem {

  final int         index;     // 弹幕在列表中的索引
  final DanmakuItem item;      // 弹幕元数据引用

  final bool        isActive;  // 弹幕是否在当前播放位置显示
  final Duration    startTime; // 弹幕实际显示的起始时间 (考虑了时间偏移)
  final Duration    duration;  // 弹幕显示持续时间
  final bool        isBlocked; // 弹幕是否被屏蔽

  const DisplayDanmakuItem({
    required this.item,
    required this.index,
    required this.startTime,
    required this.duration,
    required this.isBlocked,
    required this.isActive,
  });
}
