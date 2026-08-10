import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/emby_media_selection_controller.dart';
import 'package:nipaplay/widgets/emby_media_source_selector.dart';

void main() {
  test('entry policy accepts Emby Windows and iOS outside large screen only',
      () {
    expect(
      shouldShowEmbyMediaSelectionEntry(
        isEmby: true,
        isWindows: true,
        isIOS: false,
        isLargeScreen: false,
      ),
      isTrue,
    );
    expect(
      shouldShowEmbyMediaSelectionEntry(
        isEmby: true,
        isWindows: false,
        isIOS: true,
        isLargeScreen: false,
      ),
      isTrue,
    );

    for (final scenario
        in <({bool isEmby, bool isWindows, bool isIOS, bool isLargeScreen})>[
      (isEmby: false, isWindows: true, isIOS: false, isLargeScreen: false),
      (isEmby: true, isWindows: false, isIOS: false, isLargeScreen: false),
      (isEmby: true, isWindows: true, isIOS: false, isLargeScreen: true),
      (isEmby: true, isWindows: false, isIOS: true, isLargeScreen: true),
    ]) {
      expect(
        shouldShowEmbyMediaSelectionEntry(
          isEmby: scenario.isEmby,
          isWindows: scenario.isWindows,
          isIOS: scenario.isIOS,
          isLargeScreen: scenario.isLargeScreen,
        ),
        isFalse,
      );
    }
  });

  testWidgets('episode trailing entry opens selection without triggering play',
      (tester) async {
    var openCalls = 0;
    var playCalls = 0;
    var danmakuCalls = 0;
    const entryLabel = '\u7248\u672c\u4e0e\u8f68\u9053';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListTile(
            key: const ValueKey<String>('emby-episode-tile'),
            title: const Text('Episode 3'),
            onTap: () {
              playCalls++;
              danmakuCalls++;
            },
            trailing: EmbyMediaSelectionEntry(
              key: const ValueKey<String>('emby-media-selection-entry'),
              savedSourceLabel: 'WEB-DL.Baha',
              onOpen: () => openCalls++,
            ),
          ),
        ),
      ),
    );

    expect(find.text(entryLabel), findsOneWidget);
    expect(find.text('WEB-DL.Baha'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('emby-media-selection-entry')),
    );

    expect(openCalls, 1);
    expect(playCalls, 0);
    expect(danmakuCalls, 0);

    await tester.tap(find.byKey(const ValueKey<String>('emby-episode-tile')));
    expect(playCalls, 1);
    expect(danmakuCalls, 1);
  });

  test('selection result updates the saved label only after successful apply',
      () {
    final controller = _LabelSelectionController(
      EmbyMediaSelectionState(
        sources: const [_bahaSource, _loliSource],
        selectedSourceId: 'source-loli',
      ),
    );
    addTearDown(controller.dispose);
    final updates = <String>[];

    updateEmbySavedSourceLabelAfterSelection(
      true,
      controller,
      updates.add,
    );
    updateEmbySavedSourceLabelAfterSelection(
      false,
      controller,
      updates.add,
    );
    updateEmbySavedSourceLabelAfterSelection(
      null,
      controller,
      updates.add,
    );

    expect(updates, ['WEB-DL.LoliHouse']);
  });
}

const _bahaSource = EmbyMediaSourceDescriptor(
  source: PlaybackMediaSource(id: 'source-baha'),
  displayName: 'WEB-DL.Baha',
  summary: '',
  technical: EmbyTechnicalFingerprint(),
  videoTracks: [],
  audioTracks: [],
  subtitleTracks: [],
);

const _loliSource = EmbyMediaSourceDescriptor(
  source: PlaybackMediaSource(id: 'source-loli'),
  displayName: 'WEB-DL.LoliHouse',
  summary: '',
  technical: EmbyTechnicalFingerprint(),
  videoTracks: [],
  audioTracks: [],
  subtitleTracks: [],
);

class _LabelSelectionController extends EmbyMediaSelectionController {
  _LabelSelectionController(this._state);

  final EmbyMediaSelectionState _state;

  @override
  EmbyMediaSelectionState get state => _state;

  @override
  Future<void> load({bool forceRefresh = false}) =>
      throw UnsupportedError('label orchestration must not load');

  @override
  void selectSource(String sourceId) =>
      throw UnsupportedError('label orchestration must not select a source');

  @override
  void selectAudio(EmbyTrackPreference preference) =>
      throw UnsupportedError('label orchestration must not select audio');

  @override
  void selectSubtitle(EmbyTrackPreference preference) =>
      throw UnsupportedError('label orchestration must not select subtitles');

  @override
  Future<bool> apply() =>
      throw UnsupportedError('label orchestration must not apply');

  @override
  void cancel() =>
      throw UnsupportedError('label orchestration must not cancel');
}
