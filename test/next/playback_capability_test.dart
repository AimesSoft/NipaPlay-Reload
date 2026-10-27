import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/playback_capability.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackFixture fixture;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fixture = PlaybackFixture();
  });

  group('playback.open', () {
    test('a fresh file needs no history and does not synthesize a history row', () async {
      final directory = await Directory.systemTemp.createTemp('x13-new-file-');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('${directory.path}/new.mkv').writeAsString('source');
      fixture = PlaybackFixture(rows: []);
      await invokeCompleted(fixture.harness, 'playback.open', {'path': file.path});
      expect(fixture.started.single.historyItem, isNull);
      expect(fixture.started.single.videoPath, file.path);
      expect(fixture.rows, isEmpty);
      expect(await file.readAsString(), 'source');
    });

    test('an unrecorded URL reaches Classic without an invented identity', () async {
      fixture = PlaybackFixture(rows: []);
      await invokeCompleted(fixture.harness, 'playback.open', {'path': 'https://example.test/video.mp4'});
      expect(fixture.started.single.historyItem, isNull);
      expect(fixture.started.single.animeId, isNull);
      expect(fixture.started.single.episodeId, isNull);
    });

    test('a stable Mesh locator reaches the source resolver without a URL host', () async {
      fixture = PlaybackFixture(rows: []);
      const locator = 'mesh:///mesh-episode%3Averified-id';
      await invokeCompleted(fixture.harness, 'playback.open', {'path': locator});
      expect(fixture.started.single.videoPath, locator);
      expect(fixture.started.single.historyItem, isNull);
    });

    for (final locator in [
      'mesh://other-device/episode', 'mesh:///', 'mesh:///a/b',
      'mesh:///episode?grant=invalid', 'mesh:///episode#fragment',
    ]) {
      test('rejects malformed Mesh locator $locator before opening', () async {
        fixture = PlaybackFixture(rows: []);
        await invokeFailed(fixture.harness, 'playback.open', {'path': locator},
            FailureCode.invalidInput);
        expect(fixture.started, isEmpty);
      });
    }

    test('a file URL resolves to the same local history identity', () async {
      // A drive-letter path on Windows; a POSIX path has no file URL there.
      if (Platform.isWindows) {
        fixture = PlaybackFixture(rows: [watchItem(r'C:\media\episode.mkv')]);
      }
      final row = fixture.rows.single;
      await invokeCompleted(fixture.harness, 'playback.open', {'path': Uri.file(row.filePath).toString()});
      expect(fixture.started.single.videoPath, row.filePath);
      expect(fixture.started.single.historyItem, same(row));
    });

    test('Classic receives non-HTTP streaming URLs without a scheme allowlist', () async {
      fixture = PlaybackFixture(rows: []);
      await invokeCompleted(fixture.harness, 'playback.open', {'path': 'rtsp://example.test/live'});
      expect(fixture.started.single.videoPath, 'rtsp://example.test/live');
    });

    test('opens by path, copies history fields and bypasses file selection',
        () async {
      final row = watchItem('/media/path.mkv',
          animeId: null, episodeId: null, episodeTitle: null, mediaKey: null);
      fixture = PlaybackFixture(rows: [row]);
      final result = await invokeCompleted(
          fixture.harness, 'playback.open', {'path': row.filePath});
      expect(result['path'], row.filePath);
      expect(result['player'], 'internal');
      expect(result['state'], fixture.player.snapshot().toJson());
      final item = fixture.started.single;
      expect(item.videoPath, row.filePath);
      expect(item.title, row.animeName);
      expect(item.subtitle, row.episodeTitle);
      expect(item.animeId, row.animeId);
      expect(item.episodeId, row.episodeId);
      expect(item.historyItem, same(row));
      expect(item.mediaKey, row.mediaKey);
      expect(fixture.pathLoads, [row.filePath]);
      expect(fixture.episodeLoads, isEmpty);
      expect(fixture.matchLoads, isEmpty);
      expect(fixture.selectionHistoryLoads, isEmpty);
      expect(fixture.player.seeks, isEmpty);
    });

    test(
        'does not choose again for an explicit path with multiple matched files',
        () async {
      fixture = PlaybackFixture(rows: [
        watchItem('/media/first.mkv'),
        watchItem('/media/second.mkv')
      ]);
      await invokeCompleted(
          fixture.harness, 'playback.open', {'path': '/media/second.mkv'});
      expect(fixture.started.single.historyItem, same(fixture.rows[1]));
      expect(fixture.matchLoads, isEmpty);
    });

    test('opens an episode with one file through the selection service',
        () async {
      final result = await invokeCompleted(fixture.harness, 'playback.open',
          {'animeId': 10.0, 'episodeId': 100.0});
      expect(result['path'], fixture.rows.single.filePath);
      expect(fixture.episodeLoads, [(10, 100)]);
      expect(fixture.matchLoads, [(10, 100)]);
      expect(fixture.selectionHistoryLoads, [fixture.rows.single.filePath]);
      expect(fixture.pathLoads, isEmpty);
      expect(fixture.started.single.mediaKey, fixture.rows.single.mediaKey);
      expect(fixture.started.single.historyItem, same(fixture.rows.single));
    });

    test('reports and starts the final path resolved by the service', () async {
      final selected = watchItem('/media/resolved.mkv');
      fixture.matchesForSelection = [selected];
      final result = await invokeCompleted(
          fixture.harness, 'playback.open', {'animeId': 10, 'episodeId': 100});
      expect(result['path'], selected.filePath);
      expect(fixture.started.single.videoPath, selected.filePath);
      expect(fixture.started.single.historyItem, same(selected));
    });

    for (final startPosition in [null, 0, 250]) {
      test(
          'seeks after internal playback starts with startPositionMs=$startPosition',
          () async {
        final result = await invokeCompleted(fixture.harness, 'playback.open', {
          'path': fixture.rows.single.filePath,
          if (startPosition != null)
            'startPositionMs': startPosition.toDouble(),
        });
        expect(fixture.started.length, 1);
        expect(
            fixture.player.seeks,
            startPosition == null
                ? <Duration>[]
                : [Duration(milliseconds: startPosition)]);
        expect((result['state'] as Map)['positionMs'], startPosition ?? 500);
      });
    }

    for (final startPosition in [null, 250]) {
      test(
          'multiple episode files return executable decisions with startPositionMs=$startPosition',
          () async {
        fixture = PlaybackFixture(rows: [
          watchItem('/media/first.mkv', progress: 0.25),
          watchItem('webdav://dav/second%20HD.mkv', progress: 0.5),
          watchItem('smb://server/third.mkv', progress: 0.75),
        ]);
        final outcome = await invoke(fixture.harness, 'playback.open', {
          'animeId': 10,
          'episodeId': 100,
          if (startPosition != null) 'startPositionMs': startPosition,
        });
        expect(outcome, isA<NeedsDecision<JsonEncodable>>());
        final decision = (outcome as NeedsDecision<JsonEncodable>).decision;
        expect(outcome.toEnvelope(),
            {'status': 'needs_decision', 'decision': decision.toJson()});
        expect(decision.prompt, isNotEmpty);
        expect(decision.options.map((option) => option.label),
            ['first.mkv', 'second HD.mkv', 'third.mkv']);
        expect(decision.options.map((option) => option.detail), [
          '本地媒体库 · 25% watched',
          'WebDAV · 50% watched',
          'SMB · 75% watched',
        ]);
        expect(fixture.started, isEmpty);
        expect(fixture.player.seeks, isEmpty);
        for (var i = 0; i < decision.options.length; i++) {
          final call = decision.options[i].call;
          expect(call.actionId, 'playback.open');
          expect(call.input, {
            'path': fixture.rows[i].filePath,
            if (startPosition != null) 'startPositionMs': startPosition,
          });
          final result =
              await invokeCompleted(fixture.harness, call.actionId, call.input);
          expect(result['path'], fixture.rows[i].filePath);
          expect((result['state'] as Map)['positionMs'], startPosition ?? 500);
        }
        expect(fixture.matchLoads, [(10, 100)]);
        expect(fixture.started.map((item) => item.videoPath),
            fixture.rows.map((item) => item.filePath));
      });
    }

    for (final input in <JsonMap>[
      {'path': '/missing.mkv'},
      {'animeId': 999, 'episodeId': 999}
    ]) {
      test('returns not_found for $input without starting playback', () async {
        await invokeFailed(
            fixture.harness, 'playback.open', input, FailureCode.notFound);
        expect(fixture.started, isEmpty);
        expect(fixture.player.seeks, isEmpty);
      });
    }

    test('returns not_found when resolution returns null without a chooser',
        () async {
      fixture.storedForSelection = fixture.rows.single.withoutMatchInfo();
      fixture.matchesForSelection = [];
      await invokeFailed(fixture.harness, 'playback.open',
          {'animeId': 10, 'episodeId': 100}, FailureCode.notFound);
      expect(fixture.matchLoads, [(10, 100)]);
      expect(fixture.started, isEmpty);
    });

    for (final input in <JsonMap>[
      {'path': '/media/episode.mkv', 'startPositionMs': 0},
      {'animeId': 10, 'episodeId': 100, 'startPositionMs': 250},
    ]) {
      test(
          'opens and seeks an external player with a specified position: $input',
          () async {
        fixture.external = true;
        await invokeCompleted(fixture.harness, 'playback.open', input);
        expect(fixture.started, hasLength(1));
        expect(fixture.player.seeks, [Duration(milliseconds: input['startPositionMs'] as int)]);
      });
    }

    test('opens through the external player without a specified start position',
        () async {
      fixture.external = true;
      final result = await invokeCompleted(fixture.harness, 'playback.open',
          {'path': fixture.rows.single.filePath});
      expect(result['player'], 'external');
      expect(fixture.started.length, 1);
      expect(fixture.player.seeks, isEmpty);
    });

    test('returns retryable unavailable when start fails and does not seek',
        () async {
      fixture.startSucceeds = false;
      final failure = await invokeFailed(
          fixture.harness,
          'playback.open',
          {
            'path': fixture.rows.single.filePath,
            'startPositionMs': 250,
          },
          FailureCode.unavailable);
      expect(failure.retryable, isTrue);
      expect(failure.details, isEmpty);
      expect(fixture.started.length, 1);
      expect(fixture.player.seeks, isEmpty);
    });

    test('a start that could not begin carries the player error it left',
        () async {
      fixture.startSucceeds = false;
      fixture.player.error = {
        'code': 'media_load_failed',
        'stage': 'stream_session',
        'category': 'source_failed',
      };
      final failure = await invokeFailed(fixture.harness, 'playback.open',
          {'path': fixture.rows.single.filePath}, FailureCode.unavailable);
      expect(failure.details, {'playerError': fixture.player.error});
    });

    for (final input in <JsonMap>[
      {},
      {'path': ''},
      {'animeId': 10},
      {'episodeId': 100},
      {'path': '/media/episode.mkv', 'animeId': 10, 'episodeId': 100},
      {'path': '/media/episode.mkv', 'animeId': 10},
      {'path': '/media/episode.mkv', 'startPositionMs': -1},
      {'path': '/media/episode.mkv', 'startPositionMs': 0.5},
    ]) {
      test('rejects invalid open input $input before dependencies are called',
          () async {
        await invokeFailed(
            fixture.harness, 'playback.open', input, FailureCode.invalidInput);
        expect(fixture.started, isEmpty);
        expect(fixture.pathLoads, isEmpty);
        expect(fixture.episodeLoads, isEmpty);
      });
    }
  });

  group('playback.state', () {
    test('returns all current snapshot fields', () async {
      final result =
          await invokeCompleted(fixture.harness, 'playback.state', {});
      expect(result, {
        'state': {
          'status': 'playing',
          'observedState': 'playing',
          'sessionId': null,
          'ready': null,
          'buffering': null,
          'bufferedPositionMs': null,
          'error': null,
          'observedAt': null,
          'supportedControls': <String>[],
          'hasVideo': true,
          'paused': false,
          'path': '/media/episode.mkv',
          'seriesTitle': 'Recorded title',
          'episodeTitle': 'Episode one',
          'animeId': 10,
          'episodeId': 100,
          'positionMs': 500,
          'durationMs': 1000,
          'rate': 1.25,
          'canPrevious': true,
          'canNext': true,
        }
      });
    });

    test('returns idle state with nullable metadata when no video exists',
        () async {
      fixture.player
        ..hasVideo = false
        ..path = null
        ..seriesTitle = null
        ..episodeTitle = null
        ..animeId = null
        ..episodeId = null
        ..canNext = false
        ..canPrevious = false;
      final result =
          await invokeCompleted(fixture.harness, 'playback.state', {});
      expect(result['state'], fixture.player.snapshot().toJson());
      expect((result['state'] as Map)['status'], 'idle');
    });

    test('rejects fields in the NoInput contract', () async {
      await invokeFailed(fixture.harness, 'playback.state', {'unused': true},
          FailureCode.invalidInput);
    });
  });

  group('playback.set_paused', () {
    test('pauses and resumes and returns state after the change', () async {
      for (final paused in [true, false]) {
        final result = await invokeCompleted(
            fixture.harness, 'playback.set_paused', {'paused': paused});
        expect((result['state'] as Map)['paused'], paused);
        expect(
            (result['state'] as Map)['status'], paused ? 'paused' : 'playing');
      }
      expect(fixture.player.pauseCalls, [true, false]);
    });

    test('fails unavailable without a video and does not call the player',
        () async {
      fixture.player.hasVideo = false;
      await invokeFailed(fixture.harness, 'playback.set_paused',
          {'paused': true}, FailureCode.unavailable);
      expect(fixture.player.pauseCalls, isEmpty);
    });

    test('rejects a non-boolean paused value', () async {
      await invokeFailed(fixture.harness, 'playback.set_paused',
          {'paused': 'true'}, FailureCode.invalidInput);
      expect(fixture.player.pauseCalls, isEmpty);
    });
  });

  group('playback.seek', () {
    for (final entry in <(JsonMap, int)>[
      ({'positionMs': 250.0}, 250),
      ({'positionMs': 0}, 0),
      ({'positionMs': 1500}, 1000),
      ({'offsetMs': 250.0}, 750),
      ({'offsetMs': -250}, 250),
      ({'offsetMs': -1000}, 0),
      ({'offsetMs': 1000}, 1000),
    ]) {
      test('seeks with ${entry.$1} to ${entry.$2}', () async {
        final result =
            await invokeCompleted(fixture.harness, 'playback.seek', entry.$1);
        expect((result['state'] as Map)['positionMs'], entry.$2);
        expect(fixture.player.seeks, [Duration(milliseconds: entry.$2)]);
      });
    }

    test('clamps to zero for a zero-duration video', () async {
      fixture.player.durationMs = 0;
      final result = await invokeCompleted(
          fixture.harness, 'playback.seek', {'positionMs': 250});
      expect((result['state'] as Map)['positionMs'], 0);
    });

    test('fails unavailable without a video and does not seek', () async {
      fixture.player.hasVideo = false;
      await invokeFailed(fixture.harness, 'playback.seek', {'positionMs': 250},
          FailureCode.unavailable);
      expect(fixture.player.seeks, isEmpty);
    });

    for (final input in <JsonMap>[
      {},
      {'positionMs': 250, 'offsetMs': 10},
      {'positionMs': -1},
      {'offsetMs': 1.5}
    ]) {
      test('rejects invalid seek input $input', () async {
        await invokeFailed(
            fixture.harness, 'playback.seek', input, FailureCode.invalidInput);
        expect(fixture.player.seeks, isEmpty);
      });
    }
  });

  group('playback.switch_episode', () {
    for (final direction in EpisodeDirection.values) {
      test('awaits switching ${direction.name} and returns the new state',
          () async {
        final result = await invokeCompleted(fixture.harness,
            'playback.switch_episode', {'direction': direction.name});
        expect(fixture.player.switches, [direction]);
        expect((result['state'] as Map)['episodeId'],
            direction == EpisodeDirection.next ? 101 : 99);
        expect((result['state'] as Map)['episodeTitle'],
            direction == EpisodeDirection.next ? 'Episode 101' : 'Episode 99');
      });

      test('fails unavailable without a video when switching ${direction.name}',
          () async {
        fixture.player.hasVideo = false;
        await invokeFailed(fixture.harness, 'playback.switch_episode',
            {'direction': direction.name}, FailureCode.unavailable);
        expect(fixture.player.switches, isEmpty);
      });

      test('fails unavailable when ${direction.name} is not available',
          () async {
        if (direction == EpisodeDirection.next) {
          fixture.player.canNext = false;
        } else {
          fixture.player.canPrevious = false;
        }
        await invokeFailed(fixture.harness, 'playback.switch_episode',
            {'direction': direction.name}, FailureCode.unavailable);
        expect(fixture.player.switches, isEmpty);
      });
    }

    test('rejects unknown episode directions', () async {
      await invokeFailed(fixture.harness, 'playback.switch_episode',
          {'direction': 'later'}, FailureCode.invalidInput);
      expect(fixture.player.switches, isEmpty);
    });
  });
}
