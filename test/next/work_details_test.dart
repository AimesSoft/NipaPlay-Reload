import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/presentation.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/ui/detail/more_sections.dart';
import 'package:nipaplay/next/ui_data/detail_layout.dart';
import 'package:nipaplay/next/ui_data/work_more.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A TMDB series and a Bangumi subject, as their snapshots keep them.
const _tmdb = {
  'title': '孤独摇滚！',
  'originalTitle': 'ぼっち・ざ・ろっく！',
  'overview': 'TMDB 的简介',
  'rating': {'value': 8.6, 'max': 10},
  'genres': ['动画', '喜剧'],
  'firstAirDate': '2022-10-09',
  'lastAirDate': '2022-12-25',
  'status': 'Ended',
  'seasonCount': 1,
  'episodeCount': 12,
  'countries': ['JP'],
  'originalLanguage': 'ja',
  'networks': [
    {'name': 'Tokyo MX'}
  ],
  'studios': ['CloverWorks'],
  'tags': ['band', 'music'],
  'externalIds': {'imdb_id': 'tt23070474'},
  'homepage': 'https://bocchi.rocks/',
  'creators': [
    {'id': 9, 'name': 'Creator Person'}
  ],
  'credits': {
    'cast': [
      {'id': 1, 'name': '青山吉能', 'role': '后藤一里', 'imageUrl': 'https://img/1.jpg'},
      {'id': 2, 'name': '铃代纱弓', 'role': '伊地知虹夏'},
    ],
    'crew': [
      {'id': 3, 'name': '斋藤圭一郎', 'role': 'Director / Screenplay'},
      {'id': 4, 'name': '吉田恵里香', 'role': 'Series Composition'},
      {'id': 5, 'name': 'Someone', 'role': 'Key Grip'},
    ],
  },
};

const _bangumi = {
  'title': '孤独摇滚！',
  'overview': 'Bangumi 的简介，比较长一些的一段文字。',
  'rating': {'value': 8.9, 'max': 10},
  'tags': [
    {'name': '音乐', 'count': 30},
    {'name': '百合', 'count': 90},
  ],
  'platform': 'TV',
  'staff': [
    {'id': 11, 'name': '斎藤圭一郎', 'relation': '导演'},
    {'id': 11, 'name': '斎藤圭一郎', 'relation': '分镜'},
    {'id': 12, 'name': 'はまじあき', 'relation': '原作'},
  ],
  'characters': [
    {
      'id': 21,
      'name': '後藤ひとり',
      'relation': '主角',
      'images': {'medium': 'https://bgm/c21.jpg'},
      'actors': [
        {'id': 31, 'name': '青山吉能', 'images': {'medium': 'https://bgm/p31.jpg'}}
      ],
    },
  ],
};

Map<String, Object?> _metadata({Map<String, Object?>? rule}) => {
      'fields': {..._tmdb},
      'sources': [
        {'provider': 'tmdb', 'objectType': 'tv', 'externalId': '119100', 'fields': _tmdb},
        {'provider': 'bangumi', 'objectType': 'subject', 'externalId': '328609', 'fields': _bangumi},
      ],
      if (rule != null) 'presentation': {'rule': rule},
    };

void main() {
  group('a rule', () {
    test('names only fields, providers and sections it knows', () {
      expect(() => PresentationRule.parse({'sources': {'plot': ['tmdb']}}),
          throwsA(isA<Failure>()));
      expect(() => PresentationRule.parse({'ratings': ['douban']}),
          throwsA(isA<Failure>()));
      expect(() => PresentationRule.parse({'sections': ['comments']}),
          throwsA(isA<Failure>()));
      expect(() => PresentationRule.parse({'limits': {'cast': 0}}),
          throwsA(isA<Failure>()));
      final rule = PresentationRule.parse({
        'sources': {'overview': ['bangumi', 'tmdb']},
        'ratings': ['bangumi'],
        'sections': ['cast', 'facts'],
        'limits': {'cast': 5},
      });
      expect(rule.toJson()['sources'], {'overview': ['bangumi', 'tmdb']});
      // A work's rule wins part by part over the global one.
      final over = PresentationRule.parse({'ratings': ['tmdb']})
          .over(rule);
      expect(over.ratings, ['tmdb']);
      expect(over.sections, ['cast', 'facts']);
    });
  });

  group('the page below the episodes', () {
    test('characters stand for the cast by default; crew in TMDB jobs', () {
      final more = UiWorkMore.fromJson(buildWorkMore(_metadata()));
      expect(more.sections, isNot(contains('cast')));
      expect(more.characters.single.name, '後藤ひとり');
      expect(more.characters.single.actors.single.person,
          (provider: 'bangumi', id: '31'));
      expect([for (final c in more.crew) (c.name, c.role)], [
        ('Creator Person', '主创'),
        ('斋藤圭一郎', '导演 · 编剧'),
        ('吉田恵里香', '系列构成'),
      ]);
      final facts = {for (final f in more.facts) f.label: f.value};
      expect(facts['原名'], 'ぼっち・ざ・ろっく！');
      expect(facts['状态'], '已完结');
      expect(facts['首播'], '2022 年 10 月 9 日');
      expect(facts['国家/地区'], '日本');
      expect(facts['原始语言'], '日语');
      expect(facts['形式'], 'TV');
      expect([for (final l in more.links) l.label],
          ['TMDB', 'Bangumi', 'IMDb', '官网']);
      expect(more.gallery, (objectType: 'tv', id: '119100'));
    });

    test('a rule orders and hides sections and chooses whose people', () {
      final more = UiWorkMore.fromJson(buildWorkMore(_metadata(rule: {
        'sections': ['cast', 'crew', 'facts'],
        'sources': {'people': ['bangumi']},
        'limits': {'cast': 1},
      })));
      expect(more.sections, ['cast', 'crew', 'facts']);
      expect(more.cast.single.name, '青山吉能');
      expect(more.cast.single.role, '後藤ひとり');
      expect([for (final c in more.crew) (c.name, c.role)],
          [('斎藤圭一郎', '导演 · 分镜'), ('はまじあき', '原作')]);
    });

    test('Bangumi tags most given first', () {
      final more = UiWorkMore.fromJson(buildWorkMore({
        ..._metadata(),
        'fields': {'tags': _bangumi['tags']},
      }));
      expect(more.tags, ['百合', '音乐']);
    });

    test('the agent sees each place, its source and the alternatives', () {
      final facts = presentationFacts({
        ..._metadata(),
        'provenance': {
          'overview': {'provider': 'tmdb'}
        },
        'ratings': [
          {'source': 'tmdb', 'value': 8.6}
        ],
      });
      final overview = (facts['fields'] as List)
          .cast<Map>()
          .singleWhere((f) => f['field'] == 'overview');
      expect(overview['slot'], 'copy.overview');
      expect(overview['source'], 'tmdb');
      expect([for (final a in overview['alternatives'] as List) a['provider']],
          ['tmdb', 'bangumi']);
      expect((facts['ratings'] as Map)['available'], hasLength(2));
      expect(facts['slots'], detailPageSlots);
    });
  });

  group('merged metadata follows the rule', () {
    late Directory root;
    late Database db;
    late IdentityStore store;
    setUp(() async {
      sqfliteFfiInit();
      root = await Directory.systemTemp.createTemp('presentation-');
      db = await openNextDatabase(root, factory: databaseFactoryFfi);
      store = IdentityStore(db, 'fixture');
      await db.insert('media_entities', {
        'id': 'w1',
        'kind': 'work',
        'attributes': jsonEncode({'title': 'w1'})
      });
      for (final (provider, type, id, fields) in [
        ('tmdb', 'tv', '119100', _tmdb),
        ('bangumi', 'subject', '328609', _bangumi),
      ]) {
        await db.insert('media_external_objects', {
          'id': 'o-$provider',
          'provider': provider,
          'object_type': type,
          'external_id': id,
          'scope': ''
        });
        await db.insert('media_bindings', {
          'id': 'b-$provider',
          'entity_id': 'w1',
          'object_id': 'o-$provider',
          'relation': 'exact',
          'scope': '',
          'status': 'accepted',
          'source': 'test',
          'bound_by': 'agent',
          'revision': 1,
          'created_at': '2026-10-30T00:00:00Z'
        });
        await db.insert('media_snapshots', {
          'id': 's-$provider',
          'object_id': 'o-$provider',
          'language': 'zh-CN',
          'fetched_at': '2026-10-30T00:00:00Z',
          'fields': jsonEncode({'source': 'provider_snapshot', 'metadata': fields})
        });
      }
    });
    tearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });

    test('defaults are what the library always did', () async {
      final m = await store.mergedMetadata('w1');
      // Same language: the longer overview; ratings of both.
      expect((m['fields'] as Map)['overview'], _bangumi['overview']);
      expect([for (final r in m['ratings'] as List) r['source']],
          containsAll(['tmdb', 'bangumi']));
      expect((m['presentation'] as Map)['rule'], isEmpty);
    });

    test('the global rule, then the work\'s over it', () async {
      await db.insert('media_presentation', {
        'id': 'global',
        'payload': jsonEncode({
          'sources': {
            'overview': ['tmdb']
          },
          'ratings': ['bangumi', 'tmdb']
        }),
        'updated_at': '2026-10-30T00:00:00Z',
        'origin': 'test',
        'invocation_id': 'i1'
      });
      var m = await store.mergedMetadata('w1');
      expect((m['fields'] as Map)['overview'], 'TMDB 的简介');
      expect([for (final r in m['ratings'] as List) r['source']],
          ['bangumi', 'tmdb']);

      await store.overrideFields([
        {
          'entityId': 'w1',
          'field': 'presentation',
          'value': {
            'ratings': ['tmdb']
          }
        }
      ], Invocation(origin: 'test'));
      m = await store.mergedMetadata('w1');
      expect([for (final r in m['ratings'] as List) r['source']], ['tmdb']);
      // The overview still follows the global rule; the rule is no field.
      expect((m['fields'] as Map)['overview'], 'TMDB 的简介');
      expect((m['fields'] as Map).containsKey('presentation'), isFalse);
      expect((m['presentation'] as Map)['work'], {
        'ratings': ['tmdb']
      });
    });
  });

  testWidgets('sections show what there is, in order', (tester) async {
    final more = UiWorkMore.fromJson(buildWorkMore(_metadata()));
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1400, 900)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: WorkMoreSections(
            more: more,
            gallery: null,
            onPerson: (_) {},
            onLink: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('角色'), findsOneWidget);
    expect(find.text('演员'), findsNothing);
    expect(find.text('制作人员'), findsOneWidget);
    expect(find.text('信息'), findsOneWidget);
    expect(find.text('TMDB  ↗'), findsOneWidget);
    final characters = tester.getTopLeft(find.text('角色')).dy;
    final crew = tester.getTopLeft(find.text('制作人员')).dy;
    expect(characters, lessThan(crew));
  });
}
