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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 注册 FVP
  fvp.registerWith(options: {
  });

  if (globals.isDesktop) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: "NipaPlay",
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setMinimumSize(const Size(600, 400));
      await windowManager.maximize();
      await windowManager.show();
    });
  }

  // 加载快捷键设置
  await KeyboardShortcuts.loadShortcuts();

  String savedThemeMode =
      await SettingsStorage.loadString('themeMode', defaultValue: 'system');
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

  // 加载模糊度
  final double blurPower = await SettingsStorage.loadDouble('blurPower');
  globals.blurPower = blurPower;

  // 加载背景图像模式
  final String backgroundImageMode = await SettingsStorage.loadString('backgroundImageMode');
  globals.backgroundImageMode = backgroundImageMode;

  // 加载自定义背景图片路径
  final String customBackgroundPath = await SettingsStorage.loadString('customBackgroundPath');
  globals.customBackgroundPath = customBackgroundPath;

  // 初始化 BangumiService
  await BangumiService.instance.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VideoPlayerState()),
        ChangeNotifierProvider(
          create: (context) => ThemeNotifier(
            initialThemeMode: initialThemeMode, 
            initialBlurPower: blurPower,
            initialBackgroundImageMode: backgroundImageMode,
            initialCustomBackgroundPath: customBackgroundPath,
          ),
        ),
      ],
      child: const NipaPlayApp(),
    ),
  );
}

class NipaPlayApp extends StatelessWidget {
  const NipaPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
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
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return Stack(
          children: [
            CustomScaffold(
                pages: widget.pages, tabPage: createTabLabels(), pageIsHome: true),
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
            if (globals.winLinDesktop && videoState.shouldShowAppBar())
              Positioned(
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
              ),
          ],
        );
      },
    );
  }
}