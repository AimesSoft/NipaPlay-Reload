import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/downloads/unified_torrent_page_model.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/pages/torrent_download_page.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('subfont')
      ..addFont(rootBundle.load('assets/subfont.ttf'));
    await loader.load();
    await (FontLoader('packages/kmbal_ionicons/Ionicons')
          ..addFont(rootBundle
              .load('packages/kmbal_ionicons/assets/fonts/Ionicons.ttf')))
        .load();
  });

  for (final surface in [
    AppDisplaySurface.desktopTablet,
    AppDisplaySurface.television
  ]) {
    for (final brightness in Brightness.values) {
      for (final mode in UnifiedTorrentTaskViewMode.values) {
        testWidgets(
            '$surface $brightness $mode exposes streaming and seeding controls',
            (tester) async {
          tester.view.physicalSize = const Size(1200, 820);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final search = TextEditingController();
          addTearDown(search.dispose);
          var plays = 0;
          var pauses = 0;
          final tasks = [
            TorrentTask.fromMap({
              'id': 1,
              'name': '正在下载的视频',
              'output_folder': '/Downloads/Video',
              'stats': {
                'state': 'live',
                'finished': false,
                'progress_bytes': 400,
                'total_bytes': 1000
              }
            }),
            TorrentTask.fromMap({
              'id': 2,
              'name': '已经完成的视频',
              'output_folder': '/Downloads/Video2',
              'stats': {
                'state': 'live',
                'finished': true,
                'progress_bytes': 1000,
                'total_bytes': 1000
              }
            }),
          ];
          final items = tasks
              .map((task) => UnifiedTorrentTaskItemViewModel(
                    task: task,
                    scanSummary: null,
                    isAutoScanning: false,
                    isAutoScanned: false,
                    actions: [
                      UnifiedTorrentTaskActionViewModel(
                          action: UnifiedTorrentTaskAction.play,
                          label: '播放',
                          onPressed: () => plays++),
                      UnifiedTorrentTaskActionViewModel(
                          action: UnifiedTorrentTaskAction.toggle,
                          label: task.toggleLabel,
                          onPressed: () => pauses++),
                      for (final action in [
                        UnifiedTorrentTaskAction.openFolder,
                        UnifiedTorrentTaskAction.forget,
                        UnifiedTorrentTaskAction.delete
                      ])
                        UnifiedTorrentTaskActionViewModel(
                            action: action,
                            label: action.name,
                            onPressed: () {}),
                    ],
                  ))
              .toList();
          final data = UnifiedTorrentPageViewModel(
            isLoading: false,
            isBusy: false,
            tasks: tasks,
            visibleTasks: items,
            searchController: search,
            sort: UnifiedTorrentTaskSort.latest,
            viewMode: mode,
            onSearchChanged: (_) {},
            onClearSearch: () {},
            onSortChanged: (_) {},
            onToggleViewMode: () {},
            onRefresh: () {},
            onAddMagnet: () {},
            onPickTorrent: () {},
          );
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness, fontFamily: 'subfont'),
            home: RepaintBoundary(
                key: boundaryKey,
                child: Scaffold(
                    body: AppDisplaySurfaceScope(
                        surface: surface,
                        child: surface == AppDisplaySurface.television
                            ? TelevisionTorrentDownloadView(data: data)
                            : DesktopTorrentDownloadView(data: data)))),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final play = surface == AppDisplaySurface.television ||
                  mode == UnifiedTorrentTaskViewMode.cards
              ? find.text('播放')
              : find.byTooltip('播放');
          expect(play, findsNWidgets(2));
          await tester.tap(play.first);
          expect(plays, 1);
          final pause = surface == AppDisplaySurface.television ||
                  mode == UnifiedTorrentTaskViewMode.cards
              ? find.text('暂停做种')
              : find.byTooltip('暂停做种');
          await tester.tap(pause);
          expect(pauses, 1);
          await tester.pumpAndSettle();
          if (const bool.fromEnvironment('TORRENT_CAPTURE')) {
            final boundary = boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final directory = Directory('.codex_work/downloader-previews');
              await directory.create(recursive: true);
              await File(
                      '${directory.path}/${surface.name}-${brightness.name}-${mode.name}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'phone $brightness menu exposes playback and pause while seeding',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final search = TextEditingController();
      addTearDown(search.dispose);
      var paused = false;
      final task = TorrentTask.fromMap({
        'id': 1,
        'name': '已完成的视频',
        'output_folder': '/Downloads',
        'stats': {
          'state': 'live',
          'finished': true,
          'progress_bytes': 1000,
          'total_bytes': 1000
        }
      });
      final item = UnifiedTorrentTaskItemViewModel(
          task: task,
          scanSummary: null,
          isAutoScanning: false,
          isAutoScanned: false,
          actions: [
            UnifiedTorrentTaskActionViewModel(
                action: UnifiedTorrentTaskAction.play,
                label: '播放',
                onPressed: () {}),
            UnifiedTorrentTaskActionViewModel(
                action: UnifiedTorrentTaskAction.toggle,
                label: task.toggleLabel,
                onPressed: () => paused = true),
          ]);
      final data = UnifiedTorrentPageViewModel(
          isLoading: false,
          isBusy: false,
          tasks: [task],
          visibleTasks: [item],
          searchController: search,
          sort: UnifiedTorrentTaskSort.latest,
          viewMode: UnifiedTorrentTaskViewMode.cards,
          onSearchChanged: (_) {},
          onClearSearch: () {},
          onSortChanged: (_) {},
          onToggleViewMode: () {},
          onRefresh: () {},
          onAddMagnet: () {},
          onPickTorrent: () {});
      await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => BottomBarProvider(),
          child: MaterialApp(
              theme: ThemeData(brightness: brightness, fontFamily: 'subfont'),
              home: AppDisplaySurfaceScope(
                  surface: AppDisplaySurface.phone,
                  child: Scaffold(
                      body: CupertinoTorrentDownloadView(data: data))))));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(cupertino.CupertinoIcons.ellipsis));
      await tester.pumpAndSettle();
      expect(find.text('播放'), findsOneWidget);
      await tester.tap(find.text('暂停做种'));
      await tester.pumpAndSettle();
      expect(paused, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('preview can be cancelled while resolving', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final magnet = TextEditingController();
    addTearDown(magnet.dispose);
    SharedPreferences.setMockInitialValues({});
    final appearance = AppearanceSettingsProvider();
    addTearDown(appearance.dispose);
    var cancelled = false;
    final data = AddTorrentDialogViewModel(
      magnetController: magnet,
      downloadDirectory: '/Downloads',
      createFolderForTask: true,
      recentDirectories: const [],
      preview: null,
      error: null,
      isPreviewing: true,
      onMagnetChanged: (_) {},
      onChooseDirectory: () {},
      onSelectDirectory: (_) {},
      onRemoveRecentDirectory: (_) {},
      onCreateFolderChanged: (_) {},
      onPreview: () {},
      onConfirm: () {},
      onCancel: () => cancelled = true,
    );
    await tester.pumpWidget(MaterialApp(
        home: AppDisplaySurfaceScope(
      surface: AppDisplaySurface.desktopTablet,
      child: ChangeNotifierProvider.value(
          value: appearance,
          child: Scaffold(body: DesktopAddTorrentView(data: data))),
    )));
    await tester.pump();
    await tester.tap(find.text('取消'));
    expect(cancelled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
