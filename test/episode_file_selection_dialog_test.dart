import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/models/episode_file_candidate.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/episode_file_selection_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<EpisodeFileCandidate> _candidates({bool longPath = false}) => [
      '/media/first.mkv',
      'webdav://dav/%E7%AC%AC%E4%B8%80%E9%9B%86%20HD.mkv',
      'smb://smb/first.mkv',
    ]
        .map((path) => EpisodeFileCandidate(WatchHistoryItem(
              filePath: longPath
                  ? path.replaceFirst(
                      'first', 'very-long-directory/' * 12 + 'first')
                  : path,
              animeName: '测试番剧',
              episodeTitle: '第一集',
              animeId: 10,
              episodeId: 100,
              watchProgress: 0.5,
              lastPosition: 100,
              duration: 200,
              lastWatchTime: DateTime(2026, 9, 30),
            )))
        .toList();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(
    WidgetTester tester, {
    AppDisplaySurface surface = AppDisplaySurface.desktopTablet,
    Brightness brightness = Brightness.dark,
    double textScale = 1,
    bool longPath = false,
    Future<bool> Function(EpisodeFileCandidate)? onUnmatch,
    ValueChanged<EpisodeFileCandidate?>? onResult,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = surface == AppDisplaySurface.phone
        ? const Size(360, 780)
        : const Size(900, 650);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
        ChangeNotifierProvider(create: (_) => BottomBarProvider()),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => AppDisplaySurfaceScope(
          surface: surface,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () {
                        unawaited(EpisodeFileSelectionDialog.show(
                          context: context,
                          candidates: _candidates(longPath: longPath),
                          onUnmatch: onUnmatch ?? (_) async => true,
                        ).then((result) => onResult?.call(result)));
                      },
                      child: const Text('播放剧集'),
                    ))),
      ),
    ));
    await tester.tap(find.text('播放剧集'));
    await tester.pumpAndSettle();
  }

  for (final surface in [
    AppDisplaySurface.desktopTablet,
    AppDisplaySurface.phone
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'standard dialog fits $surface in $brightness with scaled long paths',
          (tester) async {
        await open(tester,
            surface: surface,
            brightness: brightness,
            textScale: 1.6,
            longPath: true);
        expect(tester.takeException(), isNull);
        expect(find.text('选择播放文件'), findsOneWidget);
        expect(find.text('1#'), findsOneWidget);
        expect(find.text('本地媒体库'), findsOneWidget);
        expect(tester.getCenter(find.byType(ListView)).dy,
            lessThan(tester.view.physicalSize.height));
        await tester.ensureVisible(find.byType(ListView));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('webdav://dav/第一集 HD.mkv'),
          200,
          scrollable: find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('webdav://dav/第一集 HD.mkv'), findsOneWidget);
        expect(
            find.byType(surface == AppDisplaySurface.phone
                ? CupertinoBottomSheet
                : NipaplayWindowScaffold),
            findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('clicking a file returns that exact encoded path',
      (tester) async {
    EpisodeFileCandidate? selected;
    await open(tester, onResult: (result) => selected = result);
    await tester.tap(find.text('webdav://dav/第一集 HD.mkv'));
    await tester.pumpAndSettle();
    expect(selected!.history.filePath,
        'webdav://dav/%E7%AC%AC%E4%B8%80%E9%9B%86%20HD.mkv');
  });

  testWidgets('right-side close unmatches without selecting or dismissing',
      (tester) async {
    var closed = false;
    final removed = <String>[];
    await open(
      tester,
      onResult: (_) => closed = true,
      onUnmatch: (item) async {
        removed.add(item.history.filePath);
        return true;
      },
    );
    await tester
        .tap(find.byKey(ValueKey('unmatch:${_candidates().first.identity}')));
    await tester.pumpAndSettle();
    expect(removed, ['/media/first.mkv']);
    expect(closed, isFalse);
    expect(find.text('本地媒体库'), findsNothing);
    expect(find.text('1#'), findsOneWidget);
    expect(find.text('WebDAV'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('failed unlink keeps the row and shows an error', (tester) async {
    await open(tester,
        onUnmatch: (_) async => throw StateError('write failed'));
    await tester
        .tap(find.byKey(ValueKey('unmatch:${_candidates().first.identity}')));
    await tester.pumpAndSettle();
    expect(find.text('1#'), findsOneWidget);
    expect(find.text('本地媒体库'), findsOneWidget);
    expect(find.text('解除匹配失败，请重试'), findsOneWidget);
  });

  testWidgets(
      'pending unlink prevents duplicate writes and accidental playback',
      (tester) async {
    final pending = Completer<bool>();
    var writes = 0;
    var closed = false;
    await open(
      tester,
      onResult: (_) => closed = true,
      onUnmatch: (_) {
        writes++;
        return pending.future;
      },
    );
    final unmatch =
        find.byKey(ValueKey('unmatch:${_candidates().first.identity}'));
    await tester.tap(unmatch);
    await tester.pump();
    await tester.tap(unmatch);
    await tester.tap(find.text('WebDAV'));
    await tester.pump();
    expect(writes, 1);
    expect(closed, isFalse);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('本地媒体库'), findsNothing);
  });

  testWidgets('unmatching every file leaves a cancellable empty state',
      (tester) async {
    await open(tester);
    for (final item in _candidates()) {
      await tester.tap(find.byKey(ValueKey('unmatch:${item.identity}')));
      await tester.pumpAndSettle();
    }
    expect(find.text('已解除所有文件的匹配'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('播放剧集'), findsOneWidget);
  });
}
