import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/concurrent_video_processor.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('startup restores credentials without renewing an expired token',
      () async {
    SharedPreferences.setMockInitialValues({
      'dandanplay_token': 'cached-token',
      'dandanplay_logged_in': true,
      'last_token_renew_time': 0,
    });
    await DandanplayService.initialize(renewToken: false);
    expect(DandanplayService.authorizationHeaders['Authorization'],
        'Bearer cached-token');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('last_token_renew_time'), 0);
  });

  test('startup scan is explicit, waits for playback and runs only once',
      () async {
    var calls = 0;
    final ready = Completer<void>();
    final scan = ScanService.forTesting(
        completedFilesProcessor: (_) async => [],
        startupAction: () async {
          calls++;
        });
    addTearDown(scan.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
    final first = scan.startStartupRefresh(playbackReady: ready.future);
    final second = scan.startStartupRefresh();
    expect(calls, 0);
    ready.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
  });

  test('disposed scanner does not start pending startup work', () async {
    var calls = 0;
    final ready = Completer<void>();
    final scan = ScanService.forTesting(
        completedFilesProcessor: (_) async => [],
        startupAction: () async {
          calls++;
        });
    final task = scan.startStartupRefresh(playbackReady: ready.future);
    scan.dispose();
    ready.complete();
    await task;
    expect(calls, 0);
  });

  test('scan progress is coalesced but completion is immediate', () async {
    final completed = Completer<List<VideoProcessResult>>();
    final scan = ScanService.forTesting(
        completedFilesProcessor: (_) => completed.future);
    addTearDown(scan.dispose);
    var notifications = 0;
    scan.addListener(() => notifications++);
    final task = scan.scanCompletedFiles(['a.mp4'], folderPath: '/tmp');
    final atStart = notifications;
    for (var i = 0; i < 500; i++) {
      scan.updateScanMessage('progress $i');
    }
    expect(notifications, atStart);
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(notifications, atStart + 1);
    completed.complete([]);
    await task;
    expect(scan.isScanning, isFalse);
    expect(scan.scanJustCompleted, isTrue);
    expect(notifications, greaterThan(atStart + 1));
  });

  testWidgets('unvisited tabs stay unmounted and visited tabs keep their state',
      (tester) async {
    final counts = [0, 0, 0];
    final children =
        List.generate(3, (i) => _CountedPage(onInit: () => counts[i]++));
    Future<void> show(int index) => tester.pumpWidget(MaterialApp(
            home: SwitchableView(
          currentIndex: index,
          keepAlive: true,
          preloadIndices: const [],
          children: children,
        )));
    await show(0);
    await tester.pumpAndSettle();
    expect(counts, [1, 0, 0]);
    await show(2);
    await tester.pumpAndSettle();
    expect(counts, [1, 0, 1]);
    await show(0);
    await tester.pumpAndSettle();
    expect(counts, [1, 0, 1]);
  });
}

class _CountedPage extends StatefulWidget {
  const _CountedPage({required this.onInit});
  final VoidCallback onInit;
  @override
  State<_CountedPage> createState() => _CountedPageState();
}

class _CountedPageState extends State<_CountedPage> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
