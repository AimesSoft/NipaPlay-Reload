import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/media_sources/capability.dart';
import 'package:nipaplay/next/media_sources/service.dart';
import 'package:nipaplay/next/ui_data/library_search.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('source keystrokes preserve files, bindings and discovery journal',
      () async {
    final fixture = MediaFixture();
    await fixture.open(sources: []);
    final service = MediaSourcesService(fixture.identities);
    SharedPreferences.setMockInitialValues({
      'server_profiles': '[]',
      'smb_connections': '[]',
      'webdav_connections': jsonEncode([
        {
          'id': 'x56-index',
          'name': 'X56 indexed',
          'url': 'http://127.0.0.1:1',
          'username': '',
          'isConnected': false,
        }
      ]),
    });
    await service.ensureInitialized();
    addTearDown(() async {
      await service.close();
      await fixture.close();
    });
    final fileId = await fixture.identities.ensureRemoteFile(
        'webdav://x56-index/奇幻 100%_sample.mkv', 'webdav:x56-index', {
      'itemId': '/奇幻 100%_sample.mkv',
      'name': '奇幻 100%_sample.mkv',
      'type': 'webdav',
    });
    final before =
        await fixture.jobs.database.rawQuery('SELECT total_changes() AS n');
    final harness = Harness([MediaSourcesCapability(service)]);
    expect(harness.lookup('media.sources.search')!.spec.effect, Effect.read);
    for (final term in ['奇', '奇幻', '100%', '%_', '_sample']) {
      final outcome = await harness.invokeJson(
          'media.sources.search',
          {
            'query': term,
            'sourceIds': ['webdav:x56-index', 'webdav:missing'],
            'limit': 1,
          },
          Invocation(origin: 'gui'));
      expect(outcome, isA<Completed>());
      final sources = (outcome as Completed).value.toJson()['sources'] as List;
      expect((sources.first as Map)['basis'], 'indexed');
      expect((sources.first as Map)['connectionState'], 'unverified');
      final entry = ((sources.first as Map)['entries'] as List).single as Map;
      expect(entry['fileId'], fileId);
      expect(entry['workId'], isNull);
      expect(entry['playable'], false);
      expect((sources.last as Map)['error'], isNotNull);
    }
    final empty = await service.search('100X', sourceIds: ['webdav:x56-index']);
    expect(((empty['sources'] as List).single as Map)['entries'], isEmpty);
    expect(await fixture.jobs.database.rawQuery('SELECT total_changes() AS n'),
        before);
    expect(await fixture.jobs.database.query('media_bindings'), isEmpty);
  });

  test(
      'online membership uses accepted work identity, never title or candidate',
      () async {
    final fixture = MediaFixture();
    await fixture.open(sources: ['dandanplay']);
    addTearDown(fixture.close);
    final db = fixture.jobs.database;
    await db.insert('media_entities', {
      'id': 'different-title',
      'kind': 'work',
      'attributes': '{"title":"译名完全不同"}',
    });
    await db.insert('media_entities', {
      'id': 'release',
      'kind': 'release',
      'parent_id': 'different-title',
      'attributes': '{}',
    });
    await db.insert('media_external_objects', {
      'id': 'external',
      'provider': 'dandanplay',
      'object_type': 'anime',
      'scope': '',
      'external_id': '7001',
    });
    await db.insert('media_bindings', {
      'id': 'binding',
      'entity_id': 'release',
      'object_id': 'external',
      'relation': 'contains',
      'scope': '{}',
      'status': 'proposed',
      'source': 'fixture',
      'revision': 0,
      'created_at': '2026-10-13T00:00:00Z',
    });
    for (final status in ['proposed', 'rejected', 'revoked', 'accepted']) {
      await db.update('media_bindings', {'status': status});
      final before = await db.rawQuery('SELECT total_changes() AS n');
      final result = await fixture.call(
          'media.metadata.search', {'provider': 'dandanplay', 'query': '动画'});
      expect(((result['results'] as List).single as Map)['workId'],
          status == 'accepted' ? 'different-title' : null);
      expect(await db.rawQuery('SELECT total_changes() AS n'), before);
    }
  });

  test('rebuilding the projection replaces membership, IDs and offline facts',
      () {
    final index = LibrarySearchIndex();
    JsonMap row(String id, bool playable) => {
          'id': id,
          'added': 1,
          'payload': {
            'workId': id,
            'title': '中文片名',
            'originalTitle': 'Original',
            'year': 2026
          },
          'facts': {
            'identityKeys': [
              jsonEncode(['dandanplay', 'work', '', '7001'])
            ],
            'searchTitles': ['另一译名'],
            'searchEpisodes': [
              {
                'episode': {
                  'episodeId': '$id-episode',
                  'workId': id,
                  'title': '旅途',
                  'playable': playable
                },
                'titles': ['旅程']
              }
            ],
          },
        };
    index.replace([row('old', true)]);
    index.replace([row('new', false)]);
    expect(
        index.workId(const ExternalRef('dandanplay', 'anime', '7001')), 'new');
    final work = (index.search('另一译名 2026')['works'] as List).single as Map;
    expect(work['workId'], 'new');
    expect(work['playable'], false);
    final episode = ((index.search('旅程')['episodes'] as List).single
        as Map)['episode'] as Map;
    expect(episode['episodeId'], 'new-episode');
    expect(episode['playable'], false);
    final renamed = row('new', true);
    (renamed['payload'] as Map)['title'] = '新名新名';
    (renamed['facts'] as Map)['searchTitles'] = ['更新别名'];
    index.replace([renamed]);
    expect(index.search('中文片名')['works'], isEmpty);
    expect(index.search('另一译名')['works'], isEmpty);
    expect(index.search('新名')['works'], hasLength(1));
    expect(((index.search('更新别名')['works'] as List).single as Map)['playable'], true);
    index.replace([]);
    expect(
        index.workId(const ExternalRef('dandanplay', 'anime', '7001')), isNull);
  });
}
