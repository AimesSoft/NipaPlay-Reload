
// lib/constants/danmaku/ass_kind.dart
// 实现 弹幕数据 -> ASS 字幕文本

import 'package:nipaplay/constants/danmaku/ass_kind.dart';
import 'package:nipaplay/constants/danmaku/mode.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/utils/danmaku_xml_utils.dart';


/// ASS 字幕导出用的描边样式。
/// 与 [DanmakuOutlineStyle] 一一对应，但保持本转换器零外部依赖以便单测。
enum AssOutlineStyle { none, stroke, uniform }

/// ASS 字幕导出用的阴影样式。与 [DanmakuShadowStyle] 一一对应。
/// ASS 只支持硬阴影（无 blur），soft/medium/strong 用不同深度+透明度近似。
enum AssShadowStyle { none, soft, medium, strong }

/// 顶部/底部弹幕的固定显示时长（秒）。非用户设置，按经验取值。
const double kAssFixedDanmakuDurationSeconds = 5.0;

/// ASS 脚本基准分辨率。播放器会按视频实际分辨率自动缩放。
const int kAssPlayResX = 1920;
const int kAssPlayResY = 1080;

/// 把内置弹幕渲染设置打包给 [convertDanmakuToAss]。
/// 字段含义与 [VideoPlayerState] 同名 getter 一致。
class AssExportSettings {
  /// 内置实际显示字号（像素）。会被映射到 ASS 的 1080 空间。
  final double fontSize;

  /// 0..1 透明度（1 = 不透明）。
  final double opacity;

  /// 0..1 可用显示区域占视频高度比例。
  final double displayArea;

  /// 滚动弹幕横穿屏幕的时长（秒）。
  final double scrollDurationSeconds;

  /// 时间偏移（秒），叠加到每条弹幕的起始时间。
  final double timeOffsetSeconds;

  /// 是否合并相同内容 + 小时间窗的重复弹幕。
  final bool mergeDuplicates;

  /// 字体族名（需系统已安装）；为空则用默认。
  final String? fontFamily;

  /// 描边样式。
  final AssOutlineStyle outlineStyle;

  /// 描边宽度（像素，1080 空间）。
  final double outlineWidth;

  /// 阴影样式。
  final AssShadowStyle shadowStyle;

  const AssExportSettings({
    required this.fontSize,
    this.opacity = 1.0,
    this.displayArea = 1.0,
    this.scrollDurationSeconds = 10.0,
    this.timeOffsetSeconds = 0.0,
    this.mergeDuplicates = false,
    this.fontFamily,
    this.outlineStyle = AssOutlineStyle.stroke,
    this.outlineWidth = 1.0,
    this.shadowStyle = AssShadowStyle.none,
  });

  AssExportSettings copyWith({
    double? fontSize,
    double? opacity,
    double? displayArea,
    double? scrollDurationSeconds,
    double? timeOffsetSeconds,
    bool? mergeDuplicates,
    String? fontFamily,
    AssOutlineStyle? outlineStyle,
    double? outlineWidth,
    AssShadowStyle? shadowStyle,
  }) {
    return AssExportSettings(
      fontSize: fontSize ?? this.fontSize,
      opacity: opacity ?? this.opacity,
      displayArea: displayArea ?? this.displayArea,
      scrollDurationSeconds:
          scrollDurationSeconds ?? this.scrollDurationSeconds,
      timeOffsetSeconds: timeOffsetSeconds ?? this.timeOffsetSeconds,
      mergeDuplicates: mergeDuplicates ?? this.mergeDuplicates,
      fontFamily: fontFamily ?? this.fontFamily,
      outlineStyle: outlineStyle ?? this.outlineStyle,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      shadowStyle: shadowStyle ?? this.shadowStyle,
    );
  }
}


/// 把过滤后的弹幕列表转换为 ASS 字幕文本。
///
/// ASS 事件按媒体时间轴渲染，播放器的播放/暂停/跳转/倍速都直接驱动
/// 媒体时间，因此弹幕会自动同步——零外部同步代码。
///
/// 滚动弹幕使用经典 Danmaku2ASS 车道碰撞算法：每条分配一条水平车道，
/// 前一条"完全进入屏幕"后释放车道。顶/底部弹幕用固定时长 + 垂直车道。
String convertDanmakuToAss(
  List<Map<String, dynamic>> danmaku,
  AssExportSettings settings,
) {
  final assFontSize = resolveAssFontSize(settings.fontSize);
  final laneHeight = (assFontSize * 1.3).round().clamp(1, kAssPlayResY);
  final laneCount =
      (kAssPlayResY * settings.displayArea / laneHeight).floor().clamp(1, 64);

  final alphaHex = _alphaHexFromOpacity(settings.opacity);
  final styleName = _styleFontName(settings.fontFamily);
  final outline = _resolveOutline(settings.outlineStyle, settings.outlineWidth);
  final (shadowDepth, backColour) = _resolveShadow(settings.shadowStyle);

  final buffer = StringBuffer();
  _writeHeader(buffer, assFontSize, styleName, outline, shadowDepth, backColour,
      playResX: kAssPlayResX, playResY: kAssPlayResY);

  // 解析 + 偏移 + 排序
  final parsed = <_ParsedDanmaku>[];
  for (final item in danmaku) {
    if (item['visible'] == false) continue;
    final content = _resolveContent(item);
    if (content.isEmpty) continue;
    final time = _resolveTime(item) + settings.timeOffsetSeconds;
    if (time < 0) continue; // 偏移后落到 0 之前的丢弃
    final kind = _resolveKind(item);
    final color = parseDanmakuColorToInt(item['color'] ?? item['r']);
    parsed.add(_ParsedDanmaku(
      content: content,
      time: time,
      kind: kind,
      color: color,
    ));
  }
  parsed.sort((a, b) => a.time.compareTo(b.time));

  final merged = settings.mergeDuplicates ? _mergeDuplicates(parsed) : parsed;

  final scrollLanes = List<double?>.filled(laneCount, null, growable: false);
  final topLanes = List<double?>.filled(laneCount, null, growable: false);
  final bottomLanes = List<double?>.filled(laneCount, null, growable: false);
  buffer.writeln('[Events]');
  buffer.writeln(
      'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');

  for (final d in merged) {
    final width = _estimateWidth(d.content, assFontSize);
    switch (d.kind) {
      case DanmakuKind.scroll:
        final duration =
            (settings.scrollDurationSeconds.isFinite &&
                    settings.scrollDurationSeconds > 0)
                ? settings.scrollDurationSeconds
                : 10.0;
        final lane = _pickScrollLane(scrollLanes, d.time, width, duration);
        if (lane < 0) break; // 无车道可放，丢弃（经典行为，避免重叠）
        final yCenter = (lane * laneHeight + laneHeight / 2).toDouble();
        final xEnd = -width;
        final line =
            '{\\an4\\move($kAssPlayResX,${yCenter.toStringAsFixed(1)},'
            '${xEnd.toStringAsFixed(1)},${yCenter.toStringAsFixed(1)})'
            '${_colorOverride(d.color)}${_outlineColorOverride(d.color)}\\1a$alphaHex}'
            '${_escapeAssText(d.content)}';
        _writeDialogue(
          buffer,
          layer: 0,
          start: d.time,
          end: d.time + duration,
          style: 'Danmaku',
          text: line,
        );
        break;
      case DanmakuKind.top:
        const duration = kAssFixedDanmakuDurationSeconds;
        final lane = _pickFixedLane(topLanes, d.time, duration);
        final yTop = (lane * laneHeight + 2).toDouble();
        final line =
            '{\\an8\\pos(${(kAssPlayResX ~/ 2)},${yTop.toStringAsFixed(1)})'
            '${_colorOverride(d.color)}${_outlineColorOverride(d.color)}\\1a$alphaHex}'
            '${_escapeAssText(d.content)}';
        _writeDialogue(
          buffer,
          layer: 1,
          start: d.time,
          end: d.time + duration,
          style: 'DanmakuTop',
          text: line,
        );
        break;
      case DanmakuKind.bottom:
        const duration = kAssFixedDanmakuDurationSeconds;
        final lane = _pickFixedLane(bottomLanes, d.time, duration);
        final yBottom = (kAssPlayResY - lane * laneHeight - 2).toDouble();
        final line =
            '{\\an2\\pos(${(kAssPlayResX ~/ 2)},${yBottom.toStringAsFixed(1)})'
            '${_colorOverride(d.color)}${_outlineColorOverride(d.color)}\\1a$alphaHex}'
            '${_escapeAssText(d.content)}';
        _writeDialogue(
          buffer,
          layer: 2,
          start: d.time,
          end: d.time + duration,
          style: 'DanmakuBottom',
          text: line,
        );
        break;
    }
  }

  return buffer.toString();
}

/// 把强类型应用层弹幕转换为 ASS 字幕文本.
String convertDanmakuItemsToAss(
  List<DanmakuItem> danmaku,
  AssExportSettings settings,
) {
  return convertDanmakuToAss(
    danmaku.map((item) => item.toMap()).toList(growable: false),
    settings,
  );
}

class _ParsedDanmaku {
  final String content;
  final double time;
  final DanmakuKind kind;
  final int color; // 0xRRGGBB

  const _ParsedDanmaku({
    required this.content,
    required this.time,
    required this.kind,
    required this.color,
  });
}

// ---------- 解析助手 ----------

double _resolveTime(Map<String, dynamic> item) {
  final v = item['time'] ?? item['t'];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

String _resolveContent(Map<String, dynamic> item) {
  final v = item['content'] ?? item['c'];
  if (v == null) return '';
  return v.toString();
}

DanmakuKind _resolveKind(Map<String, dynamic> item) {

  final original = item['originalType'];
  if (original is num) return _kindFromMode(DanmakuMode.fromCode(original.toInt()));

  final v = item['type'] ?? item['y'];
  if (v is num) { return _kindFromMode(DanmakuMode.fromCode     (v .toInt()   )); }
  else          { return _kindFromMode(DanmakuMode.fromTypeName (v?.toString())); }
}

DanmakuKind _kindFromMode(DanmakuMode mode) {
  switch (mode)
  {
  case DanmakuMode.top    : return DanmakuKind.top   ;
  case DanmakuMode.bottom : return DanmakuKind.bottom;
  default                 : return DanmakuKind.scroll;
  }
}

// ---------- 字号 / 字体 / 描边 ----------

double resolveAssFontSize(double inAppFontSize) {
  // 内置字号基于播放器 widget 像素，ASS 字号基于 1080 空间。
  // 经验映射 ×1.6 并夹到合理区间；用户可通过内置字号设置微调。
  final mapped = inAppFontSize * 1.6;
  return mapped.clamp(18.0, 96.0);
}

String _styleFontName(String? fontFamily) {
  final trimmed = fontFamily?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'Microsoft YaHei';
  return trimmed;
}

(String, String) _resolveOutline(
    AssOutlineStyle style, double outlineWidth) {
  // 返回 (Outline, BorderStyle)。BorderStyle 1=描边+阴影, 3=不透明底框。
  switch (style) {
    case AssOutlineStyle.none:
      return ('0.0', '1');
    case AssOutlineStyle.stroke:
      final w = outlineWidth.clamp(0.0, 8.0).toStringAsFixed(1);
      return (w, '1');
    case AssOutlineStyle.uniform:
      // uniform（描边等宽）用更粗的 Outline 近似
      final uw = (outlineWidth * 1.5).clamp(0.0, 8.0).toStringAsFixed(1);
      return (uw, '1');
  }
}

/// 阴影样式 → (Shadow 深度, BackColour)。
/// ASS 只支持硬阴影（无 blur），用深度 + BackColour 透明度近似 soft/medium/strong。
/// BackColour 的 alpha = (1 - 阴影不透明度) × 255，越强越不透明。
(String shadowDepth, String backColour) _resolveShadow(AssShadowStyle style) {
  switch (style) {
    case AssShadowStyle.none:
      return ('0.0', '&H00000000');
    case AssShadowStyle.soft:
      return ('1.0', '&HA8000000'); // 0.34 不透明 → 66% 透 → A8
    case AssShadowStyle.medium:
      return ('1.5', '&H8F000000'); // 0.44 → 8F
    case AssShadowStyle.strong:
      return ('2.0', '&H73000000'); // 0.55 → 73
  }
}

// ---------- 颜色 / 透明度 ----------

/// `opacity`(0..1) → ASS alpha 字节 `&HAA&`（opacity=0 → AA=FF 全透明）。
String _alphaHexFromOpacity(double opacity) {
  final o = opacity.clamp(0.0, 1.0);
  final alpha = ((1.0 - o) * 255.0).round().clamp(0, 255);
  return '&H${alpha.toRadixString(16).toUpperCase().padLeft(2, '0')}&';
}

/// `0xRRGGBB` → ASS `\c&HBBGGRR&` 覆盖（白色则省略，沿用样式）。
String _colorOverride(int rgb) {
  if (rgb == 0xFFFFFF) return '';
  final r = (rgb >> 16) & 0xFF;
  final g = (rgb >> 8) & 0xFF;
  final b = rgb & 0xFF;
  final bgr = (b << 16) | (g << 8) | r;
  return '\\c&H${bgr.toRadixString(16).toUpperCase().padLeft(6, '0')}&';
}

/// 暗色弹幕（近纯黑）用白描边，其余沿用样式黑描边。
/// 与 Next2/DFM+ 渲染管线 `stroke_color` 一致：r/g/b 均 ≤ 8 视为黑 → 白描边。
/// 返回 ASS `\3c` 覆盖（空 = 沿用样式黑描边）。
String _outlineColorOverride(int rgb) {
  final r = (rgb >> 16) & 0xFF;
  final g = (rgb >> 8) & 0xFF;
  final b = rgb & 0xFF;
  if (r <= 8 && g <= 8 && b <= 8) {
    return r'\3c&HFFFFFF&';
  }
  return '';
}

// ---------- 宽度估算 ----------

double _estimateWidth(String content, double fontSize) {
  if (content.isEmpty) return fontSize;
  var width = 0.0;
  for (final code in content.codeUnits) {
    // CJK / 全角近似 1 倍字号宽，ASCII 半角 0.6 倍。
    final isWide = code >= 0x1100 &&
        (code <= 0x115F ||
            (code >= 0x2E80 && code <= 0xA4CF) ||
            (code >= 0xAC00 && code <= 0xD7A3) ||
            (code >= 0xF900 && code <= 0xFAFF) ||
            (code >= 0xFE30 && code <= 0xFE4F) ||
            (code >= 0xFF00 && code <= 0xFF60) ||
            (code >= 0xFFE0 && code <= 0xFFE6));
    width += isWide ? fontSize : fontSize * 0.6;
  }
  return width;
}

// ---------- 车道分配 ----------

/// 滚动车道：返回可放的车道索引，无则 -1（丢弃，避免重叠）。
/// 释放判定：上一条"完全进入屏幕"，即 freeAt = t + width/v，
/// 其中 v = (PlayResX + width) / duration。
int _pickScrollLane(
  List<double?> laneFreeAt,
  double t,
  double width,
  double duration,
) {
  for (int i = 0; i < laneFreeAt.length; i++) {
    final freeAt = laneFreeAt[i];
    if (freeAt == null || t >= freeAt) {
      laneFreeAt[i] = _scrollLaneFreeAt(t, width, duration);
      return i;
    }
  }
  return -1;
}

/// 一条滚动弹幕放入后，其车道再次可放的最早时间：
/// 它"完全进入屏幕"的时刻 = t + width / v，v = (PlayResX + width) / duration。
double _scrollLaneFreeAt(double t, double width, double duration) {
  final v = (kAssPlayResX + width) / duration;
  if (v <= 0) return t + duration;
  return t + width / v;
}

/// 顶/底部固定弹幕车道：返回可放车道（无空闲则取最早释放者，接受轻微重叠）。
int _pickFixedLane(List<double?> laneFreeAt, double t, double duration) {
  int earliest = -1;
  double earliestFreeAt = double.infinity;
  for (int i = 0; i < laneFreeAt.length; i++) {
    final freeAt = laneFreeAt[i];
    if (freeAt == null || t >= freeAt) {
      laneFreeAt[i] = t + duration;
      return i;
    }
    if (freeAt < earliestFreeAt) {
      earliestFreeAt = freeAt;
      earliest = i;
    }
  }
  if (earliest >= 0) {
    laneFreeAt[earliest] = earliestFreeAt + duration;
  }
  return earliest;
}

// ---------- 合并去重 ----------

List<_ParsedDanmaku> _mergeDuplicates(List<_ParsedDanmaku> list) {
  if (list.length < 2) return list;
  final result = <_ParsedDanmaku>[];
  String? lastContent;
  double? lastTime;
  for (final d in list) {
    if (lastContent == d.content &&
        lastTime != null &&
        (d.time - lastTime).abs() < 3.0) {
      continue; // 同内容 + 3s 内，跳过
    }
    result.add(d);
    lastContent = d.content;
    lastTime = d.time;
  }
  return result;
}

// ---------- ASS 文本 / 时间格式 ----------

String _escapeAssText(String text) {
  return text
      .replaceAll('\\', '\\\\')
      .replaceAll('{', '\\{')
      .replaceAll('}', '\\}')
      .replaceAll('\n', '\\N')
      .replaceAll('\r', '');
}

String _formatAssTime(double seconds) {
  if (seconds < 0) seconds = 0;
  final totalCs = (seconds * 100).round();
  final cs = totalCs % 100;
  final totalSec = totalCs ~/ 100;
  final s = totalSec % 60;
  final m = (totalSec ~/ 60) % 60;
  final h = totalSec ~/ 3600;
  return '$h:${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
}

void _writeDialogue(
  StringBuffer buffer, {
  required int layer,
  required double start,
  required double end,
  required String style,
  required String text,
}) {
  buffer.writeln(
      'Dialogue: $layer,${_formatAssTime(start)},${_formatAssTime(end)},'
      '$style,,0,0,0,,$text');
}

// ---------- ASS 头 ----------

void _writeHeader(
  StringBuffer buffer,
  double fontSize,
  String fontName,
  (String, String) outline,
  String shadowDepth,
  String backColour, {
  required int playResX,
  required int playResY,
}) {
  buffer.writeln('[Script Info]');
  buffer.writeln('; Generated by NipaPlay external danmaku overlay');
  buffer.writeln('ScriptType: v4.00+');
  buffer.writeln('PlayResX: $playResX');
  buffer.writeln('PlayResY: $playResY');
  buffer.writeln('Aspect Ratio: 16:9');
  buffer.writeln('WrapStyle: 2');
  buffer.writeln('ScaledBorderAndShadow: yes');
  buffer.writeln('YCbCr Matrix: TV.709');
  buffer.writeln();
  buffer.writeln('[V4+ Styles]');
  buffer.writeln(
      'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
      'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, '
      'ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, '
      'Alignment, MarginL, MarginR, MarginV, Encoding');
  // 样式用不透明白色；每条弹幕按需用 \c 覆盖颜色、\1a 覆盖主透明度。
  // 阴影透明度由 BackColour(4a) 承载，不被 \1a 覆盖，保持阴影独立观感。
  const primary = '&H00FFFFFF';
  const outlineColor = '&H00000000';
  final (outlineW, borderStyle) = outline;
  for (final entry in [
    ['Danmaku', '2'],
    ['DanmakuTop', '8'],
    ['DanmakuBottom', '2'],
  ]) {
    final name = entry[0];
    final alignment = entry[1];
    buffer.writeln(
        'Style: $name,$fontName,${fontSize.toStringAsFixed(1)},'
        '$primary,$primary,$outlineColor,$backColour,'
        '0,0,0,0,100,100,0,0,$borderStyle,$outlineW,$shadowDepth,'
        '$alignment,0,0,0,1');
  }
  buffer.writeln();
}

// ============================================================
// 预算条目 → ASS（复用内核布局层如 DFM+ 的计算结果）
// ============================================================

/// 预算好的弹幕条目：车道/碰撞/速度由内核布局层（如 DFM+）预先算好，
/// 本类只承载运动参数，[convertDanmakuToAssFromPrepared] 直接烘焙成 ASS。
class PreparedDanmakuItem {
  final double timeSeconds;
  final String text;
  final int typeCode; // 1=ScrollRL, 6=ScrollLR, 5=top, 4=bottom
  final int colorRgb; // 0xRRGGBB
  final double yPosition; // 顶边 y（ASS 空间）
  final double width; // 文本宽度（ASS 空间）
  final double scrollSpeed; // 像素/秒（参考；\move 实际速度由起止点+时长决定）
  final double durationSeconds;
  final bool isScroll;
  final double centeredX; // 顶/底部弹幕中心 x
  final bool isFiltered; // 内核过滤掉的，跳过

  const PreparedDanmakuItem({
    required this.timeSeconds,
    required this.text,
    required this.typeCode,
    required this.colorRgb,
    required this.yPosition,
    required this.width,
    required this.scrollSpeed,
    required this.durationSeconds,
    required this.isScroll,
    required this.centeredX,
    this.isFiltered = false,
  });
}

/// 用预算好的条目烘焙 ASS。
///
/// 车道分配、碰撞避让、追赶规避由内核布局层（如 DFM+）预先算好，本函数只把
/// 每条的运动参数（yPosition / width / duration / centeredX）烘焙成 ASS
/// `\move` / `\pos`。播放器渲染时即碰撞无关，且不会出现快弹幕追慢弹幕。
///
/// - 滚动：`\an7`(顶左) + `\move(起x, y, 止x, y)`，速度 = (|止-起|)/时长，
///   与内核 scrollSpeed 一致。ScrollRL: 起=PlayResX, 止=-width；
///   ScrollLR(typeCode 6): 起=-width, 止=PlayResX。
/// - 顶/底：`\an8`(顶中) + `\pos(PlayResX/2, yPosition)`。用屏幕中心让 libass
///   按自身字体度量居中，不依赖内核 centeredX（DFM+ paint_width 与 libass 渲染
///   宽度可能不一致，长弹幕会累积偏移）。
String convertDanmakuToAssFromPrepared(
  List<PreparedDanmakuItem> items, {
  required int playResX,
  required int playResY,
  required AssExportSettings settings,
}) {
  final assFontSize = resolveAssFontSize(settings.fontSize);
  final alphaHex = _alphaHexFromOpacity(settings.opacity);
  final styleName = _styleFontName(settings.fontFamily);
  final outline = _resolveOutline(settings.outlineStyle, settings.outlineWidth);
  final (shadowDepth, backColour) = _resolveShadow(settings.shadowStyle);
  final centerX = (playResX / 2).toStringAsFixed(1);

  final buffer = StringBuffer();
  _writeHeader(buffer, assFontSize, styleName, outline, shadowDepth, backColour,
      playResX: playResX, playResY: playResY);

  buffer.writeln('[Events]');
  buffer.writeln(
      'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');
  for (final it in items) {
    if (it.isFiltered) continue;
    if (it.text.isEmpty) continue;
    final start = it.timeSeconds + settings.timeOffsetSeconds;
    if (start < 0) continue;
    final duration = (it.durationSeconds.isFinite && it.durationSeconds > 0)
        ? it.durationSeconds
        : (it.isScroll ? 10.0 : kAssFixedDanmakuDurationSeconds);
    final end = start + duration;
    final colorOverride = _colorOverride(it.colorRgb);
    final outlineOverride = _outlineColorOverride(it.colorRgb);
    final escaped = _escapeAssText(it.text);
    final yStr = it.yPosition.toStringAsFixed(1);

    if (it.isScroll) {
      final String x1;
      final String x2;
      if (it.typeCode == 6) {
        // ScrollLR：左→右
        x1 = (-it.width).toStringAsFixed(1);
        x2 = playResX.toString();
      } else {
        // ScrollRL：右→左
        x1 = playResX.toString();
        x2 = (-it.width).toStringAsFixed(1);
      }
      final line =
          '{\\an7\\move($x1,$yStr,$x2,$yStr)$colorOverride$outlineOverride\\1a$alphaHex}$escaped';
      _writeDialogue(buffer,
          layer: 0, start: start, end: end, style: 'Danmaku', text: line);
    } else {
      final isBottom = DanmakuMode.fromCode(it.typeCode) == DanmakuMode.bottom;
      // 顶/底部居中：用 \an8 顶中对齐 + \pos(PlayResX/2, y)，让 libass 按自身
      // 字体度量居中，避免 DFM+ paint_width 与 libass 渲染宽度不一致导致长弹幕偏移。
      final line =
          '{\\an8\\pos($centerX,$yStr)$colorOverride$outlineOverride\\1a$alphaHex}$escaped';
      _writeDialogue(
        buffer,
        layer: isBottom ? 2 : 1,
        start: start,
        end: end,
        style: isBottom ? 'DanmakuBottom' : 'DanmakuTop',
        text: line,
      );
    }
  }

  return buffer.toString();
}
