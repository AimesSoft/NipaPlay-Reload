import 'package:flutter/foundation.dart';

const String titanDanmakuPluginId = 'titan_danmaku_renderer';
const String titanDanmakuRendererId = 'titan';

@immutable
class TitanDanmakuFontOption {
  const TitanDanmakuFontOption(this.label, this.value);

  final String label;
  final String value;
}

@immutable
class TitanDanmakuSettings {
  const TitanDanmakuSettings({
    this.opacity = 0.85,
    this.fontSize = 1.0,
    this.bold = true,
    this.fontBorder = 0,
    this.fontFamily = defaultFontFamily,
    this.speedPlus = 1.0,
    this.density = 1.0,
    this.duration = 4.5,
    this.limit = 300,
    this.preventShade = false,
    this.offsetTop = 3,
    this.offsetBottom = 0,
    this.maxLength = 50,
    this.isRecyclingDom = true,
    this.isRecyclingModel = false,
    this.forbidShrinkState = true,
  });

  static const String defaultFontFamily =
      "SimHei, 'Microsoft JhengHei', Arial, Helvetica, sans-serif";
  static const int persistenceSchemaVersion = 2;

  static const String simplifiedChineseFontFamily =
      "-apple-system, 'PingFang SC', 'Hiragino Sans GB', "
      "'Microsoft YaHei', 'Noto Sans CJK SC', 'Source Han Sans SC', "
      'sans-serif';

  static const List<TitanDanmakuFontOption> fontOptions =
      <TitanDanmakuFontOption>[
    TitanDanmakuFontOption(
      '黑体',
      defaultFontFamily,
    ),
    TitanDanmakuFontOption('简体系统字体', simplifiedChineseFontFamily),
    TitanDanmakuFontOption('宋体', 'SimSun, serif'),
    TitanDanmakuFontOption('新宋体', 'NSimSun, serif'),
    TitanDanmakuFontOption('仿宋', 'FangSong, serif'),
    TitanDanmakuFontOption(
      '微软雅黑',
      "'Microsoft YaHei', sans-serif",
    ),
    TitanDanmakuFontOption(
      '微软雅黑 Light',
      "'Microsoft YaHei UI Light', sans-serif",
    ),
    TitanDanmakuFontOption(
      'Noto Sans DemiLight',
      "'Noto Sans CJK SC DemiLight', sans-serif",
    ),
    TitanDanmakuFontOption(
      'Noto Sans Regular',
      "'Noto Sans CJK SC Regular', sans-serif",
    ),
  ];

  final double opacity;
  final double fontSize;
  final bool bold;
  final int fontBorder;
  final String fontFamily;
  final double speedPlus;
  final double density;
  final double duration;
  final int limit;
  final bool preventShade;
  final int offsetTop;
  final int offsetBottom;
  final int maxLength;
  final bool isRecyclingDom;
  final bool isRecyclingModel;
  final bool forbidShrinkState;

  String get fontFamilyLabel {
    for (final option in fontOptions) {
      if (option.value == fontFamily) return option.label;
    }
    return fontOptions.first.label;
  }

  String get fontBorderLabel => switch (fontBorder) {
        1 => '描边',
        2 => '45° 投影',
        _ => '重墨',
      };

  TitanDanmakuSettings copyWith({
    double? opacity,
    double? fontSize,
    bool? bold,
    int? fontBorder,
    String? fontFamily,
    double? speedPlus,
    double? density,
    double? duration,
    int? limit,
    bool? preventShade,
    int? offsetTop,
    int? offsetBottom,
    int? maxLength,
    bool? isRecyclingDom,
    bool? isRecyclingModel,
    bool? forbidShrinkState,
  }) {
    return TitanDanmakuSettings(
      opacity: (opacity ?? this.opacity).clamp(0.2, 1.0).toDouble(),
      fontSize: (fontSize ?? this.fontSize).clamp(0.5, 2.0).toDouble(),
      bold: bold ?? this.bold,
      fontBorder: (fontBorder ?? this.fontBorder).clamp(0, 2),
      fontFamily: _normalizeFontFamily(fontFamily ?? this.fontFamily),
      speedPlus: (speedPlus ?? this.speedPlus).clamp(0.25, 3.0).toDouble(),
      density: (density ?? this.density).clamp(0.1, 1.0).toDouble(),
      duration: (duration ?? this.duration).clamp(2.0, 12.0).toDouble(),
      limit: (limit ?? this.limit).clamp(0, 5000),
      preventShade: preventShade ?? this.preventShade,
      offsetTop: (offsetTop ?? this.offsetTop).clamp(-1000, 1000),
      offsetBottom: (offsetBottom ?? this.offsetBottom).clamp(-1000, 1000),
      maxLength: (maxLength ?? this.maxLength).clamp(0, 1000),
      isRecyclingDom: isRecyclingDom ?? this.isRecyclingDom,
      isRecyclingModel: isRecyclingModel ?? this.isRecyclingModel,
      forbidShrinkState: forbidShrinkState ?? this.forbidShrinkState,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': persistenceSchemaVersion,
        'opacity': opacity,
        'fontSize': fontSize,
        'bold': bold,
        'fontBorder': fontBorder,
        'fontFamily': fontFamily,
        'speedPlus': speedPlus,
        'density': density,
        'duration': duration,
        'limit': limit,
        'preventShade': preventShade,
        'offsetTop': offsetTop,
        'offsetBottom': offsetBottom,
        'maxLength': maxLength,
        'isRecyclingDom': isRecyclingDom,
        'isRecyclingModel': isRecyclingModel,
        'forbidShrinkState': forbidShrinkState,
      };

  factory TitanDanmakuSettings.fromJson(Map<String, dynamic> json) {
    const defaults = TitanDanmakuSettings();
    final schemaVersion = _asInt(json['schemaVersion']) ?? 1;
    return defaults.copyWith(
      opacity: _asDouble(json['opacity']),
      fontSize: _asDouble(json['fontSize']),
      bold: _asBool(json['bold']),
      fontBorder: _asInt(json['fontBorder']),
      fontFamily: json['fontFamily']?.toString(),
      speedPlus: _asDouble(json['speedPlus']),
      density: _asDouble(json['density']),
      duration: _asDouble(json['duration']),
      limit: _asInt(json['limit']),
      preventShade: _asBool(json['preventShade']),
      offsetTop: schemaVersion < persistenceSchemaVersion
          ? defaults.offsetTop
          : _asInt(json['offsetTop']),
      offsetBottom: _asInt(json['offsetBottom']),
      maxLength: _asInt(json['maxLength']),
      isRecyclingDom: _asBool(json['isRecyclingDom']),
      isRecyclingModel: _asBool(json['isRecyclingModel']),
      forbidShrinkState: _asBool(json['forbidShrinkState']),
    );
  }

  static double? _asDouble(dynamic value) =>
      value is num ? value.toDouble() : null;

  static int? _asInt(dynamic value) => value is num ? value.toInt() : null;

  static bool? _asBool(dynamic value) => value is bool ? value : null;

  static String _normalizeFontFamily(String value) {
    for (final option in fontOptions) {
      if (option.value == value) return value;
    }
    return defaultFontFamily;
  }
}
