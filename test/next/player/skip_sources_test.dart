import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/next/player/ports/session_playback.dart';
import 'package:nipaplay/next/player/skip/skip_sources.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media_test_support.dart';
import 'fake_driver.dart';

/// A file that is episode [number] of a local catalogue work.
Future<String> episodeFile(MediaFixture f, String name, String? number,
    {String work = 'w'}) async {
  final file = await f.file(name);
  await f.call('media.entities.put_batch', {
    'requestId': 'put-$name',
    'reason': 'test catalogue',
    'entries': [
      {'kind': 'work', 'entityId': work, 'title': 'Work'},
      {'kind': 'release', 'entityId': '$work-r', 'parentId': work, 'title': 'S1'},
      {
        'kind': 'episode',
        'entityId': '$work-e-$name',
        'parentId': '$work-r',
        'title': 'Episode',
        if (number != null) 'number': number,
        'fileIds': [file]
      },
    ]
  });
  // The store keeps the real path of a file (/var is /private/var here).
  return File('${f.media.path}/$name').resolveSymbolicLinksSync();
}

Future<void> writeId(MediaFixture f, String entityId, String kind,
    String provider, String id) async {
  await f.call('media.identity.bind_batch', {
    'requestId': 'id-$entityId-$provider',
    'entries': [
      {
        'kind': kind,
        'entityId': entityId,
        'ref': {
          'provider': provider,
          'objectType': 'anime',
          'externalId': id,
          'scope': ''
        },
        'reason': 'the anime this is'
      }
    ]
  });
}

const _op = SkipSegment(
    kind: SkipSegmentKind.opening,
    source: SkipSegmentSource.aniskip,
    startSeconds: 20,
    endSeconds: 110);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MediaFixture f;
  final asked = <(int, int, double?)>[];
  var anilistAnswer = (malId: 777 as int?, definitive: true);
  late SessionSkipSources sources;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    f = MediaFixture();
    await f.open();
    asked.clear();
    anilistAnswer = (malId: 777, definitive: true);
    sources = SessionSkipSources(() => f.identities,
        fetch: ({required malId, required episode, lengthSeconds}) async {
      asked.add((malId, episode, lengthSeconds));
      return [_op];
    }, malOf: (id) async => anilistAnswer);
  });
  tearDown(() => f.close());

  group('AniSkip is asked only with an ID Nipa wrote', () {
    test('no MAL ID: not asked, and the reason says so', () async {
      final path = await episodeFile(f, 'ep12.mkv', '12');
      final outcome = await sources.aniskip.lookup(path);
      expect(outcome.segments, isEmpty);
      expect(outcome.facts, {
        'available': false,
        'reason': 'no_mal_id',
        'episodeNumber': 12
      });
      expect(asked, isEmpty);
    });

    test('a MAL ID on the work and a bound episode number: asked with both',
        () async {
      final path = await episodeFile(f, 'ep12.mkv', '12');
      await writeId(f, 'w', 'work', malProvider, '52991');
      final outcome = await sources.aniskip.lookup(path, lengthSeconds: 1420);
      expect(asked, [(52991, 12, 1420.0)]);
      expect(outcome.segments, [_op]);
      expect(outcome.facts['available'], true);
      expect(outcome.facts['malId'], 52991);
      expect(outcome.facts['episodeNumber'], 12);
      expect((outcome.facts['idFrom'] as Map)['entityKind'], 'work');
    });

    test('the nearest entity with an ID wins: the season over the work',
        () async {
      final path = await episodeFile(f, 'ep3.mkv', '3');
      await writeId(f, 'w', 'work', malProvider, '1');
      await writeId(f, 'w-r', 'release', malProvider, '2');
      await sources.aniskip.lookup(path);
      expect(asked.single.$1, 2);
    });

    test('an AniList ID is turned into a MAL ID by id, never by title',
        () async {
      final path = await episodeFile(f, 'ep5.mkv', '5');
      await writeId(f, 'w', 'work', anilistProvider, '150');
      final outcome = await sources.aniskip.lookup(path);
      expect(asked.single.$1, 777);
      expect((outcome.facts['idFrom'] as Map)['provider'], anilistProvider);

      asked.clear();
      anilistAnswer = (malId: null, definitive: true);
      var none = await sources.aniskip.lookup(path);
      expect(none.facts['reason'], 'anilist_has_no_mal_id');
      anilistAnswer = (malId: null, definitive: false);
      none = await sources.aniskip.lookup(path);
      expect(none.facts['reason'], 'anilist_request_failed');
      expect(asked, isEmpty);
    });

    test('an episode without a bound number, a file with no episode, an unknown file',
        () async {
      final path = await episodeFile(f, 'special.mkv', null);
      await writeId(f, 'w', 'work', malProvider, '9');
      expect((await sources.aniskip.lookup(path)).facts['reason'],
          'no_episode_number');
      final special = await episodeFile(f, 'sp.mkv', 'S1', work: 'w2');
      expect((await sources.aniskip.lookup(special)).facts['reason'],
          'no_episode_number');
      final bare = await f.file('bare.mkv');
      expect(bare, isNotEmpty);
      expect((await sources.aniskip.lookup(File('${f.media.path}/bare.mkv').resolveSymbolicLinksSync())).facts['reason'],
          'no_episode');
      expect((await sources.aniskip.lookup('/nowhere.mkv')).facts['reason'],
          'no_episode');
      expect(asked, isEmpty);
    });

    test('AniSkip knowing nothing of the episode is reported as such',
        () async {
      final path = await episodeFile(f, 'ep1.mkv', '1');
      await writeId(f, 'w', 'work', malProvider, '9');
      final empty = SessionSkipSources(() => f.identities,
          fetch: ({required malId, required episode, lengthSeconds}) async =>
              const []);
      final outcome = await empty.aniskip.lookup(path);
      expect(outcome.facts['available'], false);
      expect(outcome.facts['reason'], 'no_segments_returned');
      expect(outcome.facts['malId'], 9);
    });
  });

  test('what Nipa set is kept per file: replaced, cleared, found again',
      () async {
    final path = await episodeFile(f, 'ep2.mkv', '2');
    final store = sources.store;
    expect(await store.read(path), isEmpty);
    var now = await store.write(path, SkipSegmentKind.opening,
        range: (startMs: 1000, endMs: 90000));
    expect(now.single.source, SkipSegmentSource.agent);
    now = await store.write(path, SkipSegmentKind.ending,
        range: (startMs: 1300000, endMs: 1400000));
    expect(now.map((s) => s.kind.name).toSet(), {'opening', 'ending'});
    now = await store.write(path, SkipSegmentKind.opening,
        range: (startMs: 2000, endMs: 95000));
    expect(
        now.firstWhere((s) => s.kind == SkipSegmentKind.opening).endSeconds, 95);
    await f.reopen();
    final again = SessionSkipSources(() => f.identities);
    expect((await again.store.read(path)).length, 2);
    now = await again.store.write(path, SkipSegmentKind.opening);
    expect(now.single.kind, SkipSegmentKind.ending);
    // Another file of the same episode has nothing.
    final other = await episodeFile(f, 'ep2b.mkv', '2', work: 'w2');
    expect(await again.store.read(other), isEmpty);
  });

  group('in a playback session', () {
    late String path;
    late FakeHost rig;
    late SessionPlayback playback;
    setUp(() async {
      path = await episodeFile(f, 'ep12.mkv', '12');
      rig = FakeHost();
      playback = SessionPlayback(rig.host, skipSources: sources);
      await playback.danmaku.settled;
    });
    tearDown(() async {
      await playback.close(reason: 'test');
      await playback.dispose();
    });

    Future<void> settle() async {
      // The sources are asked when the session is open; let them answer.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await playback.danmaku.settled;
      }
    }

    Future<Map> chapters() async =>
        await playback.inspection.inspect('playback.chapters', {});

    test('AniSkip with an ID, the segment lands with its source; without, the reason',
        () async {
      await playback.openItem(PlayableItem(videoPath: path));
      await settle();
      var facts = (await chapters())['aniskip'] as Map;
      expect(facts['reason'], 'no_mal_id');
      expect(playback.danmaku.timeline.segments, isEmpty);

      await playback.close(reason: 'again');
      await writeId(f, 'w', 'work', malProvider, '52991');
      await playback.openItem(PlayableItem(videoPath: path));
      await settle();
      facts = (await chapters())['aniskip'] as Map;
      expect(facts['available'], true);
      final segment = playback.danmaku.timeline.segments.single;
      expect(segment.source, SkipSegmentSource.aniskip);
      expect((segment.startSeconds, segment.endSeconds), (20, 110));
    });

    test('playback.set_skip_segment: sets, shows the button, remembers, clears',
        () async {
      await playback.openItem(PlayableItem(videoPath: path));
      await settle();
      final id = playback.snapshot().sessionId;
      final set = await playback.inspection.inspect('playback.set_skip_segment',
          {'sessionId': id, 'kind': 'opening', 'startMs': 5000, 'endMs': 90000});
      expect(set['remembered'], true);
      expect((set['inEffect'] as Map)['source'], 'agent');
      final listed = (await chapters())['skipSegments'] as List;
      expect(listed.single['source'], 'agent');
      await playback.session!.seek(const Duration(seconds: 30), origin: 'agent');
      expect(playback.skippable, SkipSegmentKind.opening);
      await playback.skip();
      expect(playback.position.inMilliseconds, closeTo(90000, 200));
      expect(playback.skippable, isNull);

      // The same file opened again has it.
      await playback.close(reason: 'again');
      await playback.openItem(PlayableItem(videoPath: path));
      await settle();
      expect(playback.danmaku.timeline.segments.single.source,
          SkipSegmentSource.agent);

      final id2 = playback.snapshot().sessionId;
      final cleared = await playback.inspection.inspect(
          'playback.set_skip_segment',
          {'sessionId': id2, 'kind': 'opening', 'clear': true});
      expect(cleared['cleared'], true);
      expect(cleared['inEffect'], isNull);
      expect(playback.danmaku.timeline.segments, isEmpty);
      await playback.close(reason: 'again');
      await playback.openItem(PlayableItem(videoPath: path));
      await settle();
      expect(playback.danmaku.timeline.segments, isEmpty);
    });

    test('the Skip button is pushed at the edges of the segment, controls shown or not',
        () async {
      await playback.openItem(PlayableItem(videoPath: path));
      await settle();
      final id = playback.snapshot().sessionId;
      await playback.inspection.inspect('playback.set_skip_segment',
          {'sessionId': id, 'kind': 'opening', 'startMs': 500, 'endMs': 1000});
      // What the interface is told: the kind at every push of the frame.
      final told = <SkipSegmentKind?>[];
      void listener() => told.add(playback.skippable);
      playback.frame.addListener(listener);
      addTearDown(() => playback.frame.removeListener(listener));

      await playback.session!.seek(Duration.zero, origin: 'agent');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      told.clear();
      await playback.port.setPaused(false);
      // In at 0.5 s.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(told, contains(SkipSegmentKind.opening),
          reason: 'entering the segment is pushed');
      // Out at 1.0 s.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(told.last, isNull, reason: 'leaving the segment is pushed');
      expect(playback.skippable, isNull);
    });

    test('a seek into or out of the segment, and a new session, are pushed',
        () async {
      await playback.openItem(PlayableItem(videoPath: path));
      await settle();
      final id = playback.snapshot().sessionId;
      await playback.inspection.inspect('playback.set_skip_segment',
          {'sessionId': id, 'kind': 'opening', 'startMs': 5000, 'endMs': 90000});
      final told = <SkipSegmentKind?>[];
      void listener() => told.add(playback.skippable);
      playback.frame.addListener(listener);
      addTearDown(() => playback.frame.removeListener(listener));

      await playback.session!.seek(const Duration(seconds: 30), origin: 'agent');
      expect(told.last, SkipSegmentKind.opening);
      await playback.session!.seek(const Duration(seconds: 200), origin: 'agent');
      expect(told.last, isNull);
      await playback.session!.seek(const Duration(seconds: 30), origin: 'agent');
      expect(told.last, SkipSegmentKind.opening);

      // Another file: its own session, nothing skippable until told.
      final other = await episodeFile(f, 'ep13.mkv', '13', work: 'w2');
      await playback.openItem(PlayableItem(videoPath: other));
      await settle();
      expect(told.last, isNull);
      expect(playback.skippable, isNull);
    });

    test('Nipa\'s segment outranks AniSkip\'s; the user\'s mark outranks hers',
        () async {
      await writeId(f, 'w', 'work', malProvider, '52991');
      await playback.openItem(PlayableItem(videoPath: path));
      await settle();
      expect(playback.danmaku.timeline.segments.single.source,
          SkipSegmentSource.aniskip);
      final id = playback.snapshot().sessionId;
      await playback.inspection.inspect('playback.set_skip_segment',
          {'sessionId': id, 'kind': 'opening', 'startMs': 5000, 'endMs': 90000});
      expect(playback.danmaku.timeline.segments.single.source,
          SkipSegmentSource.agent);
      playback.danmaku.setSkipSegments('user', const [
        SkipSegment(
            kind: SkipSegmentKind.opening,
            source: SkipSegmentSource.manual,
            startSeconds: 1,
            endSeconds: 2)
      ]);
      await playback.danmaku.settled;
      expect(playback.danmaku.timeline.segments.single.source,
          SkipSegmentSource.manual);
      // Clearing hers leaves the slot to what outranks the rest.
      final cleared = await playback.inspection.inspect(
          'playback.set_skip_segment',
          {'sessionId': id, 'kind': 'opening', 'clear': true});
      expect((cleared['inEffect'] as Map)['source'], 'manual');
    });

    test('bad ranges and a stale session are refused', () async {
      await playback.openItem(PlayableItem(videoPath: path));
      await settle();
      final id = playback.snapshot().sessionId;
      Future<Object?> call(Map<String, Object?> input) => playback.inspection
          .inspect('playback.set_skip_segment', {'sessionId': id, ...input});
      await expectLater(
          call({'kind': 'opening', 'startMs': 9000, 'endMs': 9000}),
          throwsA(isA<Failure>()));
      await expectLater(
          call({'kind': 'opening', 'startMs': 0, 'endMs': 99999999}),
          throwsA(isA<Failure>()));
      await expectLater(call({'kind': 'opening', 'startMs': 1000}),
          throwsA(isA<Failure>()));
      await expectLater(
          call({'kind': 'opening', 'clear': true, 'startMs': 1, 'endMs': 2}),
          throwsA(isA<Failure>()));
      await expectLater(
          playback.inspection.inspect('playback.set_skip_segment', {
            'sessionId': 'old',
            'kind': 'opening',
            'startMs': 1,
            'endMs': 2
          }),
          throwsA(isA<Failure>()
              .having((e) => e.code, 'code', FailureCode.conflict)));
    });
  });
}
