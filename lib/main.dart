import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:nipaplay/utils/keyboard_mappings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 注册 FVP
  fvp.registerWith(options: {
   'global': {
        'log': 'off', // off, error, warning, info, debug, all(default)
      }
  });

  // 并行执行初始化操作
  await Future.wait([
    // 初始化弹弹play服务
    DandanplayService.initialize(),
    
    // 加载设置
    Future.wait([
      SettingsStorage.loadString('themeMode', defaultValue: 'system'),
      SettingsStorage.loadDouble('blurPower'),
      SettingsStorage.loadString('backgroundImageMode'),
      SettingsStorage.loadString('customBackgroundPath'),
    ]).then((results) {
      globals.blurPower = results[1] as double;
      globals.backgroundImageMode = results[2] as String;
      globals.customBackgroundPath = results[3] as String;
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
        ],
        child: const NipaPlayApp(),
      ),
    );
  });
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
          home: MainPage(),
        );
      },
    );
  }
}

class MainPage extends StatefulWidget {
  final List<Widget> pages = [
    const PlayVideoPage(),
    AnimePage(),
    const NewSeriesPage(),
    const SettingsPage(),
  ];

  MainPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool isMaximized = false;

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