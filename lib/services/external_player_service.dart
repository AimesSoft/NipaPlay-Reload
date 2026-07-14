import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/external_player_session.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/services/security_bookmark_service.dart';
import 'package:nipaplay/src/rust/api/dfm_plus.dart' as rust_dfm;
import 'package:nipaplay/src/rust/rust_init.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/danmaku/style.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';
import 'package:nipaplay/utils/danmaku_xml_utils.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExternalPlayerConfig {
  final bool enabled;
  final String playerPath;

  const ExternalPlayerConfig({
    required this.enabled,
    required this.playerPath,
  });

  bool get isReady => enabled && playerPath.trim().isNotEmpty;
}

/// 外部播放器类型，决定弹幕 ASS 字幕的注入参数。
enum ExternalPlayerType { mpv, mpvNet, potPlayer, vlc, generic }

/// 弹幕外挂启动所需的产物：ASS 字幕文件 + (mpv 系) Lua 脚本。
class DanmakuLaunchAssets {
  final String assPath;
  final String luaPath;

  const DanmakuLaunchAssets({required this.assPath, required this.luaPath});
}

/// Result of spawning an external player.
class ExternalPlayerLaunchResult {
  const ExternalPlayerLaunchResult({
    required this.started,
    this.processId,
    this.ipcPath,
  });

  final bool started;
  final int? processId;
  final String? ipcPath;
}

class ExternalPlayerService {
  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  static Future<ExternalPlayerConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(SettingsKeys.useExternalPlayer) ?? false;
    final path = prefs.getString(SettingsKeys.externalPlayerPath) ?? '';
    return ExternalPlayerConfig(enabled: enabled, playerPath: path);
  }

  static String resolveMediaPath({
    required String videoPath,
    String? actualPlayUrl,
    PlaybackSession? playbackSession,
  }) {
    final sessionUrl = playbackSession?.streamUrl;
    if (sessionUrl != null && sessionUrl.trim().isNotEmpty) {
      return sessionUrl;
    }
    if (actualPlayUrl != null && actualPlayUrl.trim().isNotEmpty) {
      return actualPlayUrl;
    }
    return videoPath;
  }

  /// 按可执行文件名识别外部播放器类型。
  static ExternalPlayerType detectPlayer(String path) {
    final lower = path.toLowerCase();
    final base = lower.split(RegExp(r'[\\/]')).last;
    // mpvnet 含 "mpv"，需先判 mpv.net
    if (base.contains('mpvnet') || base.contains('mpv.net')) {
      return ExternalPlayerType.mpvNet;
    }
    if (base.contains('mpv')) return ExternalPlayerType.mpv;
    if (base.contains('potplayer')) return ExternalPlayerType.potPlayer;
    if (base.contains('vlc')) return ExternalPlayerType.vlc;
    return ExternalPlayerType.generic;
  }

  /// 按播放器类型构造弹幕字幕参数。
  ///
  /// mpv / mpv.net：`--sub-file=` 加载弹幕轨 + `--script=` 一个 Lua 脚本把该轨
  /// 设为 `secondary-sid`（次字幕）。mpv.net 6.0.3.2 不支持 `--secondary-sub-file`
  /// CLI 选项，但 `secondary-sid` 属性经 Lua 可设。这样弹幕作次字幕始终显示，
  /// 不抢占视频自带的主字幕（内嵌/外挂）。
  ///
  /// 次字幕的 ASS 渲染开关（关键）：原版 mpv 默认 `secondary-sub-ass-override=strip`
  /// （剥离 ASS 样式 → 纯白文本），必须显式设 `no` 才按 ASS 渲染弹幕的 \move/\pos/颜色；
  /// mpv.net 无该选项，用其自有 `secondary-sub-override`（no = 弹幕模式）。
  static List<String> _buildSubArgs(
      String playerPath, DanmakuLaunchAssets assets) {
    switch (detectPlayer(playerPath)) {
      case ExternalPlayerType.potPlayer:
        // PotPlayer：/sub=<file>（作为主字幕加载；PotPlayer 双字幕需 GUI 另设）
        return ['/sub=${assets.assPath}'];
      case ExternalPlayerType.mpv:
        return [
          '--sub-file=${assets.assPath}',
          '--script=${assets.luaPath}',
          '--secondary-sub-ass-override=no',
        ];
      case ExternalPlayerType.mpvNet:
        return [
          '--sub-file=${assets.assPath}',
          '--script=${assets.luaPath}',
          '--secondary-sub-override=no',
        ];
      case ExternalPlayerType.vlc:
      case ExternalPlayerType.generic:
        // vlc / 未知播放器：仅 --sub-file=（mpv 系也可走这条）
        return ['--sub-file=${assets.assPath}'];
    }
  }

  /// 按播放器类型构造自定义 User-Agent 参数（用户在 PlayerFactory 设置的 UA）。
  /// 空 UA 或不支持的播放器返回空列表。须在打开媒体前传入，对所有 HTTP 请求生效。
  static List<String> _buildUAArgs(String playerPath) {
    final ua = PlayerFactory.getCustomPlayerUA();
    if (ua.isEmpty) return const [];
    switch (detectPlayer(playerPath)) {
      case ExternalPlayerType.mpv:
      case ExternalPlayerType.mpvNet:
        return ['--user-agent=$ua'];
      case ExternalPlayerType.vlc:
        return ['--http-user-agent=$ua'];
      case ExternalPlayerType.potPlayer:
      case ExternalPlayerType.generic:
        // PotPlayer / 未知播放器：CLI 不支持自定义 UA
        return const [];
    }
  }

  /// 按播放器类型构造弹幕平滑参数（仅原版 mpv）。
  ///
  /// 两个配套参数，缺一不可：
  /// - `--blend-subtitles=video`：把弹幕混入视频层。是下面 vf 滤镜让弹幕
  ///   按 60fps 重新定位的前提——若字幕留在 OSD 层，vf 不影响其刷新率。
  ///   通过 CLI 强制设值，不依赖用户外部 mpv 的 mpv.conf 已配置此项。
  /// - `--vf-add=lavfi=[fps=fps=60:round=down]`：把视频复制帧到 60fps，
  ///   混入视频层的弹幕随之按 60fps 重新计算 \move 位置 → 滚动清晰不卡顿
  ///   （mpv 字幕刷新率随视频帧率，24fps 视频下弹幕步进大、看不清）。
  ///
  /// 仅原版 mpv 需要：mpv.net 原生弹幕渲染已足够平滑，无需此滤镜。
  /// `--vf-add` 追加而非 `--vf=` 覆盖，避免冲掉用户 mpv.conf 已有的 vf
  /// 滤镜。PotPlayer/VLC/未知播放器不认这些选项，跳过。
  static List<String> _buildDanmakuSmoothArgs(String playerPath) {
    switch (detectPlayer(playerPath)) {
      case ExternalPlayerType.mpv:
        return [
          '--blend-subtitles=video',
          '--vf-add=lavfi=[fps=fps=60:round=down]',
        ];
      case ExternalPlayerType.mpvNet:
      case ExternalPlayerType.potPlayer:
      case ExternalPlayerType.vlc:
      case ExternalPlayerType.generic:
        return const [];
    }
  }

  /// 安全显示 snackbar。
  ///
  /// 服务层拿到的 context 可能缺少 Overlay 祖先（如 PlaybackService 传入的
  /// `navigatorKey.currentContext` 是 Navigator 自己的 context，其 Overlay
  /// 在 Navigator 内部而非祖先），此时 [BlurSnackBar.show] 会抛
  /// "No Overlay widget found"。这里吞掉异常，避免阻断播放器启动主流程——
  /// snackbar 只是提示，启动逻辑必须继续。
  static void _safeSnack(BuildContext context, String msg) {
    try {
      if (!context.mounted) return;
      BlurSnackBar.show(context, msg);
    } catch (e) {
      debugPrint('[ExtPlayer] snackbar 显示失败(忽略): $e');
    }
  }

  static Future<bool> tryHandlePlayback(
    BuildContext context,
    PlayableItem item,
  ) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    debugPrint('[ExtPlayer] tryHandlePlayback 触发: '
        'useExternalPlayer=${settings.useExternalPlayer}, '
        'danmakuOverlay=${settings.externalPlayerDanmakuOverlay}, '
        'platformSupported=$isSupportedPlatform, '
        'title=${item.title}');

    if (!settings.useExternalPlayer) {
      debugPrint('[ExtPlayer] useExternalPlayer=false，交还内置播放器');
      return false;
    }

    if (!isSupportedPlatform) {
      debugPrint('[ExtPlayer] 平台不支持外部播放器');
      _safeSnack(context, '外部播放器仅支持桌面端');
      return true;
    }

    final playerPath = settings.externalPlayerPath.trim();
    if (playerPath.isEmpty) {
      debugPrint('[ExtPlayer] externalPlayerPath 为空');
      _safeSnack(context, '请先选择外部播放器');
      return true;
    }
    debugPrint('[ExtPlayer] playerPath="$playerPath"');
    if (playerPath.toLowerCase().endsWith('.lnk')) {
      debugPrint('[ExtPlayer] ⚠️ playerPath 是 .lnk 快捷方式。'
          '部分播放器通过快捷方式启动时 --sub-file 等参数可能不会透传到目标 exe。'
          '若弹幕不显示，请在设置里改选实际的 .exe 路径后再试。');
    }

    final mediaPath = resolveMediaPath(
      videoPath: item.videoPath,
      actualPlayUrl: item.actualPlayUrl,
      playbackSession: item.playbackSession,
    );
    final episodeId = item.episodeId?.toString() ?? '';
    final animeId = item.animeId?.toString() ?? '';
    debugPrint('[ExtPlayer] mediaPath="$mediaPath", '
        'episodeId="$episodeId", animeId="$animeId"');

    // 弹幕外挂：仅当开关开启且有 episodeId 时尝试（无 ID 的本地文件跳过）
    List<String> extraArgs = const [];
    final danmakuEnabled = settings.externalPlayerDanmakuOverlay;
    if (danmakuEnabled && episodeId.isNotEmpty) {
      debugPrint('[ExtPlayer] 弹幕外挂开启，开始准备弹幕…');
      _safeSnack(context, '正在准备弹幕…');
      final t0 = DateTime.now();
      DanmakuLaunchAssets? assets;
      try {
        assets = await _prepareDanmakuAss(context, episodeId, animeId);
      } catch (e, st) {
        debugPrint('[ExtPlayer] _prepareDanmakuAss 顶层异常: $e');
        debugPrintStack(stackTrace: st);
        assets = null;
      }
      final dt = DateTime.now().difference(t0).inMilliseconds;
      debugPrint('[ExtPlayer] 弹幕准备完成: '
          'assPath=${assets?.assPath}, luaPath=${assets?.luaPath}, 耗时=${dt}ms');
      if (assets != null) {
        extraArgs = _buildSubArgs(playerPath, assets);
        // 弹幕平滑参数：仅原版 mpv（mpv.net 原生弹幕渲染已足够平滑）。
        // blend-subtitles=video 把弹幕混入视频层，是 vf fps=60 让弹幕
        // 按 60fps 重新定位的前提；二者配套，不依赖用户 mpv.conf。
        final smoothArgs = _buildDanmakuSmoothArgs(playerPath);
        if (smoothArgs.isNotEmpty) {
          extraArgs = [...extraArgs, ...smoothArgs];
          debugPrint('[ExtPlayer] 注入弹幕平滑参数: $smoothArgs');
        }
        debugPrint('[ExtPlayer] 注入弹幕参数: extraArgs=$extraArgs, '
            'playerType=${detectPlayer(playerPath)}');
      } else {
        debugPrint('[ExtPlayer] 弹幕为空/失败，将无弹幕启动');
        if (context.mounted) _safeSnack(context, '弹幕加载失败，将无弹幕启动');
      }
    } else {
      debugPrint('[ExtPlayer] 跳过弹幕外挂 '
          '(enabled=$danmakuEnabled, episodeId="$episodeId")');
    }

    // 自定义 User-Agent（mpv/mpv.net/vlc 支持；与弹幕参数合并）
    final uaArgs = _buildUAArgs(playerPath);
    if (uaArgs.isNotEmpty) {
      extraArgs = [...extraArgs, ...uaArgs];
      debugPrint('[ExtPlayer] 注入自定义 UA 参数: $uaArgs');
    }

    debugPrint('[ExtPlayer] 调用 launch: path="$playerPath", '
        'media="$mediaPath", extraArgs=$extraArgs');

    if (Platform.isLinux &&
        ExternalPlayerConsoleService.instance.hasActiveSession) {
      ExternalPlayerConsoleService.instance.closePlayerAndConsole();
    }

    final launchResult = await launchWithResult(
      playerPath: playerPath,
      mediaPath: mediaPath,
      extraArgs: extraArgs,
    );
    final launched = launchResult.started;
    debugPrint('[ExtPlayer] launch 返回: $launched');

    if (launched && Platform.isLinux && launchResult.processId != null) {
      final history = item.historyItem;
      ExternalPlayerConsoleService.instance.showSession(
        ExternalPlayerSession(
          playerPath: playerPath,
          mediaPath: mediaPath,
          processId: launchResult.processId!,
          animeTitle: history?.animeName ?? item.title,
          episodeTitle: history?.episodeTitle ?? item.subtitle,
          episodeId: item.episodeId,
          ipcPath: launchResult.ipcPath,
        ),
      );
    }

    if (context.mounted) {
      _safeSnack(
        context,
        launched
            ? (extraArgs.isEmpty ? '已通过外部播放器打开' : '已通过外部播放器打开(含弹幕)')
            : '外部播放器启动失败',
      );
    }

    return true;
  }

  /// 取过滤后弹幕 → 生成 ASS → 写临时文件 + Lua 脚本，返回产物；失败返回 null。
  static Future<DanmakuLaunchAssets?> _prepareDanmakuAss(
    BuildContext context,
    String episodeId,
    String animeId,
  ) async {
    debugPrint(
        '[ExtPlayer] _prepareDanmakuAss: episodeId=$episodeId, animeId=$animeId');
    try {
      final vps = Provider.of<VideoPlayerState>(context, listen: false);
      final list = await vps.buildFilteredDanmakuForExport(
        episodeId: episodeId,
        animeId: animeId,
      );
      debugPrint('[ExtPlayer] 过滤后弹幕 ${list.length} 条');
      if (list.isEmpty) {
        debugPrint('[ExtPlayer] 弹幕为空，跳过 ASS 生成');
        return null;
      }
      final assSettings = _buildAssSettings(vps);
      debugPrint('[ExtPlayer] ASS 设置: fontSize=${assSettings.fontSize}, '
          'opacity=${assSettings.opacity}, displayArea=${assSettings.displayArea}, '
          'scrollDur=${assSettings.scrollDurationSeconds}, '
          'offset=${assSettings.timeOffsetSeconds}, merge=${assSettings.mergeDuplicates}');
      // 优先用 DFM+ 内核布局层预算运动参数（碰撞/追赶规避），失败回退经典算法。
      String ass;
      String assPathLabel;
      final dfmAss = await _generateAssViaDfmLayout(list, assSettings, vps);
      if (dfmAss != null) {
        ass = dfmAss;
        assPathLabel = 'DFM+布局';
      } else {
        ass = convertDanmakuToAss(list, assSettings);
        assPathLabel = '经典算法';
      }
      debugPrint('[ExtPlayer] ASS 生成完成 ($assPathLabel): ${ass.length} 字符');
      final assPath = await _writeAssTempFile(ass, episodeId);
      final assBasename = assPath.split(Platform.pathSeparator).last;
      final luaPath = _writeDanmakuLuaScript(assBasename);
      debugPrint('[ExtPlayer] ASS 已写入临时文件: $assPath '
          '(${File(assPath).lengthSync()} 字节)');
      debugPrint('[ExtPlayer] Lua 脚本已写入: $luaPath');
      debugPrint('[ExtPlayer] ASS 首行: ${ass.split('\n').first}');
      return DanmakuLaunchAssets(assPath: assPath, luaPath: luaPath);
    } catch (e, st) {
      debugPrint('[ExtPlayer] _prepareDanmakuAss 异常: $e');
      debugPrintStack(stackTrace: st);
      return null;
    }
  }

  /// 用 DFM+ 内核布局层预算运动参数后烘焙 ASS。
  ///
  /// DFM+ 的 [rust_dfm.dfmPlusPrepareLayoutFull] 一次性算好全部条目的车道
  /// (yPosition)、滚动速度(scrollSpeed)、宽度(width)、时长(durationSeconds)、
  /// 居中 x(centeredX)，已做碰撞避让与追赶规避。本方法把这些参数适配为
  /// [PreparedDanmakuItem] 交给 [convertDanmakuToAssFromPrepared] 烘焙，
  /// ASS 渲染时即碰撞无关。失败返回 null（调用方回退经典算法）。
  static Future<String?> _generateAssViaDfmLayout(
    List<Map<String, dynamic>> list,
    AssExportSettings settings,
    VideoPlayerState vps,
  ) async {
    try {
      final rawItems = <rust_dfm.DfmPlusRawDanmakuItem>[];
      for (final raw in list) {
        final text = (raw['content'] ?? raw['c'])?.toString() ?? '';
        if (text.isEmpty) continue;
        final time = _resolveDanmakuTime(raw);
        final typeCode = _resolveDanmakuTypeCode(raw);
        final colorArgb =
            _toArgbSigned(parseDanmakuColorToInt(raw['color'] ?? raw['r']));
        rawItems.add(rust_dfm.DfmPlusRawDanmakuItem(
          timeSeconds: time,
          text: text,
          typeCode: typeCode,
          colorArgb: colorArgb,
          isMe: raw['isMe'] == true,
        ));
      }
      if (rawItems.isEmpty) return null;

      await ensureRustInitialized();
      final mappedFont = resolveAssFontSize(settings.fontSize);
      final prepared = await rust_dfm.dfmPlusPrepareLayoutFull(
        rawItems: rawItems,
        width: kAssPlayResX.toDouble(),
        height: kAssPlayResY.toDouble(),
        fontSize: mappedFont,
        displayArea: settings.displayArea,
        scrollDurationSeconds: settings.scrollDurationSeconds,
        allowStacking: vps.danmakuStacking,
        mergeDanmaku: settings.mergeDuplicates,
        trackGapRatio: 0.15,
        outlineWidth: settings.outlineWidth,
        customFontBytes: null,
        blockWords: const [],
      );

      final items = prepared.items
          .map((pi) => PreparedDanmakuItem(
                timeSeconds: pi.timeSeconds,
                text: pi.text,
                typeCode: pi.typeCode,
                colorRgb: pi.colorArgb & 0xFFFFFF,
                yPosition: pi.yPosition,
                width: pi.width,
                scrollSpeed: pi.scrollSpeed,
                durationSeconds: pi.durationSeconds,
                isScroll: pi.isScroll,
                centeredX: pi.centeredX,
                isFiltered: pi.isFiltered,
              ))
          .toList();
      final kept = items.where((i) => !i.isFiltered).length;
      debugPrint('[ExtPlayer] DFM+ 布局: 共 ${items.length} 条, 入 ASS $kept 条');

      final ass = convertDanmakuToAssFromPrepared(
        items,
        playResX: kAssPlayResX,
        playResY: kAssPlayResY,
        settings: settings,
      );
      rust_dfm.dfmPlusDropLayout(handle: prepared.handle);
      return ass;
    } catch (e, st) {
      debugPrint('[ExtPlayer] DFM+ 布局路径失败，将回退经典算法: $e');
      debugPrintStack(stackTrace: st);
      return null;
    }
  }

  static double _resolveDanmakuTime(Map<String, dynamic> item) {
    final v = item['time'] ?? item['t'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static int _resolveDanmakuTypeCode(Map<String, dynamic> item) {
    final original = item['originalType'];
    if (original is num) return original.toInt();
    final v = item['type'] ?? item['y'];
    if (v is num) return v.toInt();
    switch (v?.toString().toLowerCase()) {
      case 'top':
        return 5;
      case 'bottom':
        return 4;
      default:
        return 1;
    }
  }

  /// 0xRRGGBB → ARGB signed int (0xFFRRGGBB as i32)，DFM+ 要求 colorArgb 为 i32。
  static int _toArgbSigned(int rgb) {
    return (0xFF000000 | (rgb & 0xFFFFFF)).toSigned(32);
  }

  /// 从 [VideoPlayerState] 当前渲染设置构造 ASS 导出设置。
  static AssExportSettings _buildAssSettings(VideoPlayerState vps) {
    return AssExportSettings(
      fontSize: vps.actualDanmakuFontSize,
      opacity: vps.danmakuOpacity,
      displayArea: vps.danmakuDisplayArea,
      scrollDurationSeconds: vps.danmakuScrollDurationSeconds,
      timeOffsetSeconds: vps.manualDanmakuOffset + vps.autoDanmakuOffset,
      mergeDuplicates: vps.mergeDanmaku,
      fontFamily: vps.danmakuFontFamily,
      outlineStyle: _mapOutlineStyle(vps.danmakuOutlineStyle),
      outlineWidth: vps.next2DanmakuOutlineWidth,
      shadowStyle: _mapShadowStyle(vps.danmakuShadowStyle),
    );
  }

  static AssShadowStyle _mapShadowStyle(DanmakuShadowStyle style) {
    switch (style) {
      case DanmakuShadowStyle.none:
        return AssShadowStyle.none;
      case DanmakuShadowStyle.soft:
        return AssShadowStyle.soft;
      case DanmakuShadowStyle.medium:
        return AssShadowStyle.medium;
      case DanmakuShadowStyle.strong:
        return AssShadowStyle.strong;
    }
  }

  static AssOutlineStyle _mapOutlineStyle(DanmakuOutlineStyle style) {
    switch (style) {
      case DanmakuOutlineStyle.none:
        return AssOutlineStyle.none;
      case DanmakuOutlineStyle.stroke:
        return AssOutlineStyle.stroke;
      case DanmakuOutlineStyle.uniform:
        return AssOutlineStyle.uniform;
    }
  }

  /// 写 ASS 到临时目录，并清理 >1 天的旧文件。返回绝对路径。
  static Future<String> _writeAssTempFile(String ass, String episodeId) async {
    final dir = await _ensureTempDir();
    _cleanupOldTempFiles(dir);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File(
        '${dir.path}${Platform.pathSeparator}danmaku_${episodeId}_$ts.ass');
    await file.writeAsString(ass, encoding: utf8);
    return file.path;
  }

  /// 写 mpv / mpv.net 用的 Lua 脚本：file-loaded 时把目标弹幕轨设为 secondary-sid。
  ///
  /// mpv.net 6.0.3.2 不支持 `--secondary-sub-file` CLI，但 `secondary-sid` 属性
  /// 经 Lua `mp.set_property` 可设。脚本逻辑：
  /// 1. 在 track-list 中按文件名找到 NipaPlay 生成的弹幕轨；
  /// 2. 若该轨被自动选为主字幕(sid)，先把主字幕切到另一条 sub 轨；
  /// 3. 把弹幕轨设为 secondary-sid（次字幕，始终显示，不抢占主字幕）。
  /// 若视频除弹幕外没有其它字幕轨，则弹幕作为主字幕显示，跳过 secondary 设置。
  static String _writeDanmakuLuaScript(String assBasename) {
    final lua = '''-- NipaPlay 弹幕外挂脚本：把弹幕字幕轨设为次字幕(secondary-sid)
-- 由 NipaPlay 自动生成；目标弹幕文件名: $assBasename
-- 不抢占主字幕（内嵌/外挂），弹幕作为次字幕始终显示。
local TARGET = "$assBasename"
mp.register_event("file-loaded", function()
    local tracks = mp.get_property_native("track-list")
    if not tracks then return end
    local did = nil
    for _, t in ipairs(tracks) do
        if t.type == "sub" and t.external and t.title
           and string.find(t.title, TARGET, 1, true) then
            did = t.id
        end
    end
    if not did then return end
    local cur = mp.get_property("sid")
    if cur and tonumber(cur) == did then
        local switched = false
        for _, t in ipairs(tracks) do
            if t.type == "sub" and t.id ~= did then
                mp.set_property("sid", tostring(t.id))
                switched = true
                break
            end
        end
        if not switched then
            -- 没有其它字幕轨，弹幕作为主字幕显示即可
            return
        end
    end
    mp.set_property("secondary-sid", tostring(did))
end)
''';
    final dir = _ensureTempDirSync();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file =
        File('${dir.path}${Platform.pathSeparator}nipaplay_danmaku_$ts.lua');
    file.writeAsStringSync(lua, encoding: utf8);
    return file.path;
  }

  static Future<Directory> _ensureTempDir() async {
    final dir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}nipaplay_danmaku');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      debugPrint('[ExtPlayer] 创建临时目录: ${dir.path}');
    }
    return dir;
  }

  static Directory _ensureTempDirSync() {
    final dir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}nipaplay_danmaku');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static void _cleanupOldTempFiles(Directory dir) {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      for (final ent in dir.listSync()) {
        if (ent is File) {
          final lower = ent.path.toLowerCase();
          if (lower.endsWith('.ass') || lower.endsWith('.lua')) {
            if (ent.statSync().modified.isBefore(cutoff)) {
              ent.deleteSync();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ExtPlayer] 清理旧临时文件失败: $e');
    }
  }

  static Future<bool> launch({
    required String playerPath,
    required String mediaPath,
    List<String> extraArgs = const [],
  }) async {
    final result = await launchWithResult(
      playerPath: playerPath,
      mediaPath: mediaPath,
      extraArgs: extraArgs,
    );
    return result.started;
  }

  static Future<ExternalPlayerLaunchResult> launchWithResult({
    required String playerPath,
    required String mediaPath,
    List<String> extraArgs = const [],
  }) async {
    debugPrint('[ExtPlayer] launch: playerPath="$playerPath", '
        'mediaPath="$mediaPath", extraArgs=$extraArgs');
    if (!isSupportedPlatform) {
      debugPrint('[ExtPlayer] launch: 平台不支持');
      return const ExternalPlayerLaunchResult(started: false);
    }

    final resolvedPath = await _resolvePlayerPath(playerPath.trim());
    debugPrint('[ExtPlayer] launch: resolvedPath="$resolvedPath"');
    if (resolvedPath == null || resolvedPath.isEmpty) {
      debugPrint('[ExtPlayer] launch: resolvedPath 为空，中止');
      return const ExternalPlayerLaunchResult(started: false);
    }

    final exists = await FileSystemEntity.type(resolvedPath) !=
        FileSystemEntityType.notFound;
    debugPrint('[ExtPlayer] launch: 文件存在=$exists ($resolvedPath)');
    if (!exists) {
      debugPrint('[ExtPlayer] launch: 外部播放器不存在: $resolvedPath');
      return const ExternalPlayerLaunchResult(started: false);
    }

    try {
      if (Platform.isWindows) {
        final isLnk = resolvedPath.toLowerCase().endsWith('.lnk');
        if (isLnk) {
          // .lnk 快捷方式：cmd /c start 解析快捷方式目标并自动分离。
          final args = <String>[
            '/c',
            'start',
            '',
            resolvedPath,
            mediaPath,
            ...extraArgs,
          ];
          debugPrint('[ExtPlayer] launch: .lnk → '
              'Process.start("cmd", $args, runInShell:true)');
          final proc = await Process.start('cmd', args, runInShell: true);
          debugPrint('[ExtPlayer] launch: cmd 已派生 pid=${proc.pid}');
        } else {
          // .exe：直启，参数由 Dart 直接传递（绕过 cmd/start 的引号 quirks，
          // 对带空格/特殊字符的媒体路径和 --sub-file=xxx / --script=xxx 参数最可靠）。
          final args = <String>[mediaPath, ...extraArgs];
          debugPrint('[ExtPlayer] launch: .exe → '
              'Process.start("$resolvedPath", $args, mode:detached)');
          final proc = await Process.start(
            resolvedPath,
            args,
            mode: ProcessStartMode.detached,
          );
          debugPrint('[ExtPlayer] launch: 已派生 pid=${proc.pid}');
        }
        return const ExternalPlayerLaunchResult(started: true);
      }

      if (Platform.isMacOS) {
        if (resolvedPath.toLowerCase().endsWith('.app')) {
          debugPrint('[ExtPlayer] launch: macOS open -a "$resolvedPath"');
          await Process.start('open', ['-a', resolvedPath, mediaPath]);
        } else {
          debugPrint('[ExtPlayer] launch: macOS 直启 + extraArgs=$extraArgs');
          await Process.start(resolvedPath, [mediaPath, ...extraArgs]);
        }
        return const ExternalPlayerLaunchResult(started: true);
      }

      // Linux
      String? ipcPath;
      var linuxExtraArgs = extraArgs;
      if (detectPlayer(resolvedPath) == ExternalPlayerType.mpv) {
        ipcPath = _createMpvIpcPath();
        linuxExtraArgs = [...extraArgs, '--input-ipc-server=$ipcPath'];
        debugPrint('[ExtPlayer] 已启用 mpv JSON IPC: $ipcPath');
      }
      debugPrint(
        '[ExtPlayer] launch: Linux 直启 + '
        'extraArgs=$linuxExtraArgs, mode=detached',
      );

      final proc = await Process.start(
        resolvedPath,
        [mediaPath, ...linuxExtraArgs],
        mode: ProcessStartMode.detached,
      );

      // 打印派生进程 PID，方便调试
      debugPrint('[ExtPlayer] launch: 已派生 pid=${proc.pid}');

      return ExternalPlayerLaunchResult(
        started: true,
        processId: proc.pid,
        ipcPath: ipcPath,
      );
    } catch (e, st) {
      debugPrint('[ExtPlayer] launch: 启动异常: $e');
      debugPrintStack(stackTrace: st);
      return const ExternalPlayerLaunchResult(started: false);
    }
  }

  static String _createMpvIpcPath() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'nipaplay_mpv_${pid}_$timestamp.sock';
  }

  static Future<String?> _resolvePlayerPath(String path) async {
    if (path.isEmpty) {
      return null;
    }
    if (Platform.isMacOS) {
      final resolved = await SecurityBookmarkService.resolveBookmark(path);
      return resolved ?? path;
    }
    return path;
  }
}
