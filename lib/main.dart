import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_helper.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'package:flutter/foundation.dart'; // 导入这个包来使用kIsWeb

// 导入按钮组件
import 'utils/theme_provider.dart'; // 导入获取亮暗模式的文件

const double windowWidth = 1167.0;
const double windowHeight = 600.0;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 强制横屏，仅在 iOS、Android 或 Web 移动端
  if (!kIsWeb) {
    if (Platform.isIOS || Platform.isAndroid) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
      ]);
    }
  } else if (kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android)) {
    // 强制Web平台上的移动端横屏
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
  }
  // 判断是否为Web平台
  if (!kIsWeb) {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        title: "NipaPlay",
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setSize(const Size(windowWidth, windowHeight));
        await windowManager.setMinimumSize(const Size(windowWidth / 2, windowHeight / 2));
        await windowManager.show();
        await windowManager.setHasShadow(true);
        await windowManager.setAlignment(Alignment.center);
      });
    }
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const NipaPlayApp(),
    ),
  );
}

class NipaPlayApp extends StatefulWidget {
  const NipaPlayApp({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _NipaPlayAppState createState() => _NipaPlayAppState();
}

class _NipaPlayAppState extends State<NipaPlayApp> {
  @override
  Widget build(BuildContext context) {
    isDarkModeValue = getCurrentThemeMode(context, modeSwitch);
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      title: 'NipaPlay',
      theme: CupertinoThemeData(
        primaryColor: isDarkModeValue ? Colors.white : Colors.black,
        brightness: isDarkModeValue ? Brightness.dark : Brightness.light,
      ),
      home:  const Scaffold(
        body: Stack(
          children: [
            HomeScreen(),
          ],
        ),
      ),
    );
  }
}