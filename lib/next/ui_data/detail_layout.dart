import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../media/file_identity_merge.dart' show canonicalFileId;
import '../media/presentation.dart';
import '../media/presentation_store.dart';
import 'service.dart';

/// Where each part of a work's page comes from, for the agent: the page's
/// places, the field each shows, the rule that picks its source.
const detailPageSlots = <JsonMap>[
  {'slot': 'hero.title', 'shows': 'title', 'chosenBy': 'sources.title'},
  {
    'slot': 'hero.originalTitle',
    'shows': 'originalTitle (above the title)',
    'chosenBy': 'sources.originalTitle'
  },
  {
    'slot': 'hero.meta',
    'shows': 'year, episode count or runtime, studio, then ratings',
    'chosenBy': 'sources.year/episodeCount/runtimeMs/studio; ratings'
  },
  {'slot': 'copy.overview', 'shows': 'overview', 'chosenBy': 'sources.overview'},
  {
    'slot': 'section.characters',
    'shows': 'Bangumi characters with who voices them',
    'chosenBy': 'sections, limits.characters'
  },
  {
    'slot': 'section.cast',
    'shows':
        'TMDB credits.cast (character played), or Bangumi voices (character voiced)',
    'chosenBy': 'sources.people, sections, limits.cast'
  },
  {
    'slot': 'section.crew',
    'shows':
        'TMDB creators and credits.crew (director, original story, series composition, music…), or Bangumi staff',
    'chosenBy': 'sources.people, sections, limits.crew'
  },
  {
    'slot': 'section.gallery',
    'shows': "TMDB images of the work's tv/movie identity, read when shown",
    'chosenBy': 'sections, limits.gallery'
  },
  {
    'slot': 'section.facts',
    'shows':
        'original title, genres, first aired/released, ended, status, seasons and episodes, runtime, Bangumi platform, networks, studios, countries, original language, budget and revenue (films), tags',
    'chosenBy': 'sources.genres, sources.tags, sections'
  },
  {
    'slot': 'section.links',
    'shows': 'TMDB, Bangumi, IMDb, 弹弹play and official pages of its identities',
    'chosenBy': 'sections'
  },
];

/// The page's places as they stand for one work: what each shows now,
/// from which provider, and what the other providers would show instead.
JsonMap presentationFacts(Map metadata) {
  final fields = (metadata['fields'] as Map?) ?? const {};
  final provenance = (metadata['provenance'] as Map?) ?? const {};
  final sources = [
    for (final s in (metadata['sources'] as List? ?? const []).whereType<Map>())
      if (s['fields'] is Map &&
          const {'tv', 'movie', 'subject', 'anime'}.contains(s['objectType']))
        s
  ];
  Object? summary(Object? value) => switch (value) {
        final String s => s.length > 80 ? '${s.substring(0, 80)}…' : s,
        final List l => l.length > 3
            ? '${l.take(3).map(summary).join(' / ')} …(${l.length})'
            : l.map(summary).join(' / '),
        final Map m => m['name'] ?? m['value'] ?? '…',
        _ => value,
      };
  final presentation = (metadata['presentation'] as Map?) ?? const {};
  return {
    'rule': presentation['rule'] ?? const {},
    if (presentation['global'] != null) 'global': presentation['global'],
    if (presentation['work'] != null) 'work': presentation['work'],
    'fields': [
      for (final field in PresentationRule.fields.keys)
        if (field != 'people')
          {
            'field': field,
            'slot': PresentationRule.fields[field],
            'value': summary(fields[field]),
            'source': (provenance[field] as Map?)?['provider'],
            'edited': (provenance[field] as Map?)?.containsKey('mode') ?? false,
            'alternatives': [
              for (final s in sources)
                if ((s['fields'] as Map)[field] case final Object v
                    when v != '' && !(v is List && v.isEmpty))
                  {
                    'provider': s['provider'],
                    'language': s['language'],
                    'value': summary(v),
                  }
            ],
          }
    ],
    'ratings': {
      'shown': [
        for (final r in (metadata['ratings'] as List? ?? const []).whereType<Map>())
          {'source': r['source'], 'value': r['value']}
      ],
      'available': [
        for (final s in sources)
          if ((s['fields'] as Map)['rating'] case final Map r)
            {'source': s['provider'], 'value': r['value']}
      ],
    },
    'people': {
      for (final s in sources)
        if (s['provider'] == 'tmdb' || s['provider'] == 'bangumi')
          s['provider'] as String: {
            'cast': ((s['fields'] as Map)['credits'] as Map?)?['cast'] is List
                ? (((s['fields'] as Map)['credits'] as Map)['cast'] as List).length
                : 0,
            'crew': ((s['fields'] as Map)['credits'] as Map?)?['crew'] is List
                ? (((s['fields'] as Map)['credits'] as Map)['crew'] as List).length
                : 0,
            'staff': ((s['fields'] as Map)['staff'] as List?)?.length ?? 0,
            'characters':
                ((s['fields'] as Map)['characters'] as List?)?.length ?? 0,
          }
    },
    'slots': detailPageSlots,
  };
}

extension UiDetailLayout on UiDataService {
  /// The rules a work's page follows: the defaults, this device's, and the
  /// work's own when [workId] is given.
  Future<JsonMap> detailLayout({String? workId}) async {
    final global = await readGlobalPresentationRow(db);
    JsonMap? work;
    String? entity;
    if (workId != null) {
      entity = await _localWork(workId);
      final rows = await db.query('media_overrides',
          where: "entity_id=? AND field='presentation'", whereArgs: [entity]);
      if (rows.isNotEmpty) {
        final row = rows.single;
        work = {
          'rule': PresentationRule.tryParse(jsonDecode(row['value'] as String))
              ?.toJson(),
          'changedAt': row['changed_at'],
          'actor': row['actor'],
          'origin': row['origin'],
          'invocationId': row['invocation_id'],
        };
      }
    }
    final globalRule = PresentationRule.tryParse(global?['rule']);
    final workRule = PresentationRule.tryParse(work?['rule']);
    return {
      'defaults': PresentationRule.defaults(),
      'global': global,
      if (workId != null) ...{'workId': entity, 'work': work},
      'effective':
          (workRule?.over(globalRule) ?? globalRule ?? const PresentationRule())
              .toJson(),
      'slots': detailPageSlots,
    };
  }

  /// Replaces the rule of [scope] (`global`, or a work of this device), or
  /// removes it with [reset]; the page rebuilds at once.
  Future<JsonMap> setDetailLayout(JsonMap input, Invocation invocation) async {
    final scope = input['scope'] as String;
    final reset = input['reset'] == true;
    if (!reset && input['rule'] == null) {
      throw const Failure(
          FailureCode.invalidInput, 'Give a rule, or reset: true.');
    }
    final rule = reset ? null : PresentationRule.parse(input['rule']);
    if (scope == 'global') {
      if (rule == null) {
        await db.delete('media_presentation', where: "id='global'");
      } else {
        await db.insert(
            'media_presentation',
            {
              'id': 'global',
              'payload': jsonEncode(rule.toJson()),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
              'origin': invocation.origin,
              'invocation_id': invocation.id,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } else {
      final entity = await _localWork(scope);
      await media.store.overrideFields([
        {
          'entityId': entity,
          'field': 'presentation',
          'value': rule?.toJson(),
          'mode': rule == null ? 'clear' : 'persistent',
        }
      ], invocation);
    }
    notifyLibraryChanged();
    return {
      'scope': scope,
      'reset': reset,
      if (rule != null) 'rule': rule.toJson(),
      ...await detailLayout(workId: scope == 'global' ? null : scope),
    };
  }

  /// A work entity of this device's library; a merged library ID names
  /// its owners through media.management.targets.
  Future<String> _localWork(String workId) async {
    var id = workId;
    if (meshLibrary case final mesh? when workId.startsWith('mesh-')) {
      final entry = ((await mesh.managementTargets([workId]))['entries']
              as List)
          .cast<Map>()
          .single;
      final local = [
        for (final t in (entry['targets'] as List? ?? const []).cast<Map>())
          if (t['local'] == true) t['workId'] as String
      ].firstOrNull;
      if (local == null) {
        throw const Failure(FailureCode.invalidInput,
            'This merged work is not on this device; set its rule on the device that holds it (media.management.targets names it).');
      }
      id = local;
    }
    id = await canonicalFileId(db, id);
    final rows = await db.query('media_entities',
        columns: ['kind'], where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty || rows.single['kind'] != 'work') {
      throw const Failure(
          FailureCode.notFound, 'workId must identify a library work.');
    }
    return id;
  }
}
