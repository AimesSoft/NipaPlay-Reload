import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:nipaplay/pages/tab_labels.dart';
import 'package:nipaplay/utils/app_theme.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/widgets/custom_scaffold.dart';
import 'package:nipaplay/widgets/menu_button.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'pages/anime_page.dart';
import 'pages/settings_page.dart';
import 'pages/play_video_page.dart';
import 'pages/new_series_page.dart';
import 'utils/settings_storage.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'services/bangumi_service.dart';
import 'package:nipaplay/utils/keyboard_shortcuts.dart';
import 'services/dandanplay_service.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'models/watch_history_model.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:nipaplay/utils/network_checker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nipaplay/services/scan_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// 将通道定义为全局变量
const MethodChannel menuChannel = MethodChannel('custom_menu_channel');
bool _channelHandlerRegistered = false;
final GlobalKey<State<DefaultTabController>> tabControllerKey = GlobalKey<State<DefaultTabController>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    }
    
    // 默认返回空字符串
    return '';
  });

  // 创建应用所需的临时目录，解决macOS沙盒模式下的目录访问问题
  await _ensureTemporaryDirectoryExists();

  // 检查网络连接
  _checkNetworkConnection();

  // 注册 FVP

  // 并行执行初始化操作
  await Future.wait(<Future<dynamic>>[
    // 初始化弹弹play服务
    DandanplayService.initialize(),
    
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
    
    // 加载并保存默认快捷键设置
    Future(() async {
      await KeyboardShortcuts.loadShortcuts();
      // 如果没有保存的快捷键，保存默认值
      if (!await KeyboardShortcuts.hasSavedShortcuts()) {
        await KeyboardShortcuts.saveShortcuts();
      }
    }),
    
    // 清理过期的弹幕缓存
    DanmakuCacheManager.clearExpiredCache(),
    
    // 初始化 BangumiService
    BangumiService.instance.initialize(),
    
    // 初始化观看记录管理器
    WatchHistoryManager.initialize(),
  ]).then((results) {
    // 处理主题模式设置
    String savedThemeMode = results[1] as String;
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
        ],
        child: const NipaPlayApp(),
      ),
    );
    // 启动后全局加载一次观看记录
    Future.microtask(() {
      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        final context = navigator.overlay?.context;
        if (context != null) {
          Provider.of<WatchHistoryProvider>(context, listen: false).loadHistory();
        }
      }
    });
  });
}

// 检查网络连接
Future<void> _checkNetworkConnection() async {
  debugPrint('==================== 网络连接诊断开始 ====================');
  debugPrint('设备系统: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  debugPrint('设备类型: ${Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : Platform.isMacOS ? 'macOS' : '其他'}');
  
  // 检查代理设置
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
    
    if (Platform.isIOS && !baiduResult['connected'] && !tencentResult['connected']) {
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
    // 获取应用文档目录
    final docsDir = await getApplicationDocumentsDirectory();
    final appDir = Directory(path.join(docsDir.path));
    
    // 创建tmp目录路径
    final tmpDir = Directory(path.join(appDir.path, 'tmp'));
    
    // 确保tmp目录存在
    if (!tmpDir.existsSync()) {
      //debugPrint('创建应用临时目录: ${tmpDir.path}');
      tmpDir.createSync(recursive: true);
    }
    
    // 输出目录信息用于调试
    //debugPrint('应用文档目录: ${appDir.path}');
    //debugPrint('应用临时目录: ${tmpDir.path}');
  } catch (e) {
    //debugPrint('创建临时目录失败: $e');
  }
}

class NipaPlayApp extends StatelessWidget {
  const NipaPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        // 移除全局键盘快捷键注册，避免干扰文本输入
        return MaterialApp(
          title: 'NipaPlay',
          debugShowCheckedModeBanner: false,
          color: Colors.transparent,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeNotifier.themeMode,
          navigatorKey: navigatorKey,
          home: MainPage(),
        );
      },
    );
  }
}

class MainPage extends StatefulWidget {
  final List<Widget> pages = [
    const PlayVideoPage(),
    const AnimePage(),
    const NewSeriesPage(),
    const SettingsPage(),
  ];

  MainPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with SingleTickerProviderStateMixin {
  bool isMaximized = false;
  TabController? globalTabController;

  // TabChangeNotifier监听
  TabChangeNotifier? _tabChangeNotifier;
  void _onTabChangeRequested() {
    final index = _tabChangeNotifier?.targetTabIndex;
    if (index != null && globalTabController != null) {
      if (globalTabController!.index != index) {
        globalTabController!.animateTo(index);
      }
      _tabChangeNotifier?.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    globalTabController = TabController(length: widget.pages.length, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只添加一次监听
    _tabChangeNotifier ??= Provider.of<TabChangeNotifier>(context);
    _tabChangeNotifier?.removeListener(_onTabChangeRequested);
    _tabChangeNotifier?.addListener(_onTabChangeRequested);
  }

  @override
  void dispose() {
    _tabChangeNotifier?.removeListener(_onTabChangeRequested);
    globalTabController?.dispose();
    super.dispose();
  }

  void _toggleWindowSize() async {
    if (isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    setState(() {
      isMaximized = !isMaximized;
    });
  }

  void _minimizeWindow() async {
    await windowManager.minimize();
  }

  void _closeWindow() async {
    await windowManager.close();
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
        Positioned(
          top: 0,
          left: 0,
          right: globals.winLinDesktop ? 100 : 0,
          child: SizedBox(
            height: 30,
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
                width: 100,
                height: globals.isPhone && globals.isMobile ? 55 : 30,
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
      ],
    );
  }
}

// 检查自定义背景图片路径有效性
Future<void> _validateCustomBackgroundPath() async {
  final customPath = globals.customBackgroundPath;
  const defaultPath = 'assets/images/main_image.png';
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
  
  // 尝试获取上次目录
  String? lastDir;
  try {
    final prefs = await SharedPreferences.getInstance();
    lastDir = prefs.getString('last_video_dir');
    print('[Dart] 上次目录: $lastDir');
  } catch (e) {
    print('[Dart] 获取上次目录失败: $e');
  }
  
  // 选择文件
  try {
    print('[Dart] 打开文件选择器');
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mkv', 'avi', 'wmv', 'mov'],
      allowMultiple: false,
      initialDirectory: lastDir,
    );
    
    if (result == null || result.files.isEmpty) {
      print('[Dart] 用户取消了选择或未选择文件');
      return;
    }
    
    final filePath = result.files.single.path;
    if (filePath == null) {
      print('[Dart] 文件路径为空');
      return;
    }
    
    print('[Dart] 选择了文件: $filePath');
    final file = File(filePath);
    
    // 保存目录
    try {
      final prefs = await SharedPreferences.getInstance();
      final dir = file.parent.path;
      await prefs.setString('last_video_dir', dir);
      print('[Dart] 已保存目录: $dir');
    } catch (e) {
      print('[Dart] 保存目录失败: $e');
      // 继续执行，这不是关键错误
    }
    
    // 确保context还有效
    if (!context.mounted) {
      print('[Dart] 上下文已失效，无法初始化播放器');
      return;
    }
    
    // 1. 切换到视频播放Tab（PlayVideoPage，索引0）
    try {
      Provider.of<TabChangeNotifier>(context, listen: false).changeTab(0);
      print('[Dart] 已请求切换到视频播放Tab');
    } catch (e) {
      print('[Dart] 切换Tab时出错: $e');
      // 继续执行，不影响后续播放器初始化
    }
    
    // 2. 初始化播放器
    try {
      print('[Dart] 开始初始化播放器');
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      await videoState.initializePlayer(file.path);
      print('[Dart] 播放器初始化成功');
    } catch (e) {
      print('[Dart] 播放器初始化失败: $e');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法播放视频: $e')),
        );
      }
    }
  } catch (e) {
    print('[Dart] 文件选择过程出错: $e');
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件时出错: $e')),
      );
    }
  }
}