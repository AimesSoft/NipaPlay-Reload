import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/services/manual_danmaku_matcher.dart';
import 'package:nipaplay/widgets/dandanplay_login_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<BuildContext> mount(WidgetTester tester, VoidCallback onTap) async {
    late BuildContext host;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        host = context;
        return Scaffold(
          body: Center(
              child: TextButton(
            onPressed: onTap,
            child: const Text('播放器操作'),
          )),
        );
      }),
    ));
    await tester.pumpAndSettle();
    return host;
  }

  testWidgets('login notice is non-modal, bottom-right, and auto-dismisses',
      (tester) async {
    var taps = 0;
    final context = await mount(tester, () => taps++);
    await DandanplayLoginNotice.showIfNeeded(context);
    await tester.pumpAndSettle();
    final notice = find.textContaining('弹弹play在线弹幕需要登录账号');
    expect(notice, findsOneWidget);
    expect(Navigator.of(context).canPop(), isFalse);
    expect(find.text('去登录'), findsNothing);
    final position = tester.getCenter(notice);
    expect(position.dx, greaterThan(400));
    expect(position.dy, greaterThan(300));
    await tester.tap(find.text('播放器操作'));
    expect(taps, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final preferences in <String, Map<String, Object>>{
    'skip matching': {SettingsKeys.skipDanmakuMatching: true},
    'local danmaku only': {SettingsKeys.danmakuAutoLoadStrategy: 'local'},
    'legacy skip matching': {SettingsKeys.danmakuAutoLoadStrategy: 'manual'},
    'third-party provider': {
      'dandanplay_server_url': 'https://third-party.example/danmaku',
    },
  }.entries) {
    testWidgets('${preferences.key}: no login notice', (tester) async {
      SharedPreferences.setMockInitialValues(preferences.value);
      final context = await mount(tester, () {});
      await DandanplayLoginNotice.showIfNeeded(context);
      await tester.pumpAndSettle();
      expect(find.textContaining('弹弹play在线弹幕需要登录账号'), findsNothing);
    });
  }

  testWidgets('logged-out manual matching returns without waiting for input',
      (tester) async {
    final context = await mount(tester, () {});
    expect(await ManualDanmakuMatcher.showMatchDialog(context), isNull);
    await tester.pumpAndSettle();
    expect(find.textContaining('弹弹play在线弹幕需要登录账号'), findsOneWidget);
    expect(Navigator.of(context).canPop(), isFalse);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
