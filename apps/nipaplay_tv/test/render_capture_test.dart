import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay_tv/ui/tv_app_shell.dart';
import 'package:nipaplay_ui_common/l10n/app_locale_utils.dart';
import 'package:nipaplay_ui_common/l10n/app_localizations.dart';

/// 离线渲染取证：在 1080p 电视尺寸下渲染壳与设置页并导出 PNG。
/// 不依赖真机/模拟器；播放页因含持续动画的弹幕 Ticker，不在此断言（真机验证）。
void main() {
  const tvSize = Size(1920, 1080);

  setUp(() {
    // 测试环境无插件实现：给 core 的 SettingsStorage 提供内存态 prefs。
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(Widget child) => RepaintBoundary(
        key: const ValueKey('capture-boundary'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF26C6DA),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF101418),
          ),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: child,
        ),
      );

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture-boundary')),
    );
    // toImage 依赖真实异步；必须放在 runAsync 里，否则测试会一直等不到完成。
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/screenshots');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File('${dir.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('TV shell renders at 1080p', (tester) async {
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(const TvAppShell()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('NipaPlay'), findsWidgets);
    await capture(tester, 'p4_shell_1080p');
  });

  testWidgets('TV settings tiles render at 1080p (tap path proves touch wired)',
      (tester) async {
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(const TvAppShell()));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('通用'), findsWidgets);
    await capture(tester, 'p4_settings_1080p');
  });
}
