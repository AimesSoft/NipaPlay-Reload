// lib/utils/external_player_danmaku_ass.dart
// 为外部 mpv 生成弹幕 ASS

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/danmaku/ass_danmaku.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/src/rust/api/dfm_plus.dart' as rust_dfm;
import 'package:nipaplay/src/rust/rust_init.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';


/// 基于会话保存的强类型弹幕生成 mpv 使用的 ASS.
///
/// 优先复用 DFM+ 布局能力; 初始化或布局失败时回退到经典 ASS 算法.
Future<DanmakuAssConversionResult> generateExternalPlayerDanmakuAss(
  List<DanmakuItem> danmakuList,
  AssExportSettings settings, {
  required bool allowStacking,
}) async {
  final dfmConversion = await _generateAssViaDfmLayout(
    danmakuList,
    settings,
    allowStacking: allowStacking,
  );
  if (dfmConversion != null) return dfmConversion;
  return convertDanmakuItemsToAssWithEvents(danmakuList, settings);
}

Future<DanmakuAssConversionResult?> _generateAssViaDfmLayout(
  List<DanmakuItem> danmakuList,
  AssExportSettings settings, {
  required bool allowStacking,
}) async {
  rust_dfm.DfmPlusPreparedLayout? prepared;
  try {
    final rawItems = <rust_dfm.DfmPlusRawDanmakuItem>[];
    for (final item in danmakuList) {
      if (item.content.isEmpty) continue;
      rawItems.add(rust_dfm.DfmPlusRawDanmakuItem(
        timeSeconds: item.timeSeconds,
        text: item.content,
        typeCode: item.mode.code,
        colorArgb: _toArgbSigned(item.colorRgb),
        isMe: item.isMe,
      ));
    }
    if (rawItems.isEmpty) return null;

    await ensureRustInitialized();
    final mappedFont = resolveAssFontSize(settings.fontSize);
    prepared = await rust_dfm.dfmPlusPrepareLayoutFull(
      rawItems: rawItems,
      width: kAssPlayResX.toDouble(),
      height: kAssPlayResY.toDouble(),
      fontSize: mappedFont,
      displayArea: settings.displayArea,
      scrollDurationSeconds: settings.scrollDurationSeconds,
      allowStacking: allowStacking,
      mergeDanmaku: settings.mergeDuplicates,
      trackGapRatio: 0.15,
      outlineWidth: settings.outlineWidth,
      customFontBytes: null,
      blockWords: const [],
    );

    final items = prepared.items
        .map((item) => PreparedDanmakuItem(
              timeSeconds: item.timeSeconds,
              text: item.text,
              typeCode: item.typeCode,
              colorRgb: item.colorArgb & 0xFFFFFF,
              yPosition: item.yPosition,
              width: item.width,
              scrollSpeed: item.scrollSpeed,
              durationSeconds: item.durationSeconds,
              isScroll: item.isScroll,
              centeredX: item.centeredX,
              isFiltered: item.isFiltered,
            ))
        .toList();
    final kept = items.where((item) => !item.isFiltered).length;
    debugPrint('[ExtPlayer] DFM+ 布局: 共 ${items.length} 条, 入 ASS $kept 条');

    return convertDanmakuToAssFromPreparedWithEvents(
      items,
      playResX: kAssPlayResX,
      playResY: kAssPlayResY,
      settings: settings,
    );
  } catch (error, stackTrace) {
    debugPrint('[ExtPlayer] DFM+ 布局路径失败, 将回退经典算法: $error');
    debugPrintStack(stackTrace: stackTrace);
    return null;
  } finally {
    if (prepared != null) {
      try {
        await rust_dfm.dfmPlusDropLayout(handle: prepared.handle);
      } catch (error) {
        debugPrint('[ExtPlayer] 释放 DFM+ ASS 布局失败: $error');
      }
    }
  }
}

int _toArgbSigned(int rgb) {
  return (0xFF000000 | (rgb & 0xFFFFFF)).toSigned(32);
}
