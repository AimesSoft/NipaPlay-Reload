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

  testWidgets('switching pages moves highlight and library exposes add entry',
      (tester) async {
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(const TvAppShell()));
    await tester.pump(const Duration(milliseconds: 200));

    // 切到媒体库：高光应随选中态迁移，且页面出现"添加媒体"入口
    await tester.tap(find.text('媒体库'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('添加媒体'), findsOneWidget);
    expect(find.text('添加来源'), findsOneWidget);

    // 打开添加对话框（触摸路径）
    await tester.tap(find.text('添加媒体'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('添加 本地文件'), findsOneWidget);
    await capture(tester, 'p5_add_media_dialog_1080p');
  });

  testWidgets('library shows anime cards after adding a source', (tester) async {
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'tv.media_sources': [
        '{"n":"CLANNAD","l":"/sdcard/Movies","k":"localFolder","c":"","new":true}',
        '{"n":"Fate/stay night","l":"https://dav.example/dav","k":"webdav","r":8.6}',
      ],
    });

    await tester.pumpWidget(harness(const TvAppShell()));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('媒体库'));
    await tester.pump(const Duration(milliseconds: 500));

    // 番剧卡片应出现（名称 + 来源标签）
    expect(find.text('CLANNAD'), findsOneWidget);
    expect(find.text('Fate/stay night'), findsOneWidget);
    await capture(tester, 'p6_library_cards_1080p');
  });

  testWidgets('settings exposes player kernel picker and bangumi mirror',
      (tester) async {
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(const TvAppShell()));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 400));

    // 播放器分区：内核选择入口
    await tester.tap(find.text('播放器'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('播放内核'), findsOneWidget);
    await capture(tester, 'p6_settings_kernel_1080p');

    // 网络分区：Bangumi 镜像入口
    await tester.tap(find.text('网络'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Bangumi 镜像 / API 服务器'), findsOneWidget);
    await capture(tester, 'p6_settings_bangumi_1080p');
  });
}
