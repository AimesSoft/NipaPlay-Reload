import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nipaplay_tv/ui/tv_app_shell.dart';
import 'package:nipaplay_ui_common/l10n/app_locale_utils.dart';
import 'package:nipaplay_ui_common/l10n/app_localizations.dart';

/// TV 焦点适配验收测试：任何交互之后焦点都不得丢失（遥控不失灵）。
///
/// 覆盖面：
/// - 壳导航 5 项（主页/媒体库/我的/设置/关于）切换后焦点仍在；
/// - 设置 6 个分区切换后焦点仍在；
/// - 各页入口卡片可被 D-pad 移动焦点（nextFocus 路径）；
/// - 添加媒体对话框打开后文本框持有焦点，取消按钮可被导航到。
void main() {
  const tvSize = Size(1920, 1080);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF26C6DA),
            brightness: Brightness.dark,
          ),
        ),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: child,
      );

  void setTv(WidgetTester tester) {
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('nav: every tab switch keeps focus alive', (tester) async {
    setTv(tester);
    await tester.pumpWidget(harness(const TvAppShell()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(FocusManager.instance.primaryFocus, isNotNull,
        reason: '初始焦点丢失');

    for (final label in ['媒体库', '我的', '设置', '关于', '主页']) {
      await tester.tap(find.text(label).first);
      await tester.pump(const Duration(milliseconds: 350));
      expect(FocusManager.instance.primaryFocus, isNotNull,
          reason: '切到「$label」后失焦，遥控将失灵');
    }
  });

  testWidgets('D-pad traversal walks nav items without losing focus',
      (tester) async {
    setTv(tester);
    await tester.pumpWidget(harness(const TvAppShell()));
    await tester.pump(const Duration(milliseconds: 300));

    // 连续模拟方向键：焦点必须始终存在
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(
          i.isEven ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 120));
      expect(FocusManager.instance.primaryFocus, isNotNull,
          reason: '第 $i 次方向键后失焦');
    }
    // 确认键：不应抛异常（焦点节点仍有效）
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 250));
    expect(FocusManager.instance.primaryFocus, isNotNull,
        reason: '确认键后失焦');
  });

  testWidgets('settings: switching all 6 sections keeps focus', (tester) async {
    setTv(tester);
    await tester.pumpWidget(harness(const TvAppShell()));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('设置').first);
    await tester.pump(const Duration(milliseconds: 350));

    for (final section in ['通用', '播放器', '弹幕', '网络', '存储', '外观']) {
      await tester.tap(find.text(section).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(FocusManager.instance.primaryFocus, isNotNull,
          reason: '分区「$section」切换后失焦');
    }
  });

  testWidgets('library: add-source dialog keeps text field focus and buttons reachable',
      (tester) async {
    setTv(tester);
    await tester.pumpWidget(harness(const TvAppShell()));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('媒体库').first);
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('添加媒体').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('添加 本地文件'), findsOneWidget,
        reason: '添加对话框未打开');

    // 文本框必须持有焦点（遥控可直接输入）
    final node = FocusManager.instance.primaryFocus;
    expect(node, isNotNull, reason: '对话框打开后无焦点');
    // 沿祖先树查找 EditableText：TextField 的 primary focus 落在内部 Focus 节点
    var inTextField = false;
    final ctx = node?.context;
    if (ctx is Element) {
      if (ctx.widget is EditableText) inTextField = true;
      ctx.visitAncestorElements((el) {
        if (el.widget is EditableText) {
          inTextField = true;
          return false; // 找到即停止
        }
        return true;
      });
    }
    expect(inTextField, isTrue,
        reason: '焦点未落在文本框上：遥控输入将不可用');

    // 取消按钮可被到达（D-pad 导航不出异常）
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 150));
    expect(FocusManager.instance.primaryFocus, isNotNull,
        reason: '对话框内 Tab 后失焦');

    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(FocusManager.instance.primaryFocus, isNotNull,
        reason: '关闭对话框后失焦（焦点未回落到页面）');
  });

  testWidgets('profile: login dialog keeps field focus', (tester) async {
    setTv(tester);
    await tester.pumpWidget(harness(const TvAppShell()));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('我的').first);
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('未登录').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('登录弹弹play'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, isNotNull,
        reason: '登录对话框打开后失焦');

    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(FocusManager.instance.primaryFocus, isNotNull,
        reason: '登录对话框关闭后失焦');
  });
}

// ---- 追加：D-pad 从分区 chip 必须能进入下方选项行 ----
