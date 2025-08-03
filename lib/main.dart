import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nipaplay/pages/tab_labels.dart';
import 'package:nipaplay/utils/app_theme.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/utils/system_resource_monitor.dart';
import 'package:nipaplay/widgets/nipaplay_theme/custom_scaffold.dart';
import 'package:nipaplay/widgets/nipaplay_theme/menu_button.dart';
import 'package:nipaplay/widgets/nipaplay_theme/system_resource_display.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'pages/anime_page.dart';
import 'pages/settings_page.dart';
import 'pages/play_video_page.dart';
import 'pages/new_series_page.dart';
import 'utils/settings_storage.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'services/bangumi_service.dart';
import 'services/dandanplay_service.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'models/watch_history_model.dart';
import 'package:path/path.dart' as path;
import 'package:nipaplay/utils/network_checker.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/pages/fluent_main_page.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'dart:async';
import 'services/file_picker_service.dart';
import 'services/security_bookmark_service.dart';
import 'widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/utils/page_prewarmer.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/file_association_service.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/widgets/nipaplay_theme/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:nipaplay/widgets/nipaplay_theme/drag_drop_overlay.dart';
import 'providers/service_provider.dart';
import 'utils/platform_utils.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'services/hotkey_service_initializer.dart';
import 'utils/shortcut_tooltip_manager.dart';
import 'utils/hotkey_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// 将通道定义为全局变量
const MethodChannel menuChannel = MethodChannel('custom_menu_channel');

final GlobalKey<State<DefaultTabController>> tabControllerKey = GlobalKey<State<DefaultTabController>>();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化hotkey_manager
  if (globals.isDesktop) {
    await hotKeyManager.unregisterAll();
  }

  // 初始化调试日志服务（在最前面初始化，这样可以收集启动过程的日志）
  final debugLogService = DebugLogService();
  debugLogService.initialize();

  // 检查是否有文件路径参数传入
  String? launchFilePath;
  
  // 桌面平台通过命令行参数传入
  if (!kIsWeb && args.isNotEmpty && globals.isDesktop) {
    final filePath = args.first;
    if (await File(filePath).exists()) {
      launchFilePath = filePath;
      debugLogService.addLog('应用启动时收到命令行文件路径: $filePath', level: 'INFO', tag: 'FileAssociation');
    }
  }
  
  // Android平台通过Intent传入
  if (!kIsWeb && Platform.isAndroid) {
    final intentFilePath = await FileAssociationService.getOpenFileUri();
    if (intentFilePath != null && await FileAssociationService.validateFilePath(intentFilePath)) {
      launchFilePath = intentFilePath;
      debugLogService.addLog('应用启动时收到Intent文件路径: $intentFilePath', level: 'INFO', tag: 'FileAssociation');
    }
  }

  // 加载开发者选项设置，决定是否启用日志收集
  Future.microtask(() async {
    try {
      final enableLogCollection = await SettingsStorage.loadBool(
        'enable_debug_log_collection',
        defaultValue: true
      );
      
      if (!enableLogCollection) {
        debugLogService.stopCollecting();
        debugLogService.addLog('根据用户设置，日志收集已禁用', level: 'INFO', tag: 'LogService');
      } else {
        debugLogService.addLog('根据用户设置，日志收集已启用', level: 'INFO', tag: 'LogService');
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

  // 初始化MediaKit
  MediaKit.ensureInitialized();

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
    if (await Permission.photos.isRestricted || await Permission.photos.isDenied) {
      final photoStatus = await Permission.photos.request();
      debugPrint("媒体访问权限状态: $photoStatus");
    }
    
    // 对于Android 11+，尝试请求管理外部存储权限
    try {
      bool needManageStorage = false;
      
      try {
        // 检查是否需要特殊管理权限 - Android 11+
        final sdkVersion = int.tryParse(Platform.operatingSystemVersion.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        needManageStorage = sdkVersion >= 30; // Android 11 是 API 30
        debugPrint("Android SDK版本: $sdkVersion, 需要请求管理存储权限: $needManageStorage");
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
          _navigateToPage(context, 0); // 切换到视频播放页面（索引0）
        });
        
        return '正在切换到视频播放页面';
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
          _navigateToPage(context, 1); // 切换到媒体库页面（索引1）
        });
        
        return '正在切换到媒体库页面';
      } catch (e) {
        print('[Dart] 错误: $e');
        return '错误: $e';
      }
    } else if (call.method == 'openNewSeries') {
      try {
        final context = navigatorKey.currentState?.overlay?.context;
        if (context == null) {
          print('[Dart] 错误: 无法获取UI上下文');
          return '错误: 无法获取UI上下文';
        }
        
        Future.microtask(() {
          _navigateToPage(context, 2); // 切换到新番更新页面（索引2）
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
          _navigateToPage(context, 3); // 切换到设置页面（索引3）
        });
        
        return '正在切换到设置页面';
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

  // 检查网络连接
  _checkNetworkConnection();

  // 预加载播放器内核设置
  await PlayerFactory.initialize();

  // 预加载弹幕内核设置
  await DanmakuKernelFactory.initialize();

  // 初始化安全书签服务 (仅限 macOS)
  if (!kIsWeb && Platform.isMacOS) {
    try {
      await SecurityBookmarkService.restoreAllBookmarks();
      debugPrint('SecurityBookmarkService 书签恢复完成');
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
      SettingsStorage.loadDouble('blurPower'),
      SettingsStorage.loadString('backgroundImageMode'),
      SettingsStorage.loadString('customBackgroundPath'),
    ]).then((results) {
      globals.blurPower = results[1] as double;
      globals.backgroundImageMode = results[2] as String;
      globals.customBackgroundPath = results[3] as String;

      // 检查自定义背景路径有效性，发现无效则恢复为默认图片
      _validateCustomBackgroundPath();

      return results[0] as String;
    }),

    
    // 清理过期的弹幕缓存
    DanmakuCacheManager.clearExpiredCache(),
    
    // 初始化 BangumiService
    BangumiService.instance.initialize(),
    
    // 初始化观看记录管理器
    WatchHistoryManager.initialize(),
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
    String savedThemeMode = results[2] as String;
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
      windowManager.ensureInitialized();
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
          ChangeNotifierProvider(create: (_) => VideoPlayerState()),
          ChangeNotifierProvider(
            create: (context) => ThemeNotifier(
              initialThemeMode: initialThemeMode, 
              initialBlurPower: globals.blurPower,
              initialBackgroundImageMode: globals.backgroundImageMode,
              initialCustomBackgroundPath: globals.customBackgroundPath,
            ),
          ),
          ChangeNotifierProvider(create: (_) => TabChangeNotifier()),
          ChangeNotifierProvider(create: (_) => WatchHistoryProvider()),
          ChangeNotifierProvider(create: (_) => ScanService()),
          ChangeNotifierProvider(create: (_) => DeveloperOptionsProvider()),
          ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
          ChangeNotifierProvider(create: (_) => UIThemeProvider()),
          ChangeNotifierProvider.value(value: debugLogService),
          ChangeNotifierProvider(create: (context) { // 修改 JellyfinProvider 的创建方式
            final jellyfinProvider = JellyfinProvider();
            jellyfinProvider.initialize(); // 在创建后立即调用 initialize
            return jellyfinProvider;
          }),
          ChangeNotifierProvider(create: (context) { // 添加 EmbyProvider
            final embyProvider = EmbyProvider();
            embyProvider.initialize(); // 在创建后立即调用 initialize
            return embyProvider;
          }),
        ],
        child: NipaPlayApp(launchFilePath: launchFilePath),
      ),
    );
    // 启动后全局加载一次观看记录
    Future.microtask(() {
      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        final context = navigator.context;
        final provider = Provider.of<WatchHistoryProvider>(context, listen: false);
        provider.loadHistory();
        
        // 初始化并启动页面预热过程
        PagePrewarmer().initialize().then((_) {
          PagePrewarmer().startPrewarm(context);
        });
        
        // 添加一些测试日志，验证终端输出功能
        final debugLogService = Provider.of<DebugLogService>(context, listen: false);
        debugLogService.addLog('NipaPlay 应用启动完成', level: 'INFO', tag: 'App');
        debugLogService.addLog('终端输出功能已加载，可在设置 -> 开发者选项中查看', level: 'INFO', tag: 'LogService');
        debugLogService.addLog('这是一条调试信息示例', level: 'DEBUG', tag: 'Demo');
        debugLogService.addWarning('这是一条警告信息示例', tag: 'Demo');
        debugLogService.addError('这是一条错误信息示例（仅用于演示）', tag: 'Demo');
      }
    });
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
    
    debugPrint('应用目录结构初始化完成');
  } catch (e) {
    debugPrint('创建应用目录结构失败: $e');
  }
}

// 检查网络连接
Future<void> _checkNetworkConnection() async {
  debugPrint('==================== 网络连接诊断开始 ====================');
  if (!kIsWeb) {
    debugPrint('设备系统: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    debugPrint('设备类型: ${Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : Platform.isMacOS ? 'macOS' : '其他'}');
  } else {
    debugPrint('设备系统: Web');
  }
  
  // 检查代理设置
  if (!kIsWeb) {
    final proxySettings = NetworkChecker.checkProxySettings();
    debugPrint('代理设置检查结果:');
    if (proxySettings['hasProxy']) {
      debugPrint('系统存在代理设置:');
      final settings = proxySettings['proxySettings'] as Map<String, dynamic>;
      settings.forEach((key, value) {
        debugPrint(' - $key: $value');
      });
    } else {
      debugPrint('未检测到系统代理设置');
      if (proxySettings['error'] != null) {
        debugPrint('检测代理时出错: ${proxySettings['error']}');
      }
    }
  }
  
  try {
    debugPrint('\n测试百度连接:');
    // 检查百度网络连接 (详细模式)
    final baiduResult = await NetworkChecker.checkConnection(
      url: 'https://www.baidu.com',
      timeout: 5,
      verbose: true,
    );
    
    debugPrint('\n百度连接状态: ${baiduResult['connected'] ? '成功' : '失败'}');
    if (baiduResult['connected']) {
      debugPrint('响应时间: ${baiduResult['duration']}ms');
      debugPrint('响应大小: ${baiduResult['responseSize']} 字节');
    }
    
    // 等待一下再测试下一个地址
    await Future.delayed(const Duration(seconds: 1));
    
    debugPrint('\n测试Google连接(对比测试):');
    // 检查谷歌网络连接（对比测试）
    final googleResult = await NetworkChecker.checkConnection(
      url: 'https://www.google.com',
      timeout: 5,
      verbose: true,
    );
    
    debugPrint('\nGoogle连接状态: ${googleResult['connected'] ? '成功' : '失败'}');
    if (googleResult['connected']) {
      debugPrint('响应时间: ${googleResult['duration']}ms');
      debugPrint('响应大小: ${googleResult['responseSize']} 字节');
    }
    
    // 再测试一个国内的站点
    await Future.delayed(const Duration(seconds: 1));
    debugPrint('\n测试腾讯连接:');
    final tencentResult = await NetworkChecker.checkConnection(
      url: 'https://www.qq.com',
      timeout: 5,
      verbose: true,
    );
    
    debugPrint('\n腾讯连接状态: ${tencentResult['connected'] ? '成功' : '失败'}');
    if (tencentResult['connected']) {
      debugPrint('响应时间: ${tencentResult['duration']}ms');
      debugPrint('响应大小: ${tencentResult['responseSize']} 字节');
    }
    
    // 诊断结果总结
    debugPrint('\n==================== 网络诊断结果总结 ====================');
    if (baiduResult['connected'] || tencentResult['connected']) {
      debugPrint('✅ 国内网络连接正常');
    } else {
      debugPrint('❌ 国内网络连接异常，请检查网络设置');
    }
    
    if (googleResult['connected']) {
      debugPrint('✅ 国外网络连接正常');
    } else {
      debugPrint('❌ 国外网络连接异常，如果只有国外连接异常可能是正常的');
    }
    
    if (!kIsWeb && Platform.isIOS && !baiduResult['connected'] && !tencentResult['connected']) {
      debugPrint('\n⚠️ iOS设备网络问题排查建议:');
      debugPrint('1. 请确保应用有网络访问权限');
      debugPrint('2. 检查是否启用了VPN或代理');
      debugPrint('3. 尝试重启设备或重置网络设置');
      debugPrint('4. 确认Info.plist中已添加ATS例外配置');
    }
  } catch (e) {
    debugPrint('网络检查过程中发生异常: $e');
  }
  
  debugPrint('==================== 网络连接诊断结束 ====================');
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
      debugPrint('创建应用临时目录: ${tmpDir.path}');
      tmpDir.createSync(recursive: true);
    }
    
    // 输出目录信息用于调试
    debugPrint('应用文档目录: ${appDir.path}');
    debugPrint('应用临时目录: ${tmpDir.path}');
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
          // 等待UI主题初始化完成，避免竞态条件
          if (!uiThemeProvider.isInitialized) {
            return MaterialApp(
              title: 'NipaPlay',
              debugShowCheckedModeBanner: false,
              home: const SplashScreen(), // 显示启动屏幕
              builder: (context, appChild) {
                return Stack(
                  children: [
                    appChild!,
                    if (_isDragging) const DragDropOverlay(),
                  ],
                );
              },
            );
          }
          
          // 根据UI主题选择使用哪套应用框架
          if (uiThemeProvider.isFluentUITheme && (globals.isDesktop || globals.isTablet)) {
            // 桌面端使用 Fluent UI
            return fluent.FluentApp(
              title: 'NipaPlay',
              debugShowCheckedModeBanner: false,
              theme: fluent.FluentThemeData.dark(),
              navigatorKey: navigatorKey,
              home: FluentMainPage(launchFilePath: widget.launchFilePath),
              builder: (context, appChild) {
                return Stack(
                  children: [
                    appChild!, // The app's content
                    if (_isDragging) const DragDropOverlay(),
                  ],
                );
              },
            );
          } else {
            // 默认使用 Material Design
            return MaterialApp(
              title: 'NipaPlay',
              debugShowCheckedModeBanner: false,
              color: Colors.transparent,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeNotifier.themeMode,
              navigatorKey: navigatorKey,
              home: MainPage(launchFilePath: widget.launchFilePath),
              builder: (context, appChild) {
                return Stack(
                  children: [
                    appChild!, // The app's content
                    if (_isDragging) const DragDropOverlay(),
                  ],
                );
              },
            );
          }
        },
      ),
    );
  }

  void _handleDroppedFile(String filePath) async {
    try {
      debugPrint('[DragDrop] Handling dropped file: $filePath');
      
      // 检查是否存在历史记录
      WatchHistoryItem? historyItem = await WatchHistoryManager.getHistoryItem(filePath);

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
  final List<Widget> pages = [
    const PlayVideoPage(),
    const AnimePage(),
    const NewSeriesPage(),
    const SettingsPage(),
  ];

  MainPage({super.key, this.launchFilePath});

  @override
  // ignore: library_private_types_in_public_api
  MainPageState createState() => MainPageState();
}

class MainPageState extends State<MainPage> with SingleTickerProviderStateMixin, WindowListener {
  bool isMaximized = false;
  TabController? globalTabController;
  bool _showSplash = true;

  // 用于热键管理
  bool _hotkeysAreRegistered = false;
  VideoPlayerState? _videoPlayerState;

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
      if (globalTabController != null) {
        debugPrint('[MainPageState] globalTabController可用，当前索引: ${globalTabController!.index}');
        if (globalTabController!.index != index) {
          try {
            debugPrint('[MainPageState] 尝试切换到标签: $index');
            globalTabController!.animateTo(index);
            debugPrint('[MainPageState] 成功调用animateTo($index)');
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
      _tabChangeNotifier?.clear();
    } else {
      debugPrint('[MainPageState] targetTabIndex为空，不进行任何操作');
    }
  }

  void _manageHotkeys() {
    final videoState = _videoPlayerState;
    if (videoState == null || !mounted) return;

    final tabIndex = globalTabController?.index ?? -1;
    final shouldBeRegistered = tabIndex == 0 && videoState.hasVideo;

    if (shouldBeRegistered && !_hotkeysAreRegistered) {
      HotkeyService().registerHotkeys();
      _hotkeysAreRegistered = true;
    } else if (!shouldBeRegistered && _hotkeysAreRegistered) {
      HotkeyService().unregisterHotkeys();
      _hotkeysAreRegistered = false;
    }
  }

  void _onTabChange() {
    if (globalTabController != null) {
      debugPrint('[MainPageState] globalTabController listener: index=${globalTabController!.index}, previousIndex=${globalTabController!.previousIndex}, indexIsChanging=${globalTabController!.indexIsChanging}, animationValue=${globalTabController!.animation?.value.toStringAsFixed(2)}');
    }
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
    
    if (mounted) {
      globalTabController = TabController(
        length: 4,
        vsync: this,
        initialIndex: _defaultPageIndex,
      );
      debugPrint('[MainPageState] TabController initialized with index: $_defaultPageIndex');
    }
  }

  void _initializeListeners() {
    globalTabController?.addListener(_onTabChange);
    debugPrint('[MainPageState] initState: globalTabController listener ADDED.');

    if (globals.winLinDesktop) {
      windowManager.addListener(this);
    }
  }

  void _postFrameCallbacks() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.launchFilePath != null) {
        _handleLaunchFile(widget.launchFilePath!);
      }

      if (globals.winLinDesktop) {
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
    debugPrint('[MainPage] 初始化快捷键提示管理器');
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
    try {
      debugPrint('[FileAssociation] 处理启动文件: $filePath');
      
      // 检查是否存在历史记录
      WatchHistoryItem? historyItem = await WatchHistoryManager.getHistoryItem(filePath);

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
      
      debugPrint('[FileAssociation] 启动文件已提交给PlaybackService');
    } catch (e) {
      debugPrint('[FileAssociation] 启动文件播放失败: $e');
      if (mounted) {
        BlurSnackBar.show(context, '无法播放启动文件: $e');
      }
    }
  }

  // 检查窗口是否已最大化
  Future<void> _checkWindowMaximizedState() async {
    if (globals.winLinDesktop) {
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
    _tabChangeNotifier?.removeListener(_onTabChangeRequested); // Temporarily remove
    globalTabController?.removeListener(_onTabChange);
    _videoPlayerState?.removeListener(_manageHotkeys);
    globalTabController?.dispose();
    if (globals.winLinDesktop) {
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
    if (globals.winLinDesktop) {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      // 状态更新由windowManager的事件监听器处理
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
          right: globals.winLinDesktop ? 120 : 0,
          child: SizedBox(
            height: 40,
            child: GestureDetector(
              onDoubleTap: _toggleWindowSize,
              onPanStart: (details) async {
                if (globals.winLinDesktop) {
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
            if (!globals.winLinDesktop || !shouldShowAppBar) {
              return const SizedBox.shrink();
            }
            return Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 120,
                height: globals.isPhone && globals.isMobile ? 55 : 40,
                color: Colors.transparent,
                child: WindowControlButtons(
                  isMaximized: isMaximized,
                  onMinimize: _minimizeWindow,
                  onMaximizeRestore: _toggleWindowSize,
                  onClose: _closeWindow,
                ),
              ),
            );
          },
        ),
        
        // 系统资源监控显示
        Positioned(
          top: 4,
          right: globals.isPhone ? 10 : 130,
          child: const SystemResourceDisplay(),
        ),
      ],
    );
  }
}

// 检查自定义背景图片路径有效性
Future<void> _validateCustomBackgroundPath() async {
  final customPath = globals.customBackgroundPath;
  var defaultPath = (globals.isDesktop || globals.isTablet) ? 'assets/images/main_image.png' : 'assets/images/main_image_mobile.png';
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
    WatchHistoryItem? historyItem = await WatchHistoryManager.getHistoryItem(filePath);

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
      mainPageState.globalTabController!.animateTo(pageIndex);
      debugPrint('[Dart - _navigateToPage] 直接调用了globalTabController.animateTo($pageIndex)');
    } else {
      debugPrint('[Dart - _navigateToPage] globalTabController已经在索引$pageIndex，无需切换');
    }
  } else {
    debugPrint('[Dart - _navigateToPage] 无法找到MainPageState或globalTabController');
    // 如果直接访问失败，使用TabChangeNotifier作为备选方案
    Provider.of<TabChangeNotifier>(context, listen: false).changeTab(pageIndex);
    debugPrint('[Dart - _navigateToPage] 备选方案: 使用TabChangeNotifier请求切换到标签页$pageIndex');
  }
}
