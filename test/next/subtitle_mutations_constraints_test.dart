import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/subtitles/capability.dart';
import 'package:nipaplay/next/subtitles/library.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'media_test_support.dart';

void main() {
  late MediaFixture f;
  late SubtitleLibrary library;
  late Harness harness;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    f = MediaFixture();
    await f.open();
    library = SubtitleLibrary(f.service, f.root,
        probe: (_) async => {'subtitles': <JsonMap>[]});
    harness = Harness([SubtitleCapability(library)]);
  });
  tearDown(() async {
    await library.close();
    await f.close();
  });
  Future<JsonMap> call(String action, JsonMap input) async {
    final outcome =
        await harness.invokeJson(action, input, Invocation(origin: 'mcp'));
    expect(outcome, isA<Completed>(), reason: outcome.toEnvelope().toString());
    return (outcome as Completed).value.toJson();
  }

  test('facts pagination retains every imported file without duplicates',
      () async {
    final source = File('${f.root.path}/page.srt');
    await source.writeAsString('1\n00:00:00,000 --> 00:00:05,000\nCC0\n');
    final ids = [await f.file('page-a.mkv'), await f.file('page-b.mkv')];
    await call('subtitle.import', {
      'entries': [
        for (final id in ids)
          {
            'fileId': id,
            'filePath': source.path,
            'language': 'en',
            'source': {'label': 'CC0'}
          }
      ]
    });
    final first = await call('subtitle.tracks', {'limit': 1});
    final second = await call('subtitle.tracks',
        {'limit': 1, 'afterFileId': first['nextAfterFileId']});
    final observed = [
      for (final page in [first, second])
        for (final item in page['files'] as List) item['fileId']
    ];
    expect(observed, unorderedEquals(ids));
    expect(second['nextAfterFileId'], isNull);
  });

  test(
      'edits reject stale revision; detach retains copies and provenance; shared copy cannot be deleted; reset differs from disable',
      () async {
    final a = await f.file('a.mkv'), b = await f.file('b.mkv');
    final source = File('${f.root.path}/source.srt');
    await source.writeAsString(
        '1\n00:00:00,000 --> 00:00:05,000\nPublic domain fixture\n');
    final result = await call('subtitle.import', {
      'entries': [
        for (final id in [a, b])
          {
            'fileId': id,
            'filePath': source.path,
            'language': 'en',
            'source': {'label': 'CC0'}
          }
      ]
    });
    final track = ((result['entries'] as List).first['track'] as JsonMap);
    await call('subtitle.select', {'fileId': a, 'trackId': null});
    final reset = await call('subtitle.reset_selection', {
      'entries': [
        {'fileId': a}
      ]
    });
    expect(
        (((reset['entries'] as List).single['facts'] as Map)['selection']
            as Map)['basis'],
        'language_preference');
    var facts = await library.facts(a);
    final edit = {
      'fileId': a,
      'trackId': track['id'],
      'expectedRevision': facts['revision'],
      'patch': {
        'language': 'zh-Hant',
        'title': 'Traditional',
        'source': {'label': 'corrected'}
      }
    };
    await call('subtitle.update', {
      'entries': [edit]
    });
    final stale = await call('subtitle.update', {
      'entries': [edit]
    });
    expect((stale['entries'] as List).single['error']['code'], 'conflict');
    for (final id in [a, b]) {
      facts = await library.facts(id);
      await call('subtitle.remove', {
        'entries': [
          {
            'fileId': id,
            'trackId': track['id'],
            'expectedRevision': facts['revision']
          }
        ]
      });
      expect(await File(track['path'] as String).exists(), true);
      if (id == a) {
        final referenced = await harness.invokeJson(
            'subtitle.copy_delete',
            {
              'paths': [track['path']]
            },
            Invocation(origin: 'mcp'));
        expect(referenced, isA<Failed>());
      }
    }
    final preview = await harness.invokeJson(
        'subtitle.copy_delete',
        {
          'paths': [track['path']]
        },
        Invocation(origin: 'mcp'));
    expect(preview, isA<NeedsDecision>());
    final action = (preview as NeedsDecision).decision.options.single.call;
    await call(action.actionId, action.input);
    expect(await File(track['path'] as String).exists(), false);
    expect(
        await f.identities.database.query('body_changes',
            where: 'type=?', whereArgs: ['subtitle.remove']),
        hasLength(2));
  });
}
