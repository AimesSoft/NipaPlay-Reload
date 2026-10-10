import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/media_capability.dart';

import 'media_test_support.dart';

final class _Calls implements InvocationObserver {
  final List<String> actions = [];
  @override
  void onInvocation(InvocationRecord record) => actions.add(record.actionId);
}

void main() {
  late MediaFixture f;
  late _Calls calls;
  setUp(() async {
    f = MediaFixture();
    await f.open(sources: ['tmdb', 'dandanplay']);
    calls = _Calls();
    f.harness = Harness([MediaCapability(f.service)], observers: [calls]);
  });
  tearDown(() => f.close());

  test(
      '48 opaque filenames and zero hash matches take one list, two metadata calls and one batch binding',
      () async {
    final season = f.tmdb.responses['/3/tv/9001/season/1'] as Map;
    season['episodes'] = [
      for (var number = 1; number <= 48; number++)
        {
          'id': 9200 + number,
          'name': 'Episode $number',
          'season_number': 1,
          'episode_number': number
        }
    ];
    f.dandanplay.responses['/api/v2/match'] = {
      'isMatched': false,
      'matches': []
    };
    final explicitMapping = <String, int>{};
    for (var number = 1; number <= 48; number++) {
      final name = [
        '任意名-$number',
        'S99E999.$number.2160p',
        'opaque_${49 - number}_movie',
        '完全没有集号_${String.fromCharCode(0x4e00 + number)}'
      ][number % 4];
      final video = await File('${f.media.path}/$name.mkv')
          .writeAsString('offline bytes $number');
      explicitMapping[await video.resolveSymbolicLinks()] = number;
    }
    final list = await f.call('media.files.list', {'root': f.media.path});
    final files = (list['files'] as List).cast<JsonMap>();
    expect(files, hasLength(48));
    expect(
        files.every((file) =>
            file['durationMs'] == 1440000 &&
            file['headMd5'] != null &&
            file['size'] != null &&
            (file['bindings'] as List).isEmpty),
        true);
    await f.call('media.metadata.search_batch', {
      'queries': [
        {'provider': 'tmdb', 'query': '长安十二时辰'}
      ]
    });
    await f.call('media.metadata.get_batch', {
      'refs': [mediaWorkRef, mediaReleaseRef]
    });
    await f.call('media.identity.bind_batch', {
      'requestId': 'whole-season',
      'entries': [
        for (final file in files)
          {
            ...tmdbBinding('', episodes: [explicitMapping[file['path']]!])
              ..remove('entityId'),
            'path': file['path']
          }
      ]
    });
    expect(calls.actions, [
      'media.files.list',
      'media.metadata.search_batch',
      'media.metadata.get_batch',
      'media.identity.bind_batch'
    ]);
    expect(f.tmdb.requests, hasLength(5));
    expect(f.dandanplay.requests, isEmpty);
    expect(await f.engine.list(), isEmpty);
    final links = await f.jobs.database.query('media_file_episodes');
    expect(links, hasLength(48));
    expect(links.map((link) => link['episode_id']).toSet(), hasLength(48));
    final works = await f.identities.library();
    expect(
        (works.single['releases'] as List).single['episodes'], hasLength(48));
    final indexed =
        await f.service.listFiles({'workId': works.single['workId']});
    expect(indexed['files'], hasLength(48));
    expect(
        (indexed['files'] as List)
            .every((file) => (file['bindings'] as List).isNotEmpty),
        true);
  });

  test('48 hash matches take exactly one batch hash call and one batch binding',
      () async {
    final byHash = <String, int>{};
    final paths = <String>[];
    for (var number = 1; number <= 48; number++) {
      final content = 'hash fixture $number';
      final file = await File('${f.media.path}/opaque_${49 - number}.mkv')
          .writeAsString(content);
      paths.add(file.path);
      byHash[md5.convert(utf8.encode(content)).toString()] = number;
    }
    (f.dandanplay.responses['/api/v2/bangumi/7001'] as Map)['bangumi']
        ['episodes'] = [
      for (var number = 1; number <= 48; number++)
        {
          'episodeId': 7100 + number,
          'episodeTitle': 'Episode $number',
          'episodeNumber': '$number'
        }
    ];
    f.dandanplay.handlers['/api/v2/match'] = (body) {
      expect(body!['matchMode'], 'hashOnly');
      final number = byHash[body['fileHash']]!;
      return {
        'isMatched': true,
        'matches': [
          {
            'animeId': 7001,
            'animeTitle': '动画样本',
            'episodeId': 7100 + number,
            'episodeTitle': 'Episode $number',
            'episodeNumber': '$number'
          }
        ]
      };
    };
    final matched = await f.call('media.hash.match', {
      'files': [
        for (final path in paths) {'path': path}
      ]
    });
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
    final rows = (matched['files'] as List).cast<JsonMap>();
    await f.call('media.identity.bind_batch', {
      'requestId': 'hash-batch',
      'entries': [
        for (final row in rows)
          {
            'kind': 'file',
            'path': row['path'],
            'workRef': (row['candidates'] as List).single['ref'],
            'episodeRefs': [
              (row['candidates'] as List).single['episodes'].single['ref']
            ],
            'reason': 'Agent accepts the returned hash signal',
            'evidence': [
              {'source': 'dandanplay.hashOnly', 'detail': row['headMd5']}
            ]
          }
      ]
    });
    expect(calls.actions, ['media.hash.match', 'media.identity.bind_batch']);
    expect(f.dandanplay.requests.where((r) => r['path'] == '/api/v2/match'),
        hasLength(48));
    expect(
        f.dandanplay.requests.where((r) => r['path'] == '/api/v2/bangumi/7001'),
        hasLength(1));
    expect(
        f.dandanplay.requests
            .any((r) => (r['path'] as String).contains('search')),
        false);
    expect(await f.jobs.database.query('media_file_episodes'), hasLength(48));
    expect(f.classic.rows, hasLength(48));
    expect(
        (await f.jobs.database.query('media_bindings'))
            .every((b) => b['bound_by'] == 'agent'),
        true);
  });
}
