import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nipaplay/pages/tab_labels.dart';
import 'package:nipaplay/utils/app_theme.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/utils/system_resource_monitor.dart';
import 'package:nipaplay/themes/nipaplay/widgets/custom_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/menu_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/system_resource_display.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'pages/anime_page.dart';
import 'themes/nipaplay/pages/settings_page.dart';
import 'pages/play_video_page.dart';
import 'pages/new_series_page.dart';
import 'pages/dashboard_home_page.dart';
import 'themes/cupertino/pages/cupertino_main_page.dart';
import 'utils/settings_storage.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'services/bangumi_service.dart';
import 'services/dandanplay_service.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'models/watch_history_model.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/services/auto_sync_service.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/themes/theme_descriptor.dart';
import 'themes/nipaplay/pages/settings/account_page.dart';
import 'dart:async';
import 'services/file_picker_service.dart';
import 'services/security_bookmark_service.dart';
import 'themes/nipaplay/widgets/blur_snackbar.dart';

import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/file_association_service.dart';
import 'package:nipaplay/services/single_instance_service.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/themes/nipaplay/widgets/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:nipaplay/themes/nipaplay/widgets/drag_drop_overlay.dart';
import 'providers/service_provider.dart';
import 'utils/platform_utils.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'services/hotkey_service_initializer.dart';
import 'utils/shortcut_tooltip_manager.dart';
import 'utils/hotkey_service.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/services/http_client_initializer.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/models/anime_detail_display_mode.dart';
import 'package:nipaplay/models/background_image_render_mode.dart';
import 'constants/settings_keys.dart';
import 'player_abstraction/media_kit_player_adapter.dart';
import 'utils/launch_file_handler.dart';
import 'package:nipaplay/services/desktop_exit_handler_stub.dart'
    if (dart.library.io) 'package:nipaplay/services/desktop_exit_handler.dart';

final GlobalKey<NavigatorState> navigatorKey = globals.navigatorKey;
// 将通道定义为全局变量
const MethodChannel menuChannel = MethodChannel('custom_menu_channel');

final GlobalKey<State<DefaultTabController>> tabControllerKey =
    GlobalKey<State<DefaultTabController>>();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPaintBaselinesEnabled = false;
  debugPaintSizeEnabled = false;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPaintBaselinesEnabled = false;
    debugPaintSizeEnabled = false;
  });

  // Web 端不再提供 UI，仅保留客户端连接的远程访问 API。
  if (kIsWeb) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Text(
            'Web UI 已移除，请使用客户端连接远程访问服务。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ));
    return;
  }

  String? launchFilePath;
  if (globals.isDesktop && args.isNotEmpty) {
    final filePath = args.first;
    if (await File(filePath).exists()) {
      launchFilePath = filePath;
    }
  }

  if (globals.isDesktop) {
    final isPrimary = await SingleInstanceService.ensureSingleInstance(
      launchFilePath: launchFilePath,
    );
    if (!isPrimary) {
      return;
    }
  }

  WatchHistoryDatabase.ensureInitialized();

  // 安装 HTTP 客户端覆盖（自签名证书信任规则），尽早生效
  await HttpClientInitializer.install();

  // 初始化hotkey_manager
  if (globals.isDesktop) {
    await hotKeyManager.unregisterAll();
  }

  // 初始化调试日志服务（在最前面初始化，这样可以收集启动过程的日志）
  final debugLogService = DebugLogService();
  debugLogService.initialize();

  if (launchFilePath != null) {
    debugLogService.addLog('应用启动时收到命令行文件路径: $launchFilePath',
        level: 'INFO', tag: 'FileAssociation');
  }

  // Android平台通过Intent传入
  if (!kIsWeb && Platform.isAndroid) {
    final intentFilePath = await FileAssociationService.getOpenFileUri();
    if (intentFilePath != null &&
        await FileAssociationService.validateFilePath(intentFilePath)) {
      launchFilePath = intentFilePath;
      debugLogService.addLog('应用启动时收到Intent文件路径: $intentFilePath',
          level: 'INFO', tag: 'FileAssociation');
    }
  }

  // 加载开发者选项设置，决定是否启用日志收集
  Future.microtask(() async {
    try {
      final enableLogCollection = await SettingsStorage.loadBool(
          'enable_debug_log_collection',
          defaultValue: true);

      if (!enableLogCollection) {
        debugLogService.stopCollecting();
        debugLogService.addLog('根据用户设置，日志收集已禁用',
            level: 'INFO', tag: 'LogService');
      } else {
        debugLogService.addLog('根据用户设置，日志收集已启用',
            level: 'INFO', tag: 'LogService');
      }
    } catch (e) {
      debugLogService.addError('加载日志收集设置失败: $e', tag: 'LogService');
    }
  });

  // 增加Flutter引擎内存限制，减少OOM风险
  if (!kIsWeb && Platform.isAndroid) {
    // 为隔离区和图像解码设置更高的内存限制
    const int maxMemoryMB = 256; // 设置为256MB
    try {
      // 增加VM内存限制
      await SystemChannels.platform.invokeMethod('VMService.setFlag', {
        'name': 'max_old_space_size',
        'value': maxMemoryMB.toString(),
      });
      debugPrint('已设置Flutter隔离区最大内存为 ${maxMemoryMB}MB');
    } catch (e) {
      debugPrint('设置内存限制失败: $e');
    }
  }

  // 初始化MediaKit - 添加错误处理防止重复初始化
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit初始化警告: $e');
    // 如果是重复初始化错误，可以安全忽略
    if (!e.toString().contains('invalid reuse after initialization failure')) {
      rethrow;
    }
  }
  MediaKitPlayerAdapter.setMpvLogLevelNone();

  // 添加全局异常捕获
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // 记录错误
    debugPrint('应用发生错误: ${details.exception}');
    debugPrint('错误堆栈: ${details.stack}');
  };

  // 在应用启动时为iOS请求相册权限
  // if (Platform.isIOS) {
  //   print("[App Startup] Attempting to request photos permission for iOS...");
  //   PermissionStatus photoStatus = await Permission.photos.request();
  //   print("[App Startup] iOS Photos permission status: $photoStatus");
  //
  //   if (photoStatus.isPermanentlyDenied) {
  //     print("[App Startup] iOS Photos permission was permanently denied. User needs to go to settings.");
  //     // 这里可以考虑后续添加一个全局提示，引导用户去系统设置
  //   } else if (photoStatus.isDenied) {
  //     print("[App Startup] iOS Photos permission was denied by the user in this session.");
  //   } else if (photoStatus.isGranted) {
  //     print("[App Startup] iOS Photos permission granted.");
  //   } else {
  //     print("[App Startup] iOS Photos permission status: $photoStatus (unhandled case)");
  //   }
  // }

  // 请求Android存储权限
  if (!kIsWeb && Platform.isAndroid) {
    debugPrint("正在请求Android存储权限...");

    // 先检查当前权限状态
    var storageStatus = await Permission.storage.status;
    debugPrint("当前存储权限状态: $storageStatus");

    // 如果权限被拒绝，请求权限
    if (storageStatus.isDenied) {
      storageStatus = await Permission.storage.request();
      debugPrint("请求后存储权限状态: $storageStatus");
    }

    // 对于Android 10+，请求READ_EXTERNAL_STORAGE
    if (await Permission.photos.isRestricted ||
        await Permission.photos.isDenied) {
      final photoStatus = await Permission.photos.request();
      debugPrint("媒体访问权限状态: $photoStatus");
    }

    // 对于Android 11+，尝试请求管理外部存储权限
    try {
      bool needManageStorage = false;

      try {
        // 检查是否需要特殊管理权限 - Android 11+
        final sdkVersion = int.tryParse(Platform.operatingSystemVersion
                .replaceAll(RegExp(r'[^0-9]'), '')) ??
            0;
        needManageStorage = sdkVersion >= 30; // Android 11 是 API 30
        debugPrint(
            "Android SDK版本: $sdkVersion, 需要请求管理存储权限: $needManageStorage");
      } catch (e) {
        debugPrint("无法确定Android版本: $e, 将尝试请求管理存储权限");
        needManageStorage = true;
      }

      if (needManageStorage) {
        final manageStatus = await Permission.manageExternalStorage.status;
        debugPrint("当前管理存储权限状态: $manageStatus");

        if (manageStatus.isDenied) {
          final newStatus = await Permission.manageExternalStorage.request();
          debugPrint("请求后管理存储权限状态: $newStatus");

          if (newStatus.isDenied || newStatus.isPermanentlyDenied) {
            debugPrint("警告: 未获得管理存储权限，某些功能可能受限");
          }
        }
      }
    } catch (e) {
      debugPrint("请求管理存储权限失败: $e");
    }

    // 重新检查权限并打印最终状态
    final finalStatus = await Permission.storage.status;
    final manageStatus = await Permission.manageExternalStorage.status;
    debugPrint("最终存储权限状态: $finalStatus, 管理存储权限状态: $manageStatus");
  }
  // 设置方法通道处理器
  menuChannel.setMethodCallHandler((call) async {
    print('[Dart] 收到方法调用: ${call.method}');

    if (call.method == 'uploadVideo') {
      try {
        // 获取UI上下文
        final context = navigatorKey.currentState?.overlay?.context;
        if (context == null) {
          print('[Dart] 错误: 无法获取UI上下文');
          return '错误: 无法获取UI上下文';
        }

        // 延迟确保UI准备好
        Future.microtask(() {
          print('[Dart] 启动文件选择器');
          _showGlobalUploadDialog(context);
        });

        return '正在显示文件选择器';
      } catch (e) {
        print('[Dart] 错误: $e');
        return '错误: $e';
      }
    } else if (call.method == 'openVideoPlayback') {
      try {
        final context = navigatorKey.currentState?.overlay?.context;
        if (context == null) {
          print('[Dart] 错误: 无法获取UI上下文');
          return '错误: 无法获取UI上下文';
        }

        Future.microtask(() {
          _navigateToPage(context, 1); // 切换到视频播放页面（索引1）
        });

        return '正在切换到视频播放页面';
      } catch (e) {
        print('[Dart] 错误: $e');
        return '错误: $e';
      }
    } else if (call.method == 'openHome') {
      try {
        final context = navigatorKey.currentState?.overlay?.context;
        if (context == null) {
          print('[Dart] 错误: 无法获取UI上下文');
          return '错误: 无法获取UI上下文';
        }

        Future.microtask(() {
          _navigateToPage(context, 0); // 切换到主页（索引0）
        });

        return '正在切换到主页';
      } catch (e) {
        print('[Dart] 错误: $e');
        return '错误: $e';
      }
    } else if (call.method == 'openMediaLibrary') {
      try {
        final context = navigatorKey.currentState?.overlay?.context;
        if (context == null) {
          print('[Dart] 错误: 无法获取UI上下文');
          return '错误: 无法获取UI上下文';
        }

        Future.microtask(() {
          _navigateToPage(context, 2); // 切换到媒体库页面（索引2）
        });

        return '正在切换到媒体库页面';
      } catch (e) {
        print('[Dart] 错误: $e');
        return '错误: $e';
      }
    } else if (call.method == 'openNewSeries') {
      try {
        // iOS平台不支持新番更新页面，直接返回错误信息
        if (Platform.isIOS) {
          print('[Dart] iOS平台不支持新番更新功能');
          return 'iOS平台不支持新番更新功能';
        }

        final context = navigatorKey.currentState?.overlay?.context;
        if (context == null) {
          print('[Dart] 错误: 无法获取UI上下文');
          return '错误: 无法获取UI上下文';
        }

        Future.microtask(() {
          _navigateToPage(context, 3); // 切换到新番更新页面（索引3）
        });

        return '正在切换到新番更新页面';
      } catch (e) {
        print('[Dart] 错误: $e');
        return '错误: $e';
      }
    } else if (call.method == 'openSettings') {
      try {
        final context = navigatorKey.currentState?.overlay?.context;
        if (context == null) {
          print('[Dart] 错误: 无法获取UI上下文');
          return '错误: 无法获取UI上下文';
        }

        Future.microtask(() {
          final uiThemeProvider =
              Provider.of<UIThemeProvider>(context, listen: false);
          if (uiThemeProvider.isCupertinoTheme) {
            _navigateToPage(context, 3); // Cupertino 主题保留底部设置页
          } else {
            SettingsPage.showWindow(context); // Nipaplay 主题使用弹窗设置页
          }
        });

        return '正在打开设置';
      } catch (e) {
        print('[Dart] 错误: $e');
        return '错误: $e';
      }
    }

    // 默认返回空字符串
    return '';
  });

  // 创建应用所需的目录结构
  await _initializeAppDirectories();

  // 预加载播放器内核设置
  await PlayerFactory.initialize();

  // 预加载弹幕内核设置
  await DanmakuKernelFactory.initialize();

  // 初始化安全书签服务 (仅限 macOS)
  if (!kIsWeb && Platform.isMacOS) {
    try {
      await SecurityBookmarkService.restoreAllBookmarks();
    } catch (e) {
      debugPrint('SecurityBookmarkService 书签恢复失败: $e');
    }
  }

  // 并行执行初始化操作
  await Future.wait(<Future<dynamic>>[
    // 初始化弹弹play服务
    DandanplayService.initialize(),
    // 初始化服务提供者
    ServiceProvider.initialize(),

    // 加载设置
    Future.wait(<Future<dynamic>>[
      SettingsStorage.loadString('themeMode', defaultValue: 'system'),
      SettingsStorage.loadString('backgroundImageMode'),
      SettingsStorage.loadString('customBackgroundPath'),
      SettingsStorage.loadString('anime_detail_display_mode',
          defaultValue: 'simple'),
      SettingsStorage.loadString(
        ThemeNotifier.backgroundImageRenderModeKey,
        defaultValue: BackgroundImageRenderMode.opacity.storageKey,
      ),
      SettingsStorage.loadDouble(
        ThemeNotifier.backgroundImageOverlayOpacityKey,
        defaultValue: ThemeNotifier.defaultBackgroundImageOverlayOpacity,
      ),
    ]).then((results) {
      globals.backgroundImageMode =
          (results[1] as String?) ?? globals.backgroundImageMode;
      globals.customBackgroundPath =
          (results[2] as String?) ?? globals.customBackgroundPath;

      // 检查自定义背景路径有效性，发现无效则恢复为默认图片
      _validateCustomBackgroundPath();

      final themeMode = (results[0] as String?) ?? 'system';
      final animeDetailMode = (results[3] as String?) ?? 'simple';
      final backgroundImageRenderMode =
          (results[4] as String?) ?? BackgroundImageRenderMode.opacity.storageKey;
      final backgroundImageOverlayOpacity = (results[5] as double?) ??
          ThemeNotifier.defaultBackgroundImageOverlayOpacity;

      return <String, dynamic>{
        'themeMode': themeMode,
        'animeDetailMode': animeDetailMode,
        'backgroundImageRenderMode': backgroundImageRenderMode,
        'backgroundImageOverlayOpacity': backgroundImageOverlayOpacity,
      };
    }),

    // 根据设置清理弹幕缓存
    _prepareDanmakuCachePolicy(),

    // 初始化 BangumiService
    BangumiService.instance.initialize(),

    // 初始化观看记录管理器
    WatchHistoryManager.initialize(),

    // 初始化自动同步服务（仅桌面端）
    if (globals.isDesktop)
      AutoSyncService.instance.initialize()
    else
      Future.value(),

    // SMB 本地代理（用于 SMB 文件按 HTTP/Range 播放与匹配）
    if (!kIsWeb) SMBProxyService.instance.initialize() else Future.value(),
  ]).then((results) async {
    // BangumiService初始化完成后，检查并刷新缺少标签的缓存
    Future.microtask(() async {
      try {
        await BangumiService.instance.checkAndRefreshCacheWithoutTags();
      } catch (e) {
        debugPrint('检查缓存标签失败: $e');
      }
    });

    // 处理主题模式设置
    final settingsMap = results[2] as Map<String, dynamic>;
    final savedThemeMode = settingsMap['themeMode'] as String? ?? 'system';
    final savedDetailModeString =
        settingsMap['animeDetailMode'] as String? ?? 'simple';
    final savedBackgroundRenderModeString =
        settingsMap['backgroundImageRenderMode'] as String?;
    final savedBackgroundOverlayOpacity =
        settingsMap['backgroundImageOverlayOpacity'] as double? ??
            ThemeNotifier.defaultBackgroundImageOverlayOpacity;
    final savedDetailMode =
        AnimeDetailDisplayModeStorage.fromString(savedDetailModeString);
    final savedBackgroundRenderMode =
        BackgroundImageRenderModeStorage.fromString(
            savedBackgroundRenderModeString);
    ThemeMode initialThemeMode;
    switch (savedThemeMode) {
      case 'light':
        initialThemeMode = ThemeMode.light;
        break;
      case 'dark':
        initialThemeMode = ThemeMode.dark;
        break;
      default:
        initialThemeMode = ThemeMode.system;
    }

    // 初始化系统资源监控（所有平台）
    SystemResourceMonitor.initialize();

    if (globals.isDesktop) {
      await windowManager.ensureInitialized();
      try {
        await windowManager.setIcon('assets/images/logo512.png');
      } catch (e) {
      }
      WindowOptions windowOptions = const WindowOptions(
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        title: "NipaPlay",
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setMinimumSize(const Size(600, 400));
        await windowManager.maximize();
        await windowManager.show();
        await windowManager.focus();
      });
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BottomBarProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => VideoPlayerState()),
          ChangeNotifierProvider(
            create: (context) => ThemeNotifier(
              initialThemeMode: initialThemeMode,
              initialBackgroundImageMode: globals.backgroundImageMode,
              initialCustomBackgroundPath: globals.customBackgroundPath,
              initialAnimeDetailDisplayMode: savedDetailMode,
              initialBackgroundImageRenderMode: savedBackgroundRenderMode,
              initialBackgroundImageOverlayOpacity:
                  savedBackgroundOverlayOpacity,
            ),
          ),
          ChangeNotifierProvider(create: (_) => TabChangeNotifier()),
          // 统一使用 ServiceProvider 中的全局实例，避免重复初始化与事件风暴
          ChangeNotifierProvider.value(
              value: ServiceProvider.watchHistoryProvider),
          ChangeNotifierProvider.value(value: ServiceProvider.scanService),
          ChangeNotifierProvider(create: (_) => DeveloperOptionsProvider()),
          ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
          ChangeNotifierProvider(create: (_) => HomeSectionsSettingsProvider()),
          ChangeNotifierProvider(create: (_) => UIThemeProvider()),
          ChangeNotifierProvider(create: (_) => SharedRemoteLibraryProvider()),
          ChangeNotifierProvider(create: (_) => JellyfinTranscodeProvider()),
          ChangeNotifierProvider(create: (_) => EmbyTranscodeProvider()),
          ChangeNotifierProvider.value(value: debugLogService),
          ChangeNotifierProvider.value(value: ServiceProvider.jellyfinProvider),
          ChangeNotifierProvider.value(value: ServiceProvider.embyProvider),
          ChangeNotifierProvider.value(
              value: ServiceProvider.dandanplayRemoteProvider),
        ],
        child: NipaPlayApp(launchFilePath: launchFilePath),
      ),
    );
  });
}

// 初始化应用所需的所有目录
Future<void> _initializeAppDirectories() async {
  try {
    // Linux平台先处理数据迁移，然后创建目录
    // 其他平台直接创建目录（getAppStorageDirectory内部会处理Linux迁移）
    await StorageService.getAppStorageDirectory();
    await StorageService.getTempDirectory();
    await StorageService.getCacheDirectory();
    await StorageService.getDownloadsDirectory();
    await StorageService.getVideosDirectory();

    // 创建临时目录
    await _ensureTemporaryDirectoryExists();
  } catch (e) {
    debugPrint('创建应用目录结构失败: $e');
  }
}

Future<void> _prepareDanmakuCachePolicy() async {
  try {
    final clearOnLaunch = await SettingsStorage.loadBool(
      SettingsKeys.clearDanmakuCacheOnLaunch,
      defaultValue: false,
    );
    if (clearOnLaunch) {
      await DanmakuCacheManager.clearAllCache();
    } else {
      await DanmakuCacheManager.clearExpiredCache();
    }
  } catch (e) {
    debugPrint('初始化弹幕缓存策略失败: $e');
  }
}

// 确保临时目录存在
Future<void> _ensureTemporaryDirectoryExists() async {
  try {
    // 使用StorageService获取应用目录
    final appDir = await StorageService.getAppStorageDirectory();

    // 创建tmp目录路径
    final tmpDir = Directory(path.join(appDir.path, 'tmp'));

    // 确保tmp目录存在
    if (!tmpDir.existsSync()) {
      tmpDir.createSync(recursive: true);
    }
  } catch (e) {
    debugPrint('创建临时目录失败: $e');
  }
}

class NipaPlayApp extends StatefulWidget {
  final String? launchFilePath;

  const NipaPlayApp({super.key, this.launchFilePath});

  @override
  State<NipaPlayApp> createState() => _NipaPlayAppState();
}

class _NipaPlayAppState extends State<NipaPlayApp> {
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    // 启动后设置WatchHistoryProvider监听ScanService
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (globals.isDesktop) {
        SingleInstanceService.registerMessageHandler(
          _handleSingleInstanceMessage,
        );
      }
      DesktopExitHandler.instance.initialize(navigatorKey);

      // 调试：启动时打印数据库内容
      Future.delayed(const Duration(milliseconds: 1000), () async {
        try {
          final db = WatchHistoryDatabase.instance;
          await db.debugPrintAllData();
        } catch (e) {
          debugPrint('启动时调试打印数据库内容失败: $e');
        }
      });

      try {
        final watchHistoryProvider =
            Provider.of<WatchHistoryProvider>(context, listen: false);
        final scanService = Provider.of<ScanService>(context, listen: false);

        watchHistoryProvider.setScanService(scanService);

        // 启动历史记录加载
        watchHistoryProvider.loadHistory();
      } catch (e) {
        debugPrint('_NipaPlayAppState: 设置监听器时出错: $e');
      }
    });
  }

  Future<void> _handleSingleInstanceMessage(
    SingleInstanceMessage message,
  ) async {
    if (!mounted) {
      return;
    }
    if (message.focus) {
      await _focusMainWindow();
    }
    final filePath = message.filePath;
    if (filePath != null) {
      await LaunchFileHandler.handle(
        filePath,
        onError: (error) {
          if (mounted) {
            BlurSnackBar.show(context, error);
          }
        },
      );
    }
  }

  Future<void> _focusMainWindow() async {
    if (!globals.isDesktop) {
      return;
    }
    try {
      final isMinimized = await windowManager.isMinimized();
      if (isMinimized) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[SingleInstance] 唤起窗口失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (details) {
        setState(() {
          _isDragging = true;
        });
        debugPrint('[DragDrop] onDragEntered');
      },
      onDragExited: (details) {
        setState(() {
          _isDragging = false;
        });
        debugPrint('[DragDrop] onDragExited');
      },
      onDragDone: (details) {
        setState(() {
          _isDragging = false;
        });
        debugPrint('[DragDrop] onDragDone: ${details.files.length} files');
        if (details.files.isNotEmpty) {
          final filePath = details.files.first.path;
          debugPrint('[DragDrop] Handling file: $filePath');
          _handleDroppedFile(filePath);
        }
      },
      child: Consumer2<ThemeNotifier, UIThemeProvider>(
        builder: (context, themeNotifier, uiThemeProvider, child) {
          if (!uiThemeProvider.isInitialized) {
            return MaterialApp(
              title: 'NipaPlay',
              debugShowCheckedModeBanner: false,
              home: const SplashScreen(),
              builder: (context, appChild) {
                return Stack(
                  children: [
                    appChild ?? const SizedBox.shrink(),
                    if (_isDragging) const DragDropOverlay(),
                  ],
                );
              },
            );
          }

          final descriptor = uiThemeProvider.currentThemeDescriptor;
          final environment = ThemeEnvironment(
            isDesktop: globals.isDesktop,
            isPhone: globals.isPhone,
            isWeb: kIsWeb,
            isIOS: !kIsWeb && Platform.isIOS,
            isTablet: globals.isTablet,
          );
          final overlayBuilder = (Widget child) => Stack(
                children: [
                  child,
                  if (_isDragging) const DragDropOverlay(),
                ],
              );

          final themeContext = ThemeBuildContext(
            themeNotifier: themeNotifier,
            navigatorKey: navigatorKey,
            launchFilePath: widget.launchFilePath,
            environment: environment,
            settings: uiThemeProvider.currentThemeSettings,
            overlayBuilder: overlayBuilder,
            materialHomeBuilder: () =>
                MainPage(launchFilePath: widget.launchFilePath),
            fluentHomeBuilder: () =>
                MainPage(launchFilePath: widget.launchFilePath),
            cupertinoHomeBuilder: () =>
                CupertinoMainPage(launchFilePath: widget.launchFilePath),
          );

          return descriptor.buildApp(themeContext);
        },
      ),
    );
  }

  void _handleDroppedFile(String filePath) async {
    try {
      debugPrint('[DragDrop] Handling dropped file: $filePath');

      // 检查是否存在历史记录
      WatchHistoryItem? historyItem =
          await WatchHistoryManager.getHistoryItem(filePath);

      historyItem ??= WatchHistoryItem(
        filePath: filePath,
        animeName: path.basenameWithoutExtension(filePath),
        watchProgress: 0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: DateTime.now(),
      );

      final playableItem = PlayableItem(
        videoPath: filePath,
        title: historyItem.animeName,
        historyItem: historyItem,
      );

      await PlaybackService().play(playableItem);
      debugPrint('[DragDrop] PlaybackService called for dropped file');
    } catch (e) {
      debugPrint('[DragDrop] Error handling dropped file: $e');
      // 可以考虑在这里显示一个错误提示
    }
  }
}

class MainPage extends StatefulWidget {
  final String? launchFilePath;

  // 根据平台动态创建pages列表
  static List<Widget> createPages() {
    List<Widget> pages = [
      const DashboardHomePage(),
      const PlayVideoPage(),
      const AnimePage(),
      const AccountPage(),
    ];
    return pages;
  }

  late final List<Widget> pages;

  MainPage({super.key, this.launchFilePath}) {
    pages = createPages();
  }

  @override
  // ignore: library_private_types_in_public_api
  MainPageState createState() => MainPageState();
}

class MainPageState extends State<MainPage>
    with SingleTickerProviderStateMixin, WindowListener {
  bool isMaximized = false;
  TabController? globalTabController;
  bool _showSplash = true;

  // 用于热键管理
  bool _hotkeysAreRegistered = false;
  VideoPlayerState? _videoPlayerState;
  AppearanceSettingsProvider? _appearanceSettingsProvider;

  // Static method to find MainPageState from context
  static MainPageState? of(BuildContext context) {
    return context.findAncestorStateOfType<MainPageState>();
  }

  // TabChangeNotifier监听 - Temporarily remove or comment out for Scheme 1
  TabChangeNotifier? _tabChangeNotifier;
  void _onTabChangeRequested() {
    debugPrint('[MainPageState] _onTabChangeRequested triggered.');
    final index = _tabChangeNotifier?.targetTabIndex;
    debugPrint('[MainPageState] targetTabIndex: $index');

    if (index != null) {
      debugPrint('[MainPageState] 准备调用_manageHotkeys()...');
      _manageHotkeys();
      debugPrint('[MainPageState] _manageHotkeys()调用完成');

      if (globalTabController != null) {
        debugPrint(
            '[MainPageState] globalTabController可用，当前索引: ${globalTabController!.index}');
        if (globalTabController!.index != index) {
          try {
            debugPrint('[MainPageState] 尝试切换到标签: $index');
            // 强制启用页面滑动动画
            globalTabController!.animateTo(index);
            debugPrint('[MainPageState] 已切换到标签: $index');
          } catch (e) {
            debugPrint('[MainPageState] 切换标签失败: $e');
          }
        } else {
          debugPrint('[MainPageState] 已经是目标标签: $index，无需切换');
        }
      } else {
        debugPrint('[MainPageState] globalTabController为空，无法切换标签');
      }

      // 清除标记，避免多次触发
      debugPrint('[MainPageState] 正在清除targetTabIndex');
      _tabChangeNotifier?.clearMainTabIndex();
    } else {
      debugPrint('[MainPageState] targetTabIndex为空，不进行任何操作');
    }
  }

  void _manageHotkeys() {
    final videoState = _videoPlayerState;
    if (videoState == null || !mounted) {
      //debugPrint('[HotkeyManager] 跳过热键管理: videoState=${videoState != null}, mounted=$mounted');
      return;
    }

    final tabIndex = globalTabController?.index ?? -1;

    final bool shouldBeRegistered = tabIndex == 1 && videoState.hasVideo;

    //debugPrint('[HotkeyManager] 最终判断: shouldBeRegistered=$shouldBeRegistered, currentlyRegistered=$_hotkeysAreRegistered');

    if (shouldBeRegistered && !_hotkeysAreRegistered) {
      //debugPrint('[HotkeyManager] 开始注册热键...');
      HotkeyService().registerHotkeys().then((_) {
        _hotkeysAreRegistered = true;
        //debugPrint('[HotkeyManager] 热键注册完成');
      }).catchError((e) {
        //debugPrint('[HotkeyManager] 热键注册失败: $e');
      });
    } else if (!shouldBeRegistered && _hotkeysAreRegistered) {
      //debugPrint('[HotkeyManager] 开始注销热键...');
      HotkeyService().unregisterHotkeys().then((_) {
        _hotkeysAreRegistered = false;
        //debugPrint('[HotkeyManager] 热键注销完成');
      }).catchError((e) {
        //debugPrint('[HotkeyManager] 热键注销失败: $e');
      });
    } else {
      //debugPrint('[HotkeyManager] 无需更改热键状态');
    }
  }

  void _onTabChange() {
    //debugPrint('[CPU-泄漏排查] 主页面Tab切换: 索引=${globalTabController?.index}');
    _manageHotkeys();
  }

  int _defaultPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _initializeController();
    _initializeListeners();
    _postFrameCallbacks();
  }

  Future<void> _initializeController() async {
    final prefs = await SharedPreferences.getInstance();
    _defaultPageIndex = prefs.getInt('default_page_index') ?? 0;

    // 强制启用页面滑动动画
    // ... (注释省略)

    if (mounted) {
      // 主页面Tab数量与页面列表保持一致
      final tabLength = widget.pages.length;
      globalTabController = TabController(
        length: tabLength,
        vsync: this,
        initialIndex: _defaultPageIndex.clamp(0, tabLength - 1),
      );
    }
  }

  void _initializeListeners() {
    globalTabController?.addListener(_onTabChange);

    if (globals.isDesktop) {
      windowManager.addListener(this);
    }
  }

  void _postFrameCallbacks() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.launchFilePath != null) {
        _handleLaunchFile(widget.launchFilePath!);
      }

      if (globals.isDesktop) {
        _checkWindowMaximizedState();
      }

      _startSplashScreenSequence();

      if (globals.isDesktop) {
        _initializeHotkeys();
      }
    });
  }

  void _initializeHotkeys() async {
    await HotkeyServiceInitializer().initialize(context);
    ShortcutTooltipManager();
  }

  void _startSplashScreenSequence() {
    // 确保在第一帧后执行
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // 直接使用已加载的 _defaultPageIndex, 不再需要动画切换
      // 如果需要启动动画，可以在这里实现

      // 延迟一段时间后隐藏启动画面
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() {
          _showSplash = false;
        });
      }
    });
  }

  // 处理启动文件
  Future<void> _handleLaunchFile(String filePath) async {
    await LaunchFileHandler.handle(
      filePath,
      onError: (error) {
        if (mounted) {
          BlurSnackBar.show(context, error);
        }
      },
    );
  }

  // 检查窗口是否已最大化
  Future<void> _checkWindowMaximizedState() async {
    if (globals.isDesktop) {
      final maximized = await windowManager.isMaximized();
      if (maximized != isMaximized) {
        setState(() {
          isMaximized = maximized;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final newAppearanceSettingsProvider =
        Provider.of<AppearanceSettingsProvider>(context, listen: false);
    if (newAppearanceSettingsProvider != _appearanceSettingsProvider) {
      _appearanceSettingsProvider = newAppearanceSettingsProvider;
    }

    // 初始化对话框尺寸管理器 - 只初始化一次
    if (!globals.DialogSizes.isInitialized) {
      final screenSize = MediaQuery.of(context).size;
      globals.DialogSizes.initialize(screenSize.width, screenSize.height);
    }

    // 只添加一次监听 - Temporarily remove or comment out for Scheme 1
    _tabChangeNotifier ??= Provider.of<TabChangeNotifier>(context);
    _tabChangeNotifier?.removeListener(_onTabChangeRequested);
    _tabChangeNotifier?.addListener(_onTabChangeRequested);

    // 添加VideoPlayerState监听
    final newVideoPlayerState = Provider.of<VideoPlayerState>(context);
    if (newVideoPlayerState != _videoPlayerState) {
      _videoPlayerState?.removeListener(_manageHotkeys);
      _videoPlayerState = newVideoPlayerState;
      _videoPlayerState?.addListener(_manageHotkeys);
    }
    _manageHotkeys(); // 初始状态检查
  }

  @override
  void dispose() {
    _tabChangeNotifier
        ?.removeListener(_onTabChangeRequested); // Temporarily remove
    globalTabController?.removeListener(_onTabChange);
    _videoPlayerState?.removeListener(_manageHotkeys);
    globalTabController?.dispose();
    if (globals.isDesktop) {
      windowManager.removeListener(this);
    }

    // 清理安全书签资源 (仅限 macOS)
    if (!kIsWeb && Platform.isMacOS) {
      try {
        SecurityBookmarkService.cleanup();
        debugPrint('SecurityBookmarkService 清理完成');
      } catch (e) {
        debugPrint('SecurityBookmarkService 清理失败: $e');
      }
    }

    // 释放系统资源监控，移除桌面平台限制
    SystemResourceMonitor.dispose();

    // 清理热键服务
    if (globals.isDesktop) {
      HotkeyServiceInitializer().dispose();
    }

    super.dispose();
  }

  // 切换窗口大小
  void _toggleWindowSize() async {
    if (globals.isDesktop) {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      await _checkWindowMaximizedState();
    }
  }

  void _minimizeWindow() async {
    await windowManager.minimize();
  }

  void _closeWindow() async {
    await windowManager.close();
  }

  // WindowListener回调
  @override
  void onWindowMaximize() {
    setState(() {
      isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      isMaximized = false;
    });
  }

  @override
  void onWindowResize() {
    _checkWindowMaximizedState();
  }

  @override
  void onWindowEvent(String eventName) {
    // 监听所有窗口事件，可以在这里添加日志
    // print('窗口事件: $eventName');
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final mediaPadding = MediaQuery.of(context).padding;
    final bool isMac = !kIsWeb && Platform.isMacOS;
    final bool isDesktop = globals.isDesktop;
    final double baseTopPadding = isMac ? 10 : 4;
    final double baseRightPadding = isMac ? 20 : 10;
    final double topPadding =
        isDesktop ? baseTopPadding : baseTopPadding + mediaPadding.top;
    final double rightPadding =
        isDesktop ? baseRightPadding : baseRightPadding + mediaPadding.right;
    return Stack(
      children: [
        // 使用 Selector 只监听需要的状态
        Selector<VideoPlayerState, bool>(
          selector: (context, videoState) => videoState.shouldShowAppBar(),
          builder: (context, shouldShowAppBar, child) {
            return CustomScaffold(
              pages: widget.pages,
              tabPage: createTabLabels(),
              pageIsHome: true,
              shouldShowAppBar: shouldShowAppBar,
              tabController: globalTabController,
            );
          },
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _showSplash
              ? const SplashScreen(key: ValueKey('splash'))
              : const SizedBox.shrink(key: ValueKey('no_splash')),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 40,
            child: GestureDetector(
              onDoubleTap: _toggleWindowSize,
              onPanStart: (details) async {
                if (globals.isDesktop) {
                  await windowManager.startDragging();
                }
              },
            ),
          ),
        ),
        // 使用 Selector 只监听需要的状态
        Selector<VideoPlayerState, bool>(
          selector: (context, videoState) => videoState.shouldShowAppBar(),
          builder: (context, shouldShowAppBar, child) {
            if (!globals.isDesktopOrTablet || !shouldShowAppBar) {
              return const SizedBox.shrink();
            }
            return Positioned(
              top: topPadding,
              right: rightPadding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SystemResourceDisplay(),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: kWindowCaptionHeight,
                    child: Center(
                      child: Image.asset(
                        'assets/logo2.png',
                        height: 24,
                        fit: BoxFit.contain,
                        color: isDarkMode ? Colors.white : Colors.black,
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: kWindowCaptionHeight,
                    child: Center(
                      child: _ThemeToggleButton(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: kWindowCaptionHeight,
                    child: Center(
                      child: _SettingsEntryButton(
                        onPressed: () => SettingsPage.showWindow(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!kIsWeb && (Platform.isWindows || Platform.isLinux))
                    SizedBox(
                      height: kWindowCaptionHeight,
                      child: Center(
                        child: WindowControlButtons(
                          isMaximized: isMaximized,
                          onMinimize: _minimizeWindow,
                          onMaximizeRestore: _toggleWindowSize,
                          onClose: _closeWindow,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SettingsEntryButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _SettingsEntryButton({required this.onPressed});

  @override
  State<_SettingsEntryButton> createState() => _SettingsEntryButtonState();
}

class _ThemeToggleButton extends StatefulWidget {
  @override
  State<_ThemeToggleButton> createState() => _ThemeToggleButtonState();
}

class _ThemeToggleButtonState extends State<_ThemeToggleButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (_isHovered == value) {
      return;
    }
    setState(() {
      _isHovered = value;
    });
  }

  void _toggleTheme() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    context.read<ThemeNotifier>().themeMode =
        isDarkMode ? ThemeMode.light : ThemeMode.dark;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final double scale = _isPressed ? 0.92 : (_isHovered ? 1.1 : 1.0);
    final Color iconColor = _isHovered
        ? const Color(0xFFFF2E55)
        : (isDarkMode ? Colors.white : Colors.black87);
    final icon = isDarkMode ? Icons.nightlight_rounded : Icons.light_mode_rounded;
    final tooltip = isDarkMode ? '切换到日间模式' : '切换到夜间模式';

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: _toggleTheme,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 120),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale:
                        Tween<double>(begin: 0.85, end: 1.0).animate(animation),
                    child: RotationTransition(
                      turns: Tween<double>(begin: 0.9, end: 1.0)
                          .animate(animation),
                      child: child,
                    ),
                  ),
                );
              },
              child: Icon(
                icon,
                key: ValueKey<bool>(isDarkMode),
                size: 22,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsEntryButtonState extends State<_SettingsEntryButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (_isHovered == value) {
      return;
    }
    setState(() {
      _isHovered = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final double scale = _isPressed ? 0.92 : (_isHovered ? 1.1 : 1.0);
    final Color iconColor = _isHovered
        ? const Color(0xFFFF2E55)
        : (isDarkMode ? Colors.white : Colors.black87);

    return Tooltip(
      message: '设置',
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 120),
            child: Icon(
              Icons.settings_rounded,
              size: 22,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

// 检查自定义背景图片路径有效性
Future<void> _validateCustomBackgroundPath() async {
  final customPath = globals.customBackgroundPath;
  var defaultPath = (globals.isDesktop || globals.isTablet)
      ? 'assets/images/main_image.png'
      : 'assets/images/main_image_mobile.png';
  bool needReset = false;

  if (customPath.isEmpty) {
    needReset = true;
  } else {
    try {
      // 只允许常见图片格式
      final ext = path.extension(customPath).toLowerCase();
      if (!['.png', '.jpg', '.jpeg', '.bmp', '.gif'].contains(ext)) {
        needReset = true;
      } else {
        final file = File(customPath);
        if (!file.existsSync()) {
          needReset = true;
        }
      }
    } catch (e) {
      needReset = true;
    }
  }

  if (needReset) {
    globals.customBackgroundPath = defaultPath;
    await SettingsStorage.saveString('customBackgroundPath', defaultPath);
  }
}

// 全局弹出上传视频逻辑
Future<void> _showGlobalUploadDialog(BuildContext context) async {
  print('[Dart] 开始选择视频文件');

  // 使用FilePickerService选择视频文件
  try {
    print('[Dart] 打开文件选择器');
    final filePickerService = FilePickerService();
    final filePath = await filePickerService.pickVideoFile();

    if (filePath == null) {
      print('[Dart] 用户取消了选择或未选择文件');
      return;
    }

    print('[Dart] 选择了文件: $filePath');

    // 确保context还有效
    if (!context.mounted) {
      print('[Dart] 上下文已失效，无法初始化播放器');
      return;
    }

    // 检查是否存在历史记录
    WatchHistoryItem? historyItem =
        await WatchHistoryManager.getHistoryItem(filePath);

    historyItem ??= WatchHistoryItem(
      filePath: filePath,
      animeName: path.basenameWithoutExtension(filePath),
      watchProgress: 0,
      lastPosition: 0,
      duration: 0,
      lastWatchTime: DateTime.now(),
    );

    final playableItem = PlayableItem(
      videoPath: filePath,
      title: historyItem.animeName,
      historyItem: historyItem,
    );

    await PlaybackService().play(playableItem);
    print('[Dart] PlaybackService 已调用');
  } catch (e) {
    print('[Dart] 文件选择过程出错: $e');

    if (context.mounted) {
      BlurSnackBar.show(context, '选择文件时出错: $e');
    }
  }
}

// 导航到特定页面逻辑
void _navigateToPage(BuildContext context, int pageIndex) {
  print('[Dart] 准备导航到页面索引: $pageIndex');

  // 尝试获取MainPageState
  MainPageState? mainPageState = MainPageState.of(context);
  if (mainPageState != null && mainPageState.globalTabController != null) {
    if (mainPageState.globalTabController!.index != pageIndex) {
      final enablePageAnimation =
          context.read<AppearanceSettingsProvider>().enablePageAnimation;
      if (enablePageAnimation) {
        mainPageState.globalTabController!.animateTo(pageIndex);
      } else {
        mainPageState.globalTabController!.index = pageIndex;
      }
      debugPrint(
          '[Dart - _navigateToPage] 直接切换到标签页$pageIndex (动画: $enablePageAnimation)');
    } else {
      debugPrint(
          '[Dart - _navigateToPage] globalTabController已经在索引$pageIndex，无需切换');
    }
  } else {
    debugPrint(
        '[Dart - _navigateToPage] 无法找到MainPageState或globalTabController');
    // 如果直接访问失败，使用TabChangeNotifier作为备选方案
    Provider.of<TabChangeNotifier>(context, listen: false).changeTab(pageIndex);
    debugPrint(
        '[Dart - _navigateToPage] 备选方案: 使用TabChangeNotifier请求切换到标签页$pageIndex');
  }
}
