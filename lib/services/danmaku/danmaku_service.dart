
// lib/services/danmaku/danmaku_service.dart
// 处理弹幕相关的服务, 包括弹幕的加载, 保存, 导出等功能.

import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/utils/danmaku/style.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';
import 'package:nipaplay/utils/external_player_danmaku_ass.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';


/// 单例类, 提供弹幕相关的服务.
class DanmakuService {

  // 单例模式
  DanmakuService._();
  static final DanmakuService _ins = DanmakuService._();
  static DanmakuService get instance => _ins;


  /// 获取用户当前弹幕设置
  static DanmakuStyle getCurrentDanmakuStyle() {

    DanmakuStyle danmakuStyle = DanmakuStyle();
    final context = globals.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      try {
        final videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
        danmakuStyle.opacity = videoPlayerState.danmakuOpacity;
        danmakuStyle.outlineWidth = videoPlayerState.next2DanmakuOutlineWidth;
        danmakuStyle.danmakuFontSize = videoPlayerState.actualDanmakuFontSize;
        danmakuStyle.danmakuOffset = videoPlayerState.manualDanmakuOffset + videoPlayerState.autoDanmakuOffset;
        danmakuStyle.danmakuAllowStacking = videoPlayerState.danmakuStacking;
      }
      catch (_) {}
    }
    return danmakuStyle;
  }


  /// 通过弹弹play剧集 ID 获取弹幕.
  ///
  /// 获取失败时返回 `null`; 请求成功但该剧集没有弹幕时返回空集合.
  static Future<Set<DanmakuItem>?> getDanmakuFromEpisodeId(int episodeId) async {

    // 参数检查
    if (episodeId <= 0) return null;

    try {
      final result = await DandanplayService.getDanmaku(episodeId.toString(), 0);
      final comments = result['comments'];

      // 如果返回的 comments 不是 List, 则说明该剧集没有弹幕, 返回空集合.
      if (comments is! List) return <DanmakuItem>{};

      // 将返回的弹幕数据转换为 DanmakuItem 对象集合
      final res =  comments.whereType<Map>().map((comment) => DanmakuItem.fromMap(comment)).toSet();
      return res;
    }
    catch (_) { return null; }
  }

  static Future<DanmakuItemSet?> getFilteredDanmakuFromEpisodeIdAndAnimeId(int episodeId, int animeId) async {

    if (episodeId <= 0) return null;

    final context = globals.navigatorKey.currentContext;
    if (context == null) return null;

    try {
      final vps = Provider.of<VideoPlayerState>(context, listen: false);
      final filtered = await vps.buildFilteredDanmakuForExport(
        episodeId: episodeId.toString(),
        animeId: animeId.toString(),
      );
      return filtered.map(DanmakuItem.fromMap).toSet();
    } catch (_) {
      return null;
    }
  }

  /// 将强类型弹幕转换为 ASS 字幕文本.
  ///
  /// 优先使用 DFM+ 布局生成轨道与运动参数; 布局不可用时由
  /// [generateExternalPlayerDanmakuAss] 回退到经典 ASS 转换器.
  static Future<String> getDanmakuAssStringFromDanmakuItemSet(Set<DanmakuItem> danmakuItemSet) async {

    final context = globals.navigatorKey.currentContext;
    if (context == null) {
      throw Exception("DanmakuService: Navigator context is null, cannot generate ASS.");
    }
    final vps = Provider.of<VideoPlayerState>(context, listen: false);

    // 从 [VideoPlayerState] 当前渲染设置构造 ASS 导出设置.
    final assSettings = AssExportSettings(
      fontSize: vps.actualDanmakuFontSize,
      opacity: vps.danmakuOpacity,
      displayArea: vps.danmakuDisplayArea,
      scrollDurationSeconds: vps.danmakuScrollDurationSeconds,
      timeOffsetSeconds: vps.manualDanmakuOffset + vps.autoDanmakuOffset,
      mergeDuplicates: vps.mergeDanmaku,
      allowStacking: vps.danmakuStacking,
      fontFamily: vps.danmakuFontFamily,
      outlineStyle: switch (vps.danmakuOutlineStyle) {
        DanmakuOutlineStyle.none => AssOutlineStyle.none,
        DanmakuOutlineStyle.stroke => AssOutlineStyle.stroke,
        DanmakuOutlineStyle.uniform => AssOutlineStyle.uniform,
      },
      outlineWidth: vps.next2DanmakuOutlineWidth,
      shadowStyle: switch (vps.danmakuShadowStyle) {
        DanmakuShadowStyle.none => AssShadowStyle.none,
        DanmakuShadowStyle.soft => AssShadowStyle.soft,
        DanmakuShadowStyle.medium => AssShadowStyle.medium,
        DanmakuShadowStyle.strong => AssShadowStyle.strong,
      },
    );

    return generateExternalPlayerDanmakuAss(danmakuItemSet.toList(growable: false), assSettings);
  }
}
