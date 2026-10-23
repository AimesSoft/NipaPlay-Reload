import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/next_playback.dart';
import 'package:nipaplay/next/player/ports/session_playback.dart';
import 'package:nipaplay/next/player/subtitles/controller.dart';
import 'package:nipaplay/next/player/subtitles/cue_index.dart';
import 'package:nipaplay/next/player/subtitles/look.dart';
import 'package:nipaplay/next/ui/player/subtitle_layer.dart';
import 'package:nipaplay/utils/subtitle_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_driver.dart';

/// Next's tracks and subtitles (player-core design §2.3–2.4, P2): the open
/// plan carries the subtitle library's choice, what shows is what was
/// chosen and never two at once, the kernel confirms, the overlay draws a
/// text file from an index made off the main isolate, and the shared
/// settings apply.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String video;
  late String srt;
  late String ass;

  const srtText = '''1
00:00:01,000 --> 00:00:03,000
第一行

2
00:00:05,000 --> 00:00:07,000
第二行

3
00:00:06,000 --> 00:00:08,000
<i>重叠</i>
''';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('player-subtitles-');
    video = '${temp.path}/Sintel.mkv';
    await File(video).writeAsString('not a video');
    srt = '${temp.path}/Sintel.zh-Hans.srt';
    await File(srt).writeAsString(srtText);
    ass = '${temp.path}/Sintel.ass';
    await File(ass).writeAsString('[Script Info]\n');
  });
  tearDown(() => temp.delete(recursive: true));

  /// A subtitle library that offers [files] and puts [choose] on.
  SessionPlayback withLibrary(FakeHost rig,
      {List<String> files = const [],
      Future<void> Function(SubtitleTarget target)? choose,
      Duration delay = Duration.zero,
      List<(String, int?, String?)>? recorded}) {
    final playback = SessionPlayback(rig.host);
    final target = playback.subtitleTarget;
    target.loader = (path) async {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      for (final f in files) {
        await target.offer(f, f.split('/').last);
      }
      await choose?.call(target);
      return true;
    };
    target.selection = (path, index, external) async =>
        recorded?.add((path, index, external));
    return playback;
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('the library\'s embedded track is in the open plan; MDK\'s own first '
      'track is never drawn unasked', () async {
    final rig = FakeHost();
    final playback =
        withLibrary(rig, choose: (t) => t.applyEmbedded(2));
    await playback.openItem(PlayableItem(videoPath: video));
    final driver = rig.drivers.single;
    final session = playback.session!;
    expect(driver.plan!.subtitle, const EmbeddedKernelSubtitle(2));
    // Nothing switched after the open.
    expect(driver.log.where((l) => l.startsWith('subtitle')), isEmpty);
    final state = session.subtitles.state.value;
    expect(state.selectedBy, 'library_selection');
    expect(state.presented.single.renderer, SubtitleRenderer.kernel);
    expect(state.presented.single.want, const SubtitleWant.embedded(2));
    expect(session.subtitles.presentedIsSelected, isTrue);
    expect(playback.subtitleOverlay.value, isNull);
    await playback.close(reason: 'test');

    // With no library choice nothing is drawn (not the kernel's track 0).
    final bare = FakeHost();
    final quiet = SessionPlayback(bare.host);
    await quiet.openItem(PlayableItem(videoPath: video));
    expect(bare.drivers.single.plan!.subtitle, KernelSubtitle.none);
    expect(quiet.session!.subtitles.state.value.presented, isEmpty);
    await quiet.close(reason: 'test');
  });

  test('a text file the library chose is drawn over the video, the kernel '
      'drawing nothing; the line follows the clock', () async {
    final rig = FakeHost();
    final playback = withLibrary(rig,
        files: [srt], choose: (t) => t.applyExternal(srt, 'zh'));
    await playback.openItem(PlayableItem(videoPath: video),
        start: const Duration(milliseconds: 1500));
    final session = playback.session!;
    expect(rig.drivers.single.plan!.subtitle, KernelSubtitle.none);
    await settle();
    expect(session.subtitles.state.value.presented.single.renderer,
        SubtitleRenderer.overlay);
    await session.setPaused(true, origin: 'test');
    await session.seek(const Duration(milliseconds: 2000), origin: 'test');
    await settle();
    expect(playback.subtitleOverlay.value?.text, '第一行');
    await session.seek(const Duration(milliseconds: 6500), origin: 'test');
    await settle();
    // Two cues at once, each once, without markup.
    expect(playback.subtitleOverlay.value?.text, '第二行\n重叠');
    await session.seek(const Duration(milliseconds: 4000), origin: 'test');
    await settle();
    expect(playback.subtitleOverlay.value?.text, '');
    await playback.close(reason: 'test');
    expect(playback.subtitleOverlay.value, isNull);
  });

  test('switching never shows two: the overlay waits for the kernel to say '
      'off, and goes before the kernel draws again', () async {
    final rig = FakeHost();
    final playback = withLibrary(rig,
        files: [srt], choose: (t) => t.applyEmbedded(0));
    await playback.openItem(PlayableItem(videoPath: video));
    final session = playback.session!;
    final driver = rig.drivers.single;
    final shown = <String>[];
    void watch() {
      final kernel = driver.tracks.subtitle.drawn;
      final overlay = playback.subtitleOverlay.value != null;
      expect(kernel && overlay, isFalse, reason: 'two subtitles at once');
      shown.add('${kernel ? 'kernel' : '-'}/${overlay ? 'overlay' : '-'}');
    }

    playback.subtitleOverlay.addListener(watch);
    session.subtitles.state.addListener(watch);
    // Embedded → the SRT: the kernel's off first.
    driver.trackGate = Completer<void>();
    final toFile = playback.choose(SubtitleChoice.file('zh', srt));
    await settle();
    expect(playback.subtitleOverlay.value, isNull);
    expect(driver.tracks.subtitle, const EmbeddedKernelSubtitle(0));
    driver.trackGate!.complete();
    driver.trackGate = null;
    await toFile;
    await settle();
    expect(driver.tracks.subtitle, KernelSubtitle.none);
    expect(playback.subtitleOverlay.value, isNotNull);
    // The SRT → embedded 1: the overlay goes at once, then the kernel.
    driver.trackGate = Completer<void>();
    final toTrack = playback.choose(const SubtitleChoice.embedded('eng', 1));
    await Future<void>.delayed(Duration.zero);
    expect(playback.subtitleOverlay.value, isNull);
    driver.trackGate!.complete();
    driver.trackGate = null;
    await toTrack;
    expect(driver.tracks.subtitle, const EmbeddedKernelSubtitle(1));
    expect(session.subtitles.state.value.presented.single.want,
        const SubtitleWant.embedded(1));
    // Off: nothing.
    await playback.choose(const SubtitleChoice.off());
    expect(driver.tracks.subtitle, KernelSubtitle.none);
    expect(playback.subtitleOverlay.value, isNull);
    expect(session.subtitles.state.value.presented, isEmpty);
    expect(shown, isNotEmpty);
    playback.subtitleOverlay.removeListener(watch);
    session.subtitles.state.removeListener(watch);
    await playback.close(reason: 'test');
  });

  test('the person\'s and Nipa\'s choices are told to the library; the '
      'library\'s own are not, and its echo keeps the choice theirs', () async {
    final rig = FakeHost();
    final recorded = <(String, int?, String?)>[];
    final playback = withLibrary(rig,
        files: [srt], choose: (t) => t.applyEmbedded(0), recorded: recorded);
    await playback.openItem(PlayableItem(videoPath: video));
    final session = playback.session!;
    expect(recorded, isEmpty);
    await playback.choose(SubtitleChoice.file('zh', srt));
    await settle();
    expect(recorded, [(video, null, srt)]);
    expect(session.subtitles.state.value.selectedBy, 'gui');
    // The library records it and reapplies the same choice.
    await playback.subtitleTarget.reapply('file-1', [
      {'origin': 'sidecar', 'available': true, 'path': srt, 'title': 'zh'}
    ], {'origin': 'sidecar', 'path': srt, 'title': 'zh'});
    expect(session.subtitles.state.value.selectedBy, 'gui');
    expect(recorded, hasLength(1));
    // Nipa turns them off through the capability.
    final off = await playback.controls.selectTrack(
        {'kind': 'subtitle', 'origin': 'embedded', 'index': -1});
    expect((off['receipt'] as Map)['outcome'], 'applied');
    await settle();
    expect(recorded.last, (video, -1, null));
    await playback.close(reason: 'test');
  });

  test('the library telling back the same choice while it is put on does not '
      'overtake it: the receipt is the kernel\'s confirmation', () async {
    final rig = FakeHost();
    final playback = SessionPlayback(rig.host);
    final target = playback.subtitleTarget;
    target.selection = (path, index, external) async {
      // As the library does: record, then reapply its record.
      await target.reapply('file-1', const [], {'origin': 'embedded', 'index': index});
    };
    await playback.openItem(PlayableItem(videoPath: video));
    final driver = rig.drivers.single;
    driver.trackGate = Completer<void>();
    final choosing = playback.session!.chooseSubtitle(
        const SubtitleWant.embedded(2),
        origin: 'agent');
    await settle();
    driver.trackGate!.complete();
    driver.trackGate = null;
    final receipt = await choosing;
    expect(receipt.outcome, 'applied');
    expect(driver.log.where((l) => l.startsWith('subtitle')), ['subtitle embedded 2']);
    expect(playback.session!.subtitles.state.value.selectedBy, 'agent');
    await playback.close(reason: 'test');
  });

  test('a slow library: the media opens with nothing drawn and its choice '
      'goes on when it comes', () async {
    final rig = FakeHost();
    final playback = withLibrary(rig,
        delay: const Duration(milliseconds: 300),
        choose: (t) => t.applyEmbedded(1));
    // A short wait for the plan, as the lab cannot wait 3 s per test.
    final opening = playback.openItem(PlayableItem(videoPath: video));
    await opening.timeout(const Duration(seconds: 5));
    final driver = rig.drivers.single;
    // The plan waited for the library (it answers within the wait here).
    expect(driver.plan!.subtitle, const EmbeddedKernelSubtitle(1));
    await playback.close(reason: 'test');
  });

  test('a choice made before the kernel opens goes into the plan; one made '
      'while it opens is put on before it plays', () async {
    final library = Completer<void>();
    final rig = FakeHost();
    final playback = SessionPlayback(rig.host);
    playback.subtitleTarget.loader = (path) async {
      await library.future;
      return true;
    };
    final opening = playback.openItem(PlayableItem(videoPath: video));
    await settle();
    final session = playback.session!;
    final receipt = await session.chooseSubtitle(
        const SubtitleWant.embedded(1),
        origin: 'agent');
    expect(receipt.outcome, 'pending');
    final audio = await session.selectAudio(1, origin: 'agent');
    expect(audio.outcome, 'pending');
    library.complete();
    await opening;
    final driver = rig.drivers.single;
    expect(driver.plan!.subtitle, const EmbeddedKernelSubtitle(1));
    expect(driver.plan!.audio, 1);
    expect(driver.log, ['open 0', 'play']);
    expect(session.audio.value.kernel, 1);
    await playback.close(reason: 'test');

    final gate = Completer<void>();
    final held = FakeHost(make: (lease) => FakeDriver(lease, gate: gate));
    final second = SessionPlayback(held.host);
    final opening2 = second.openItem(PlayableItem(videoPath: video));
    await settle();
    final s2 = second.session!;
    unawaited(s2.chooseSubtitle(const SubtitleWant.embedded(2), origin: 'agent'));
    unawaited(s2.selectAudio(1, origin: 'agent'));
    gate.complete();
    await opening2;
    // Put on after the open, confirmed, before play.
    expect(held.drivers.single.log,
        ['open 0', 'subtitle embedded 2', 'audio 1', 'play']);
    expect(s2.subtitles.state.value.presented.single.want,
        const SubtitleWant.embedded(2));
    await second.close(reason: 'test');
  });

  test('tracks, select_track, load_subtitle, remove_subtitle and cues over '
      'the session', () async {
    final rig = FakeHost();
    final playback = SessionPlayback(rig.host);
    await playback.openItem(PlayableItem(videoPath: video));
    final session = playback.session!;
    final listed = await playback.controls.tracks({});
    final tracks = (listed['tracks'] as List).cast<Map>();
    expect(tracks.where((t) => t['kind'] == 'audio'), hasLength(2));
    expect(tracks.where((t) => t['kind'] == 'subtitle'), hasLength(3));
    expect(tracks.firstWhere((t) => t['kind'] == 'audio')['selected'], isTrue);
    // An audio track, confirmed by the kernel.
    final audio = await playback.controls
        .selectTrack({'kind': 'audio', 'origin': 'embedded', 'index': 1});
    expect((audio['receipt'] as Map)['outcome'], 'applied');
    await expectLater(
        playback.controls
            .selectTrack({'kind': 'subtitle', 'origin': 'embedded', 'index': 7}),
        throwsA(isA<Exception>()));
    // A file mounted and put on alone.
    final loaded = await playback.controls.loadSubtitle({'path': srt});
    expect(loaded['active'], isTrue);
    expect(loaded['renderer'], 'overlay');
    await settle();
    await session.setPaused(true, origin: 'test');
    await session.seek(const Duration(milliseconds: 5500), origin: 'test');
    await settle();
    final cues = await playback.controls.inspect('subtitle.cues', {});
    final current = (cues['items'] as List).cast<Map>().where((c) => c['current'] == true);
    expect(current.single['text'], '第二行');
    expect(playback.subtitleOverlay.value?.text, '第二行');
    final range = await playback.controls
        .inspect('subtitle.cues', {'startMs': 0, 'endMs': 5500, 'limit': 1});
    expect(range['total'], 2);
    expect(range['nextCursor'], 1);
    // An ASS file goes to the kernel.
    final kernel = await playback.controls.loadSubtitle({'path': ass});
    expect(kernel['renderer'], 'kernel');
    expect(rig.drivers.single.tracks.subtitle, FileKernelSubtitle(ass));
    expect(playback.subtitleOverlay.value, isNull);
    final removed = await playback.controls.removeSubtitle({'path': ass});
    expect(removed['active'], isFalse);
    expect(rig.drivers.single.tracks.subtitle, KernelSubtitle.none);
    // An embedded track: the kernel's line now, as the kernel tells it.
    rig.drivers.single.kernelText = 'Hello';
    await playback.controls
        .selectTrack({'kind': 'subtitle', 'origin': 'embedded', 'index': 1});
    final embedded = await playback.controls.inspect('subtitle.cues', {});
    expect((embedded['unsupported'] as List).single['reason'],
        'embedded_text_not_extracted');
    expect((embedded['kernelLine'] as Map)['text'], 'Hello');
    await playback.close(reason: 'test');
  });

  test('delay and size: the overlay\'s per file, the kernel\'s scale; the '
      'shared keys are written', () async {
    final rig = FakeHost();
    final playback = withLibrary(rig,
        files: [srt], choose: (t) => t.applyExternal(srt, 'zh'));
    await playback.openItem(PlayableItem(videoPath: video));
    final session = playback.session!;
    await settle();
    await session.setPaused(true, origin: 'test');
    await session.seek(const Duration(milliseconds: 3500), origin: 'test');
    await settle();
    expect(playback.subtitleOverlay.value?.text, '');
    final file = SubtitleChoice.file('zh', srt, selected: true);
    expect(playback.canDelaySubtitles(file), isTrue);
    await playback.setSubtitleDelay(file, 1);
    // 3.5 s now shows what the file has at 2.5 s.
    expect(playback.subtitleOverlay.value?.text, '第一行');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(OverlayPlacement.key(srt)), contains('"delay":1'));
    final cues = await playback.controls.inspect('subtitle.cues', {});
    expect(cues['delayMs'], 1000);
    final shown = (cues['items'] as List).cast<Map>().firstWhere((c) => c['current'] == true);
    expect(shown['startMs'], 2000);
    // The shared delay of files drawn over the video (settings.set
    // subtitle.srtDelaySeconds) adds to the file's own.
    await prefs.setDouble('srt_subtitle_delay', 3);
    rig.host.settingChanged('subtitle.srtDelaySeconds', 3.0);
    await settle();
    final shifted = await playback.controls.inspect('subtitle.cues', {});
    expect(shifted['delayMs'], 4000);
    // 3.5 s now shows what the file has at -0.5 s: nothing yet.
    expect(playback.subtitleOverlay.value?.text, '');
    await prefs.setDouble('srt_subtitle_delay', 0);
    rig.host.settingChanged('subtitle.srtDelaySeconds', 0.0);
    await settle();
    expect(playback.subtitleOverlay.value?.text, '第一行');
    await playback.setSubtitleScale(file, 1.5);
    expect(prefs.getDouble('srt_subtitle_scale'), 1.5);
    expect(playback.subtitleOverlay.value?.look.overlayScale, 1.5);
    // The kernel's own: no delay on MDK, a scale it is told.
    const track = SubtitleChoice.embedded('eng', 1, selected: true);
    expect(playback.canDelaySubtitles(track), isFalse);
    expect(playback.canScaleSubtitles(track), isTrue);
    await playback.setSubtitleScale(track, 1.2);
    expect(rig.drivers.single.properties['subtitle.scale'], '1.20');
    // A shared setting changed elsewhere (settings.set): applied.
    await prefs.setInt('subtitle_color', 0xFFFF0000);
    rig.host.settingChanged('subtitle.color', '#FFFF0000');
    await settle();
    expect(rig.drivers.single.properties['subtitle.color'], '0xff0000ff');
    expect(session.subtitles.look.color, 0xFFFF0000);
    await playback.close(reason: 'test');
  });

  test('the menu lists off, the media\'s tracks and the files, the chosen '
      'one ticked', () async {
    final rig = FakeHost();
    final playback = withLibrary(rig,
        files: [srt], choose: (t) => t.applyEmbedded(2));
    await playback.openItem(PlayableItem(videoPath: video));
    final menu = await playback.subtitles();
    expect([for (final c in menu) c.label],
        ['关闭', '德语', '英语', 'JPSC', 'Sintel.zh-Hans']);
    expect(menu.where((c) => c.selected).single.label, 'JPSC');
    expect([for (final a in playback.audio()) a.label], ['日语', '英语']);
    expect(playback.offersSubtitles, isTrue);
    await playback.close(reason: 'test');
  });

  group('the cue index', () {
    CueIndex index(List<(int, int, String)> cues) => CueIndex.build('x.srt', [
          for (final (s, e, t) in cues)
            SubtitleEntry(startTimeMs: s, endTimeMs: e, content: t)
        ]);

    test('lines: what is on at a time and until when', () {
      final i = index([(1000, 3000, 'a'), (2000, 4000, 'b'), (6000, 7000, 'c')]);
      expect(i.lineAt(500).text, '');
      expect(i.lineAt(500).until, 1000);
      expect(i.lineAt(1500).text, 'a');
      expect(i.lineAt(2500).text, 'a\nb');
      expect(i.lineAt(2500).until, 3000);
      expect(i.lineAt(3500).text, 'b');
      expect(i.lineAt(5000).text, '');
      expect(i.lineAt(7000).text, '');
      expect(i.lineAt(7000).until, isNull);
    });

    test('pages: overlapping spans, context, cursors', () {
      final i = index([
        for (var k = 0; k < 100; k++) (k * 1000, k * 1000 + 800, 'line $k')
      ]);
      // 10.0–10.8 s reaches into the span; 21.0 s starts after it.
      final range = i.page(positionMs: 0, startMs: 10500, endMs: 20500, limit: 5);
      expect(range.total, 11);
      expect([for (final c in range.items) c.text].first, 'line 10');
      expect(range.nextCursor, 5);
      final rest = i.page(
          positionMs: 0, startMs: 10500, endMs: 20500, cursor: 5, limit: 50);
      expect(rest.items, hasLength(6));
      expect(rest.items.last.text, 'line 20');
      expect(rest.nextCursor, isNull);
      final around = i.page(positionMs: 50400);
      expect([for (final c in around.items) c.text],
          ['line 48', 'line 49', 'line 50', 'line 51', 'line 52']);
      expect(around.items[2].current, isTrue);
      final gap = i.page(positionMs: 50900, context: 0);
      expect(gap.items.single.text, 'line 50');
      expect(gap.items.single.current, isFalse);
    });

    test('a file is parsed off the main isolate', () async {
      final parsed = await CueIndex.load(srt);
      expect(parsed.length, 3);
      expect(parsed.lineAt(6500).text, '第二行\n重叠');
    });
  });

  testWidgets('the overlay rebuilds only when its line changes',
      (tester) async {
    final overlay = ValueNotifier<OverlayFrame?>(null);
    var built = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (e, _) {
      if (e.widget is Text) built++;
    };
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
            width: 800,
            height: 450,
            child: NextSubtitleLayer(overlay: overlay))));
    const look = SubtitleLook(borderSize: 0);
    overlay.value = const OverlayFrame('一', look, OverlayPlacement());
    await tester.pump();
    final first = built;
    expect(find.text('一'), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(built, first);
    overlay.value = const OverlayFrame('二', look, OverlayPlacement());
    await tester.pump();
    expect(find.text('二'), findsOneWidget);
    debugOnRebuildDirtyWidget = previous;
  });
}
