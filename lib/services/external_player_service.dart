
// lib/services/external_player_service.dart
// 掌管外部播放器启动, 弹幕导出和参数注入的服务

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/models/external_player_session/linux_session.dart';
import 'package:nipaplay/models/external_player_session/other_session.dart';
import 'package:nipaplay/models/external_player_session/session.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/services/security_bookmark_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/danmaku/assets.dart';
import 'package:nipaplay/utils/danmaku/style.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';
import 'package:nipaplay/utils/external_player_danmaku_ass.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// 外部播放器功能的持久化配置.
///
/// 配置是否真正可用由 [isReady] 判断: 除了启用功能外, 还必须提供非空的
/// 播放器可执行文件路径. 路径是否存在及当前平台是否受支持由启动流程检查.
class ExternalPlayerConfig {
  /// 是否优先使用外部播放器处理播放请求.
  final bool enabled;

  /// 外部播放器的可执行文件, 快捷方式或 macOS 应用包路径.
  final String playerPath;

  /// 创建一份外部播放器配置.
  const ExternalPlayerConfig({
    required this.enabled,
    required this.playerPath,
  });

  /// 配置是否已启用且包含非空的播放器路径.
  bool get isReady => enabled && playerPath.trim().isNotEmpty;
}

/// 项目里掌管协调桌面端外部播放器启动, 播放参数注入和弹幕导出的神.
///
/// 服务支持在 Windows, macOS 和 Linux 上启动外部播放器.
///
/// 1. 从设置中读取播放器配置
/// 2. 选择实际媒体地址
/// 3. 按播放器类型生成命令行参数
/// 4. 在需要时把当前弹幕导出为 ASS 文件
///
/// Linux 上还会为 mpv 创建 IPC socket, 并把已启动进程注册到
/// [ExternalPlayerConsoleService].
///
/// 此服务只负责发起启动, 无法保证外部播放器最终成功解码或播放媒体.
class ExternalPlayerService {

  // 单例访问
  ExternalPlayerService._();
  static final instance = ExternalPlayerService._();

  /// 当前运行平台是否支持由本服务启动外部播放器.
  ///
  /// Web, 移动端以及未显式支持的桌面平台均返回 `false`.
  static bool get isSupportedPlatform => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 从持久化设置中读取外部播放器配置.
  ///
  /// 未保存过的开关和路径分别按 `false` 与空字符串处理. 本方法不校验平台,
  /// 文件是否存在或播放器是否能够执行; 调用方可先使用
  /// [ExternalPlayerConfig.isReady] 做基本检查.
  static Future<ExternalPlayerConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(SettingsKeys.useExternalPlayer) ?? false;
    final path = prefs.getString(SettingsKeys.externalPlayerPath) ?? '';
    return ExternalPlayerConfig(enabled: enabled, playerPath: path);
  }

  /// 解析应交给外部播放器的媒体地址.
  ///
  /// 地址按以下优先级选择:
  ///
  /// 1. [playbackSession] 中非空的流地址;
  /// 2. 非空的 [actualPlayUrl];
  /// 3. 原始 [videoPath].
  ///
  /// 返回值可以是本地文件路径, 也可以是播放器能够访问的网络 URL.
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

  /// 使用 [playerPath] 启动外部播放器打开 [mediaPath], 并附加 [extraArgs].
  ///
  /// 启动前会解析 macOS security bookmark, 并检查播放器路径是否存在.
  /// Windows 快捷方式通过 `cmd /c start` 打开, 普通可执行文件以 detached
  /// 模式启动; macOS 应用包通过 `open -a` 打开; Linux 播放器以 detached
  /// 模式启动. 只有 Linux mpv 会额外启用 JSON IPC 和弹幕控制台能力.
  ///
  /// 成功派生进程时返回对应的 [ExternalPlayerLaunchSession]. 不支持的平台, 空路径,
  /// 文件不存在或进程派生异常均返回 `null`, 且异常不会向调用方抛出. 返回非空
  /// Session 仅表示启动命令执行成功, 不保证播放器已经完成媒体加载.
  static Future<ExternalPlayerLaunchSession?> launch({
    required String playerPath,
    required String mediaPath,
    List<String> extraArgs = const [],
    DanmakuLaunchAssets? danmakuAssets,
    Duration duration = Duration.zero,
    Duration position = Duration.zero,
  }) async {

    debugPrint('[ExtPlayer] launch: playerPath="$playerPath", '
        'mediaPath="$mediaPath", extraArgs=$extraArgs');
    if (!isSupportedPlatform) {
      debugPrint('[ExtPlayer] launch: 平台不支持');
      return null;
    }

    final resolvedPath = await _resolvePlayerPath(playerPath.trim());
    debugPrint('[ExtPlayer] launch: resolvedPath="$resolvedPath"');
    if (resolvedPath == null || resolvedPath.isEmpty) {
      debugPrint('[ExtPlayer] launch: resolvedPath 为空, 中止');
      return null;
    }

    final exists = await FileSystemEntity.type(resolvedPath) !=
        FileSystemEntityType.notFound;
    debugPrint('[ExtPlayer] launch: 文件存在=$exists ($resolvedPath)');
    if (!exists) {
      debugPrint('[ExtPlayer] launch: 外部播放器不存在: $resolvedPath');
      return null;
    }

    try {
      final type = _detectPlayer(resolvedPath);
      if (Platform.isLinux && type == ExternalPlayerType.mpv) {
        return await LinuxSession.launch(
          playerPath: resolvedPath,
          mediaPath: mediaPath,
          extraArgs: extraArgs,
          danmakuAssets: danmakuAssets,
          duration: duration,
          position: position,
        );
      }
      return await _launchOtherSession(
        type: type,
        playerPath: resolvedPath,
        mediaPath: mediaPath,
        extraArgs: extraArgs,
        duration: duration,
        position: position,
      );
    } catch (e, st) {
      debugPrint('[ExtPlayer] launch: 启动异常: $e');
      debugPrintStack(stackTrace: st);
      return null;
    }
  }

  /// 启动 Linux mpv 以外的播放器进程.
  static Future<OtherSession> _launchOtherSession({
    required ExternalPlayerType type,
    required String playerPath,
    required String mediaPath,
    required List<String> extraArgs,
    required Duration duration,
    required Duration position,
  }) async {
    late final Process process;
    var monitorProcess = false;

    if (Platform.isWindows) {
      final isShortcut = playerPath.toLowerCase().endsWith('.lnk');
      process = isShortcut
          ? await Process.start('cmd',['/c', 'start',  '', playerPath, mediaPath, ...extraArgs], runInShell: true)
          : await Process.start(playerPath, [mediaPath, ...extraArgs], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      final isAppBundle = playerPath.toLowerCase().endsWith('.app');
      process = isAppBundle
          ? await Process.start('open', ['-a', playerPath, mediaPath])
          : await Process.start(playerPath, [mediaPath, ...extraArgs]);
    } else {
      process = await Process.start(
        playerPath,
        [mediaPath, ...extraArgs],
        mode: ProcessStartMode.detached,
      );
      monitorProcess = true;
    }

    return OtherSession.attach(
      type: type,
      playerPath: playerPath,
      mediaPath: mediaPath,
      processId: process.pid,
      duration: duration,
      position: position,
      monitorProcess: monitorProcess,
    );
  }

  /// 按当前设置尝试接管 [item] 的播放请求.
  ///
  /// 本方法是外部播放器功能的主要入口. 它从 [context] 读取
  /// [SettingsProvider], 解析媒体地址, 并按设置选择性导出弹幕, 注入字幕,
  /// Lua, 平滑渲染和 User-Agent 参数, 最后启动播放器. Linux 启动成功后还会
  /// 建立供外部播放器控制台使用的会话.
  ///
  /// 返回 `false` 仅表示外部播放器功能未启用, 调用方应继续使用内置播放器.
  /// 一旦功能已启用, 本方法即返回 `true` 表示播放请求已被接管; 平台不支持,
  /// 配置缺失, 弹幕生成失败或播放器启动失败等情况会向用户提示, 而不会回退到
  /// 内置播放器. 弹幕生成失败时仍会尝试无弹幕启动.
  ///
  /// [context] 必须能够读取 [SettingsProvider]; 若需要导出弹幕, 还必须能够读取
  /// [VideoPlayerState]. 异步操作期间会在使用界面前检查 `context.mounted`.
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
      debugPrint('[ExtPlayer] useExternalPlayer=false, 交还内置播放器');
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
      debugPrint('[ExtPlayer] ⚠️ playerPath 是 .lnk 快捷方式. '
          '部分播放器通过快捷方式启动时 --sub-file 等参数可能不会透传到目标 exe. '
          '若弹幕不显示, 请在设置里改选实际的 .exe 路径后再试. ');
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

    // 弹幕外挂: 仅当开关开启且有 episodeId 时尝试（无 ID 的本地文件跳过）
    List<String> extraArgs = const [];
    final danmakuEnabled = settings.externalPlayerDanmakuOverlay;
    DanmakuLaunchAssets? danmakuAssets; // ASS + Lua 脚本产物
    if (danmakuEnabled && episodeId.isNotEmpty) {

      debugPrint('[ExtPlayer] 弹幕外挂开启, 开始准备弹幕…');
      _safeSnack(context, '正在准备弹幕…');

      // 获取弹幕
      final t0 = DateTime.now(); // 计时, 方便调试弹幕生成耗时
      try { danmakuAssets = await _prepareDanmakuAss(context, episodeId, animeId); }
      catch (e, st) {
        debugPrint('[ExtPlayer] _prepareDanmakuAss 顶层异常: $e');
        debugPrintStack(stackTrace: st);
        danmakuAssets = null;
      }

      // 计算弹幕准备耗时
      final dt = DateTime.now().difference(t0).inMilliseconds;
      debugPrint('[ExtPlayer] 弹幕准备完成: '
      'assPath=${danmakuAssets?.assPath}, luaPath=${danmakuAssets?.luaPath}, 耗时=${dt}ms');

      // 若弹幕产物不为空, 则注入 ASS + Lua 脚本参数; 否则提示弹幕加载失败
      if (danmakuAssets != null) {

        // 构建弹幕外挂参数: --sub-file=xxx + --script=xxx + mpv/mpv.net 平滑参数
        extraArgs = _buildSubArgs(playerPath, danmakuAssets);

        // 弹幕平滑参数: 仅原版 mpv（mpv.net 原生弹幕渲染已足够平滑）.
        // blend-subtitles=video 把弹幕混入视频层, 是 vf fps=60 让弹幕
        // 按 60fps 重新定位的前提; 二者配套, 不依赖用户 mpv.conf.
        final smoothArgs = _buildDanmakuSmoothArgs(playerPath);

        // 若平滑参数不为空, 注入到 extraArgs
        if (smoothArgs.isNotEmpty) {
          extraArgs = [...extraArgs, ...smoothArgs];
          debugPrint('[ExtPlayer] 注入弹幕平滑参数: $smoothArgs');
        }
        debugPrint('[ExtPlayer] 注入弹幕参数: extraArgs=$extraArgs, playerType=${_detectPlayer(playerPath)}');

      } else {
        debugPrint('[ExtPlayer] 弹幕为空/失败, 将无弹幕启动');
        if (context.mounted) _safeSnack(context, '弹幕加载失败, 将无弹幕启动');
      }

    } else {
      debugPrint('[ExtPlayer] 跳过弹幕外挂 '
      '(enabled=$danmakuEnabled, episodeId="$episodeId")');
    }

    // 自定义 User-Agent（mpv/mpv.net/vlc 支持; 与弹幕参数合并）
    final uaArgs = _buildUAArgs(playerPath);
    if (uaArgs.isNotEmpty) {
      extraArgs = [...extraArgs, ...uaArgs];
      debugPrint('[ExtPlayer] 注入自定义 UA 参数: $uaArgs');
    }

    debugPrint('[ExtPlayer] 调用 launch: path="$playerPath", media="$mediaPath", extraArgs=$extraArgs');

    // 如有已存在的外部播放器会话, 则先关闭它, 避免新播放器启动失败
    if (Platform.isLinux && ExternalPlayerConsoleService.instance.hasActiveSession) {
      ExternalPlayerConsoleService.closePlayerAndConsole();
    }

    // 启动外部播放器, 并获取启动结果
    final history = item.historyItem;
    final session = await launch(
      playerPath: playerPath,
      mediaPath: mediaPath,
      extraArgs: extraArgs,
      danmakuAssets: danmakuAssets,
      duration: Duration(milliseconds: history?.duration ?? 0),
      position: Duration(milliseconds: history?.lastPosition ?? 0),
    );

    final launched = session != null;
    debugPrint('[ExtPlayer] launch 返回: $launched');

    // Linux 下, 若 mpv 会话启动成功, 则在控制台显示会话信息
    if (session is LinuxSession) {
      final episodeMetaData = EpisodeMetaData(
        animeTitle: history?.animeName ?? item.title,
        episodeTitle: history?.episodeTitle ?? item.subtitle,
        episodeId: item.episodeId,
      );
      final assets = session.danmakuAssets;

      final consoleState = ConsoleState(
        session: session,
        episodeMetaData: episodeMetaData,
        danmakuList: assets?.danmakuList,
        danmakuStyle: assets == null
            ? null
            : DanmakuStyle(
                opacity: assets.opacity,
                outlineWidth: assets.outlineWidth,
                danmakuFontSize: assets.assSettings.fontSize,
                danmakuOffset: assets.assSettings.timeOffsetSeconds,
                danmakuAllowStacking: assets.allowStacking,
              ),
      );
      ExternalPlayerConsoleService.setState(consoleState);

      // 如果设置了启动外部播放器后自动切换到弹幕控制台, 则切换页面
      if (settings.externalPlayerAutoSwitchToDanmakuConsole && context.mounted) {
        Provider.of<TabChangeNotifier>(context, listen: false).changePage(AppPageIds.externalPlayerConsole);
      }
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


  // ===========================================================================
  // =============================== 内部方法 ==================================
  // ===========================================================================


  /// 按 [path] 最后一段文件名推断外部播放器类型.
  ///
  /// 匹配不区分大小写, 并同时接受 `/` 与 `\\` 路径分隔符. mpv.net 会先于
  /// mpv 匹配; 无法识别时返回 [ExternalPlayerType.generic]. 此判断只用于选择
  /// 命令行参数, 不会读取或启动目标文件.
  static ExternalPlayerType _detectPlayer(String path) {
    final lower = path.toLowerCase();
    final base = lower.split(RegExp(r'[\\/]')).last;
    // mpvnet 含 "mpv", 需先判 mpv.net
    if (base.contains('mpvnet') || base.contains('mpv.net')) {
      return ExternalPlayerType.mpvNet;
    }
    if (base.contains('mpv')) return ExternalPlayerType.mpv;
    if (base.contains('potplayer')) return ExternalPlayerType.potPlayer;
    if (base.contains('vlc')) return ExternalPlayerType.vlc;
    return ExternalPlayerType.generic;
  }

  /// 按播放器类型构造弹幕字幕参数.
  ///
  /// mpv / mpv.net: `--sub-file=` 加载弹幕轨 + `--script=` 一个 Lua 脚本把该轨
  /// 设为 `secondary-sid`（次字幕）. mpv.net 6.0.3.2 不支持 `--secondary-sub-file`
  /// CLI 选项, 但 `secondary-sid` 属性经 Lua 可设. 这样弹幕作次字幕始终显示,
  /// 不抢占视频自带的主字幕（内嵌/外挂）.
  ///
  /// 次字幕的 ASS 渲染开关（关键）: 原版 mpv 默认 `secondary-sub-ass-override=strip`
  /// （剥离 ASS 样式 → 纯白文本）, 必须显式设 `no` 才按 ASS 渲染弹幕的 \move/\pos/颜色;
  /// mpv.net 无该选项, 用其自有 `secondary-sub-override`（no = 弹幕模式）.
  static List<String> _buildSubArgs(
      String playerPath, DanmakuLaunchAssets assets) {
    switch (_detectPlayer(playerPath)) {
      case ExternalPlayerType.potPlayer:
        // PotPlayer: /sub=<file>（作为主字幕加载; PotPlayer 双字幕需 GUI 另设）
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
        // vlc / 未知播放器: 仅 --sub-file=（mpv 系也可走这条）
        return ['--sub-file=${assets.assPath}'];
    }
  }

  /// 按播放器类型构造自定义 User-Agent 参数（用户在 PlayerFactory 设置的 UA）.
  /// 空 UA 或不支持的播放器返回空列表. 须在打开媒体前传入, 对所有 HTTP 请求生效.
  static List<String> _buildUAArgs(String playerPath) {
    final ua = PlayerFactory.getCustomPlayerUA();
    if (ua.isEmpty) return const [];
    switch (_detectPlayer(playerPath)) {
      case ExternalPlayerType.mpv:
      case ExternalPlayerType.mpvNet:
        return ['--user-agent=$ua'];
      case ExternalPlayerType.vlc:
        return ['--http-user-agent=$ua'];
      case ExternalPlayerType.potPlayer:
      case ExternalPlayerType.generic:
        // PotPlayer / 未知播放器: CLI 不支持自定义 UA
        return const [];
    }
  }

  /// 按播放器类型构造弹幕平滑参数（仅原版 mpv）.
  ///
  /// 两个配套参数, 缺一不可:
  /// - `--blend-subtitles=video`: 把弹幕混入视频层. 是下面 vf 滤镜让弹幕
  ///   按 60fps 重新定位的前提——若字幕留在 OSD 层, vf 不影响其刷新率.
  ///   通过 CLI 强制设值, 不依赖用户外部 mpv 的 mpv.conf 已配置此项.
  /// - `--vf-add=lavfi=[fps=fps=60:round=down]`: 把视频复制帧到 60fps,
  ///   混入视频层的弹幕随之按 60fps 重新计算 \move 位置 → 滚动清晰不卡顿
  ///   （mpv 字幕刷新率随视频帧率, 24fps 视频下弹幕步进大, 看不清）.
  ///
  /// 仅原版 mpv 需要: mpv.net 原生弹幕渲染已足够平滑, 无需此滤镜.
  /// `--vf-add` 追加而非 `--vf=` 覆盖, 避免冲掉用户 mpv.conf 已有的 vf
  /// 滤镜. PotPlayer/VLC/未知播放器不认这些选项, 跳过.
  static List<String> _buildDanmakuSmoothArgs(String playerPath) {
    switch (_detectPlayer(playerPath)) {
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

  /// 安全显示 snackbar.
  ///
  /// 服务层拿到的 context 可能缺少 Overlay 祖先（如 PlaybackService 传入的
  /// `navigatorKey.currentContext` 是 Navigator 自己的 context, 其 Overlay
  /// 在 Navigator 内部而非祖先）, 此时 [BlurSnackBar.show] 会抛
  /// "No Overlay widget found". 这里吞掉异常, 避免阻断播放器启动主流程——
  /// snackbar 只是提示, 启动逻辑必须继续.
  static void _safeSnack(BuildContext context, String msg) {
    try {
      if (!context.mounted) return;
      BlurSnackBar.show(context, msg);
    } catch (e) {
      debugPrint('[ExtPlayer] snackbar 显示失败(忽略): $e');
    }
  }

  /// 取过滤后弹幕 → 生成 ASS → 写临时文件 + Lua 脚本, 返回产物; 失败返回 null.
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
        debugPrint('[ExtPlayer] 弹幕为空, 跳过 ASS 生成');
        return null;
      }
      final assSettings = _buildAssSettings(vps);
      final danmakuList = List<DanmakuItem>.unmodifiable(
        list.map(DanmakuItem.fromMap),
      );
      debugPrint('[ExtPlayer] ASS 设置: fontSize=${assSettings.fontSize}, '
          'opacity=${assSettings.opacity}, displayArea=${assSettings.displayArea}, '
          'scrollDur=${assSettings.scrollDurationSeconds}, '
          'offset=${assSettings.timeOffsetSeconds}, merge=${assSettings.mergeDuplicates}');
      // 优先用 DFM+ 内核布局层预算运动参数（碰撞/追赶规避）, 失败回退经典算法.
      final ass = await generateExternalPlayerDanmakuAss(
        danmakuList,
        assSettings,
        allowStacking: vps.danmakuStacking,
      );
      debugPrint('[ExtPlayer] ASS 生成完成: ${ass.length} 字符');
      debugPrint('[ExtPlayer] 会话弹幕 ${danmakuList.length} 条');
      final assPath = await _writeAssTempFile(ass, episodeId);
      final assBasename = assPath.split(Platform.pathSeparator).last;
      final luaPath = _writeDanmakuLuaScript(assBasename);
      debugPrint('[ExtPlayer] ASS 已写入临时文件: $assPath '
          '(${File(assPath).lengthSync()} 字节)');
      debugPrint('[ExtPlayer] Lua 脚本已写入: $luaPath');
      debugPrint('[ExtPlayer] ASS 首行: ${ass.split('\n').first}');
      return DanmakuLaunchAssets(
        assPath: assPath,
        luaPath: luaPath,
        opacity: assSettings.opacity,
        outlineWidth: _resolveAssOutlineWidth(assSettings),
        danmakuList: danmakuList,
        assSettings: assSettings,
        allowStacking: vps.danmakuStacking,
      );
    } catch (e, st) {
      debugPrint('[ExtPlayer] _prepareDanmakuAss 异常: $e');
      debugPrintStack(stackTrace: st);
      return null;
    }
  }

  /// 从 [VideoPlayerState] 当前渲染设置构造 ASS 导出设置.
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

  static double _resolveAssOutlineWidth(AssExportSettings settings) {
    switch (settings.outlineStyle) {
      case AssOutlineStyle.none:
        return 0.0;
      case AssOutlineStyle.stroke:
        return settings.outlineWidth.clamp(0.0, 8.0).toDouble();
      case AssOutlineStyle.uniform:
        return (settings.outlineWidth * 1.5).clamp(0.0, 8.0).toDouble();
    }
  }

  /// 写 ASS 到临时目录, 并清理 >1 天的旧文件. 返回绝对路径.
  static Future<String> _writeAssTempFile(String ass, String episodeId) async {
    final dir = await _ensureTempDir();
    _cleanupOldTempFiles(dir);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File(
        '${dir.path}${Platform.pathSeparator}danmaku_${episodeId}_$ts.ass');
    await file.writeAsString(ass, encoding: utf8);
    return file.path;
  }

  /// 写 mpv / mpv.net 用的 Lua 脚本: file-loaded 时把目标弹幕轨设为 secondary-sid.
  ///
  /// mpv.net 6.0.3.2 不支持 `--secondary-sub-file` CLI, 但 `secondary-sid` 属性
  /// 经 Lua `mp.set_property` 可设. 脚本逻辑:
  /// 1. 在 track-list 中按文件名找到 NipaPlay 生成的弹幕轨;
  /// 2. 若该轨被自动选为主字幕(sid), 先把主字幕切到另一条 sub 轨;
  /// 3. 把弹幕轨设为 secondary-sid（次字幕, 始终显示, 不抢占主字幕）.
  /// 若视频除弹幕外没有其它字幕轨, 则弹幕作为主字幕显示, 跳过 secondary 设置.
  static String _writeDanmakuLuaScript(String assBasename) {
    final lua = '''-- NipaPlay 弹幕外挂脚本: 把弹幕字幕轨设为次字幕(secondary-sid)
-- 由 NipaPlay 自动生成; 目标弹幕文件名: $assBasename
-- 不抢占主字幕（内嵌/外挂）, 弹幕作为次字幕始终显示.
local TARGET = "$assBasename"
local function find_danmaku_track()
    local tracks = mp.get_property_native("track-list")
    if not tracks then return nil end
    local did = nil
    for _, t in ipairs(tracks) do
        if t.type == "sub" and t.external and t.title
           and string.find(t.title, TARGET, 1, true) then
            did = t.id
        end
    end
    return did, tracks
end

local function select_danmaku_track()
    local did, tracks = find_danmaku_track()
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
            -- 没有其它字幕轨, 弹幕作为主字幕显示即可
            return
        end
    end
    mp.set_property("secondary-sid", tostring(did))
end

mp.register_event("file-loaded", select_danmaku_track)

local reload_timer = nil

local function restore_primary_track(primary)
    -- sub-reload 会选中重载后的轨道, 但不会同步 sid 选项值.
    -- 先显式取消主字幕, 再恢复原主字幕, 避免相同 sid 被 mpv 当作无变化.
    mp.set_property("sid", "no")
    if primary and primary ~= "no" then
        mp.set_property("sid", primary)
    end
end

local function reload_danmaku_track()
    reload_timer = nil
    local did = find_danmaku_track()
    if not did then return end
    local primary = mp.get_property("sid")
    local was_primary = tonumber(primary) == did
    local was_secondary = tonumber(mp.get_property("secondary-sid")) == did
    mp.commandv("sub-reload", tostring(did))

    mp.add_timeout(0, function()
        local reloaded_did = find_danmaku_track()
        if not reloaded_did then
            restore_primary_track(primary)
            return
        end

        if was_secondary then
            restore_primary_track(primary)
            mp.add_timeout(0, function()
                local current_did = find_danmaku_track()
                if current_did then
                    mp.set_property("secondary-sid", tostring(current_did))
                end
            end)
        elseif was_primary then
            mp.set_property("sid", tostring(reloaded_did))
        else
            restore_primary_track(primary)
        end
    end)
end

mp.register_script_message("nipaplay-danmaku-reload", function(ass_path)
    if ass_path and ass_path ~= "" then
        local ass_name = string.match(ass_path, "([^/\\\\]+)\$")
        if ass_name then TARGET = ass_name end
    end
    if reload_timer then reload_timer:kill() end
    reload_timer = mp.add_timeout(0.05, reload_danmaku_track)
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

  static Future<String?> _resolvePlayerPath(String path) async {
    if (path.isEmpty) return null;
    if (Platform.isMacOS) {
      final resolved = await SecurityBookmarkService.resolveBookmark(path);
      return resolved ?? path;
    }
    return path;
  }

}
