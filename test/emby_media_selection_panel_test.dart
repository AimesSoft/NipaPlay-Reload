import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/services/emby_media_selection_controller.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/widgets/emby_media_source_selector.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('panel shows loading, retryable error, source summaries and tabs',
      (tester) async {
    final controller = _FakeSelectionController(
      state: EmbyMediaSelectionState(isLoading: true),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_panelHarness(controller));
    expect(find.text('正在加载版本信息…'), findsOneWidget);

    controller.setState(
      EmbyMediaSelectionState(
        error: StateError('暂时无法加载版本'),
      ),
    );
    await tester.pump();
    expect(find.textContaining('暂时无法加载版本'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(controller.loadCalls, [true]);

    controller.setState(_loadedState());
    await tester.pump();
    expect(find.text('WEB-DL.Baha'), findsOneWidget);
    expect(find.text('1080p · 1.37 GB · 2.2 Mbps'), findsOneWidget);
    expect(find.text('概览'), findsOneWidget);
    expect(find.text('音轨'), findsOneWidget);
    expect(find.text('字幕'), findsOneWidget);
  });

  testWidgets('panel selects source, audio and subtitle without playing',
      (tester) async {
    final controller = _FakeSelectionController(state: _loadedState());
    addTearDown(controller.dispose);

    await tester.pumpWidget(_panelHarness(controller));
    await tester.tap(find.text('WEB-DL.LoliHouse'));
    await tester.pump();
    expect(controller.selectedSourceIds, ['source-loli']);

    await tester.tap(find.text('音轨'));
    await tester.pump();
    await tester.tap(find.text('英语 · E-AC-3 · 5.1ch'));
    expect(controller.selectedAudio.length, 1);
    expect(controller.selectedSubtitle, isEmpty);

    await tester.tap(find.text('字幕'));
    await tester.pump();
    await tester.tap(find.text('繁體中文 · ASS'));
    expect(controller.selectedSubtitle.length, 1);
  });

  testWidgets('switching source replaces track candidates from the old source',
      (tester) async {
    final controller = _FakeSelectionController(state: _loadedState());
    addTearDown(controller.dispose);

    await tester.pumpWidget(_panelHarness(controller));
    await tester.tap(find.text('WEB-DL.LoliHouse'));
    await tester.pump();
    await tester.tap(find.text('\u97f3\u8f68'));
    await tester.pump();

    expect(find.text('\u65e5\u8bed · AAC · 2.0ch'), findsNothing);
    expect(find.text('\u82f1\u8bed · E-AC-3 · 5.1ch'), findsOneWidget);
    await tester.tap(find.text('\u82f1\u8bed · E-AC-3 · 5.1ch'));
    expect(controller.selectedAudio.single.fingerprint?.language, 'eng');

    await tester.tap(find.text('\u5b57\u5e55'));
    await tester.pump();
    expect(find.text('\u7b80\u4f53\u4e2d\u6587 · ASS'), findsNothing);
    expect(find.text('\u7e41\u9ad4\u4e2d\u6587 · ASS'), findsOneWidget);
    await tester.tap(find.text('\u7e41\u9ad4\u4e2d\u6587 · ASS'));
    expect(controller.selectedSubtitle.single.fingerprint?.language, 'zho');
  });

  testWidgets('cancel closes without saving', (tester) async {
    final controller = _FakeSelectionController(state: _loadedState());
    addTearDown(controller.dispose);
    final closeResults = <bool>[];

    await tester.pumpWidget(
      _panelHarness(controller, onClose: closeResults.add),
    );
    await tester.tap(find.text('取消'));

    expect(controller.cancelCalls, 1);
    expect(controller.applyCalls, 0);
    expect(closeResults, [false]);
  });

  testWidgets('apply saves and closes without starting playback',
      (tester) async {
    final controller = _FakeSelectionController(state: _loadedState());
    addTearDown(controller.dispose);
    final closeResults = <bool>[];

    await tester.pumpWidget(
      _panelHarness(controller, onClose: closeResults.add),
    );
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(controller.applyCalls, 1);
    expect(controller.cancelCalls, 0);
    expect(closeResults, [true]);
  });

  testWidgets('failed and throwing apply keep the panel open with an error',
      (tester) async {
    final controller = _FakeSelectionController(
      state: _loadedState(),
      applyResult: false,
      applyError: StateError('无法保存 Emby 媒体偏好：账号标识不可用'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_panelHarness(controller));
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('版本与轨道'), findsOneWidget);
    expect(find.textContaining('账号标识不可用'), findsOneWidget);

    controller.throwOnApply = true;
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('版本与轨道'), findsOneWidget);
    expect(find.textContaining('账号标识不可用'), findsOneWidget);
  });

  testWidgets(
      'apply with unavailable account identity stays open and shows error',
      (tester) async {
    final controller = _FakeSelectionController(
      state: EmbyMediaSelectionState(
        sources: _loadedState().sources,
        selectedSourceId: 'source-baha',
        canPersist: false,
      ),
      applyResult: false,
      applyError: StateError('无法保存 Emby 媒体偏好：账号标识不可用'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_panelHarness(controller));
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(controller.applyCalls, 1);
    expect(find.text('版本与轨道'), findsOneWidget);
    expect(find.textContaining('账号标识不可用'), findsOneWidget);
  });

  testWidgets('showEmbyMediaSelection uses a Windows dialog wrapper',
      (tester) async {
    final controller = _FakeSelectionController(state: _loadedState());
    addTearDown(controller.dispose);

    await tester.pumpWidget(_launcherHarness(
      controller: controller,
      useCupertino: false,
      surface: AppDisplaySurface.desktopTablet,
    ));
    await tester.tap(find.byKey(const ValueKey<String>('open-selector')));
    await tester.pumpAndSettle();

    expect(find.byType(NipaplayWindowScaffold), findsOneWidget);
    expect(find.byType(EmbyMediaSelectionPanel), findsOneWidget);
  });

  testWidgets('show result is true only for apply and false for cancel',
      (tester) async {
    final applyController = _FakeSelectionController(state: _loadedState());
    addTearDown(applyController.dispose);
    final applyResults = <bool?>[];
    await tester.pumpWidget(_launcherHarness(
      controller: applyController,
      useCupertino: false,
      surface: AppDisplaySurface.desktopTablet,
      onResult: applyResults.add,
    ));
    await tester.tap(find.byKey(const ValueKey<String>('open-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(applyResults, [true]);
    expect(applyController.cancelCalls, 0);

    final cancelController = _FakeSelectionController(state: _loadedState());
    addTearDown(cancelController.dispose);
    final cancelResults = <bool?>[];
    await tester.pumpWidget(_launcherHarness(
      controller: cancelController,
      useCupertino: false,
      surface: AppDisplaySurface.desktopTablet,
      onResult: cancelResults.add,
    ));
    await tester.tap(find.byKey(const ValueKey<String>('open-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(cancelResults, [false]);
    expect(cancelController.cancelCalls, 1);
  });

  testWidgets('Windows outer close returns false and cancels exactly once',
      (tester) async {
    final controller = _FakeSelectionController(state: _loadedState());
    addTearDown(controller.dispose);
    final results = <bool?>[];
    await tester.pumpWidget(_launcherHarness(
      controller: controller,
      useCupertino: false,
      surface: AppDisplaySurface.desktopTablet,
      onResult: results.add,
    ));
    await tester.tap(find.byKey(const ValueKey<String>('open-selector')));
    await tester.pumpAndSettle();

    tester
        .widget<NipaplayWindowScaffold>(find.byType(NipaplayWindowScaffold))
        .onClose!
        .call();
    await tester.pumpAndSettle();

    expect(results, [false]);
    expect(controller.cancelCalls, 1);
  });

  testWidgets('showEmbyMediaSelection uses an iOS sheet wrapper',
      (tester) async {
    final controller = _FakeSelectionController(state: _loadedState());
    addTearDown(controller.dispose);

    await tester.pumpWidget(_launcherHarness(
      controller: controller,
      useCupertino: true,
      surface: AppDisplaySurface.phone,
    ));
    await tester.tap(find.byKey(const ValueKey<String>('open-selector')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoBottomSheet), findsOneWidget);
    expect(find.byType(EmbyMediaSelectionPanel), findsOneWidget);
    expect(find.text('\u7248\u672c\u4e0e\u8f68\u9053'), findsOneWidget);

    final sheet = find.byType(CupertinoBottomSheet);
    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getSize(sheet).height,
        greaterThanOrEqualTo(viewport.height * 0.9));

    final scrollable = find.descendant(
      of: sheet,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsWidgets);
    final actions =
        find.byKey(const ValueKey<String>('emby-media-selection-actions'));
    expect(actions, findsOneWidget);
    final actionsBeforeScroll = tester.getRect(actions);
    await tester.drag(scrollable.first, const Offset(0, -300));
    await tester.pump();
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(tester.getRect(actions), actionsBeforeScroll);
  });

  for (final useCupertino in <bool>[false, true]) {
    testWidgets(
        'saving blocks ${useCupertino ? 'iOS' : 'Windows'} close and system back',
        (tester) async {
      final applyGate = Completer<bool>();
      final controller = _FakeSelectionController(
        state: _loadedState(),
        applyGate: applyGate,
      );
      addTearDown(controller.dispose);
      final results = <bool?>[];
      await tester.pumpWidget(_launcherHarness(
        controller: controller,
        useCupertino: useCupertino,
        surface: useCupertino
            ? AppDisplaySurface.phone
            : AppDisplaySurface.desktopTablet,
        onResult: results.add,
      ));
      await tester.tap(find.byKey(const ValueKey<String>('open-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用'));
      await tester.pump();
      expect(controller.state.isSaving, isTrue);

      if (useCupertino) {
        tester
            .widget<CupertinoBottomSheet>(find.byType(CupertinoBottomSheet))
            .onClose!
            .call();
      } else {
        tester
            .widget<NipaplayWindowScaffold>(
              find.byType(NipaplayWindowScaffold),
            )
            .onClose!
            .call();
      }
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.byType(EmbyMediaSelectionPanel), findsOneWidget);
      expect(results, isEmpty);
      expect(controller.cancelCalls, 0);

      applyGate.complete(false);
      await tester.pumpAndSettle();
      expect(controller.state.isSaving, isFalse);

      if (useCupertino) {
        await tester.binding.handlePopRoute();
      } else {
        tester
            .widget<NipaplayWindowScaffold>(
              find.byType(NipaplayWindowScaffold),
            )
            .onClose!
            .call();
      }
      await tester.pumpAndSettle();

      expect(results, [false]);
      expect(controller.cancelCalls, 1);
    });
  }
}

Widget _panelHarness(
  _FakeSelectionController controller, {
  ValueChanged<bool>? onClose,
}) =>
    MaterialApp(
      home: Scaffold(
        body: EmbyMediaSelectionPanel(
          controller: controller,
          onClose: onClose ?? (_) {},
        ),
      ),
    );

Widget _launcherHarness({
  required _FakeSelectionController controller,
  required bool useCupertino,
  required AppDisplaySurface surface,
  ValueChanged<bool?>? onResult,
}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppearanceSettingsProvider>(
          create: (_) => AppearanceSettingsProvider(),
        ),
        ChangeNotifierProvider<BottomBarProvider>(
          create: (_) => BottomBarProvider(),
        ),
      ],
      child: AppDisplaySurfaceScope(
        surface: surface,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const ValueKey<String>('open-selector'),
                onPressed: () => unawaited(
                  showEmbyMediaSelection(
                    context: context,
                    useCupertino: useCupertino,
                    controller: controller,
                  ).then((result) => onResult?.call(result)),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

EmbyMediaSelectionState _loadedState() => EmbyMediaSelectionState(
      sources: const [_baha, _loli],
      selectedSourceId: 'source-baha',
      audio: const EmbyTrackPreference.followDefault(),
      subtitle: const EmbyTrackPreference.followDefault(),
    );

const _baha = EmbyMediaSourceDescriptor(
  source: PlaybackMediaSource(id: 'source-baha', name: 'WEB-DL.Baha'),
  displayName: 'WEB-DL.Baha',
  summary: '1080p · 1.37 GB · 2.2 Mbps',
  technical: EmbyTechnicalFingerprint(height: 1080, videoCodec: 'h264'),
  videoTracks: [
    EmbyVideoStreamDescriptor(index: 0, codec: 'h264', height: 1080)
  ],
  audioTracks: [
    EmbyAudioTrackDescriptor(
      index: 1,
      language: '日语',
      codec: 'AAC',
      channels: 2,
      isDefault: true,
      fingerprint:
          EmbyTrackFingerprint(language: 'jpn', codec: 'aac', channels: 2),
    ),
  ],
  subtitleTracks: [
    EmbySubtitleTrackDescriptor(
      index: 2,
      language: '简体中文',
      codec: 'ASS',
      isExternal: false,
      isDefault: true,
      isForced: false,
      fingerprint: EmbyTrackFingerprint(language: 'chi', codec: 'ass'),
    ),
  ],
);

const _loli = EmbyMediaSourceDescriptor(
  source: PlaybackMediaSource(id: 'source-loli', name: 'WEB-DL.LoliHouse'),
  displayName: 'WEB-DL.LoliHouse',
  summary: '1080p · 505.4 MB · 2.8 Mbps',
  technical: EmbyTechnicalFingerprint(height: 1080, videoCodec: 'h264'),
  videoTracks: [
    EmbyVideoStreamDescriptor(index: 0, codec: 'h264', height: 1080)
  ],
  audioTracks: [
    EmbyAudioTrackDescriptor(
      index: 3,
      language: '\u82f1\u8bed',
      codec: 'E-AC-3',
      channels: 6,
      isDefault: true,
      fingerprint:
          EmbyTrackFingerprint(language: 'eng', codec: 'eac3', channels: 6),
    ),
  ],
  subtitleTracks: [
    EmbySubtitleTrackDescriptor(
      index: 4,
      language: '\u7e41\u9ad4\u4e2d\u6587',
      codec: 'ASS',
      isExternal: false,
      isDefault: true,
      isForced: false,
      fingerprint: EmbyTrackFingerprint(language: 'zho', codec: 'ass'),
    ),
  ],
);

class _FakeSelectionController extends EmbyMediaSelectionController {
  _FakeSelectionController({
    required EmbyMediaSelectionState state,
    this.applyResult = true,
    this.applyError,
    this.applyGate,
  }) : _state = state;

  EmbyMediaSelectionState _state;
  final bool applyResult;
  final Object? applyError;
  final Completer<bool>? applyGate;
  bool throwOnApply = false;
  final List<bool> loadCalls = <bool>[];
  final List<String> selectedSourceIds = <String>[];
  final List<EmbyTrackPreference> selectedAudio = <EmbyTrackPreference>[];
  final List<EmbyTrackPreference> selectedSubtitle = <EmbyTrackPreference>[];
  int cancelCalls = 0;
  int applyCalls = 0;

  @override
  EmbyMediaSelectionState get state => _state;

  void setState(EmbyMediaSelectionState value) {
    _state = value;
    notifyListeners();
  }

  @override
  Future<void> load({bool forceRefresh = false}) async {
    loadCalls.add(forceRefresh);
  }

  @override
  void selectSource(String sourceId) {
    selectedSourceIds.add(sourceId);
    setState(
      EmbyMediaSelectionState(
        sources: _state.sources,
        selectedSourceId: sourceId,
        canPersist: _state.canPersist,
      ),
    );
  }

  @override
  void selectAudio(EmbyTrackPreference preference) =>
      selectedAudio.add(preference);

  @override
  void selectSubtitle(EmbyTrackPreference preference) =>
      selectedSubtitle.add(preference);

  @override
  Future<bool> apply() async {
    applyCalls++;
    final gate = applyGate;
    if (gate != null) {
      setState(_stateWithSaving(true));
      final result = await gate.future;
      setState(_stateWithSaving(false));
      return result;
    }
    if (applyError != null) {
      setState(EmbyMediaSelectionState(
        sources: _state.sources,
        selectedSourceId: _state.selectedSourceId,
        audio: _state.audio,
        subtitle: _state.subtitle,
        error: applyError,
      ));
    }
    if (throwOnApply && applyError != null) throw applyError!;
    return applyResult;
  }

  @override
  void cancel() => cancelCalls++;

  EmbyMediaSelectionState _stateWithSaving(bool isSaving) =>
      EmbyMediaSelectionState(
        sources: _state.sources,
        selectedSourceId: _state.selectedSourceId,
        audio: _state.audio,
        subtitle: _state.subtitle,
        isLoading: _state.isLoading,
        isSaving: isSaving,
        error: _state.error,
        canPersist: _state.canPersist,
        dirtyDimensions: _state.dirtyDimensions,
      );
}
