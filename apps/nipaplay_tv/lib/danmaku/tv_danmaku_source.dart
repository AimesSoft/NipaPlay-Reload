import 'package:nipaplay_core/constants/danmaku/mode.dart';
import 'package:nipaplay_core/models/danmaku/danmaku_item.dart';
import 'package:nipaplay_core/utils/danmaku_xml_utils.dart';

/// 解析结果：core 的 [parseBilibiliXmlDanmakuComments] 输出 → [DanmakuItem]。
///
/// core 负责协议解析（XML 字段、模式码、颜色编码），TV 版只做展示侧装配。
class TvDanmakuSource {
  const TvDanmakuSource._();

  static List<DanmakuItem> parseBilibiliXml(String xmlContent) {
    final raw = parseBilibiliXmlDanmakuComments(xmlContent);
    final items = <DanmakuItem>[];
    for (final entry in raw) {
      final seconds = (entry['t'] as num?)?.toDouble() ?? 0;
      final content = (entry['c'] as String?) ?? '';
      if (content.isEmpty) continue;
      final colorRgb = _rgbFromCss(entry['r'] as String?);
      items.add(DanmakuItem(
        time: Duration(milliseconds: (seconds * 1000).round()),
        content: content,
        mode: DanmakuMode.fromTypeName(entry['y'] as String?),
        colorRgb: colorRgb,
        senderId: (entry['senderId'] as String?)?.isEmpty ?? true
            ? null
            : entry['senderId'] as String,
      ));
    }
    items.sort((a, b) => a.time.compareTo(b.time));
    return items;
  }

  /// core 输出 `rgb(r,g,b)` 形式的颜色字符串，转成 24 位 RGB。
  static int _rgbFromCss(String? css) {
    if (css == null) return 0xFFFFFF;
    final match = RegExp(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)').firstMatch(css);
    if (match == null) return 0xFFFFFF;
    final r = int.parse(match.group(1)!);
    final g = int.parse(match.group(2)!);
    final b = int.parse(match.group(3)!);
    return ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
  }
}
