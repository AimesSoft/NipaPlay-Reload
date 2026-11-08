import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/pages/activity_page.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

import 'player_test_support.dart';

/// 动态 → 在追: what Nipa follows on each device, her own sentence for it,
/// when she last looked and what came of it; paused ones after the rest.
void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nipaplay/next_chrome'),
            (call) async => {'leading': 0.0, 'fullScreen': false});
    NextShell.debugServices = (_) => playerTestServices();
    playerTestSubscriptions
      ..clear()
      ..addAll([
        const UiSubscription(
            id: 'paused',
            title: '迷宫饭',
            state: UiSubscriptionState.paused,
            deviceId: 'here'),
        UiSubscription(
            id: 'frieren',
            title: '葬送的芙莉莲',
            state: UiSubscriptionState.active,
            deviceId: 'workstation',
            device: '工作站',
            note: '简中内嵌 1080p，每周日检查',
            lastCheckedAt: DateTime.now().subtract(const Duration(minutes: 5)),
            downloads: const [
              UiSubscriptionDownload(jobId: 'j', title: '葬送的芙莉莲', episode: '13')
            ]),
      ]);
  });
  tearDown(() {
    NextShell.debugServices = null;
    playerTestSubscriptions.clear();
  });

  testWidgets('following lists what Nipa watches for, where and how it went',
      (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.text('动态').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('在追'));
    await tester.pump(const Duration(milliseconds: 400));
    // The data arrives after the frame that listened for it.
    await tester.pump();

    expect(find.text('简中内嵌 1080p，每周日检查'), findsOneWidget);
    expect(find.text('5 分钟前检查 · 第 13 集已下载'), findsOneWidget);
    expect(find.text('在 工作站 上'), findsOneWidget);
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget, reason: 'a paused one resumes');
    // What runs now comes before what is paused.
    expect(tester.getTopLeft(find.text('葬送的芙莉莲')).dy,
        lessThan(tester.getTopLeft(find.text('迷宫饭')).dy));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('the tab sits after what runs now', () {
    expect(ActivityTab.values.indexOf(ActivityTab.following), 1);
  });
}
