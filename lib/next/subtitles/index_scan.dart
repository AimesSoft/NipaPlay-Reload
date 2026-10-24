import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';

import '../media/identity_store.dart';
import 'detection.dart';
import 'webvtt.dart';

/// Everything from Classic that a subtitle scan needs, captured once in the UI
/// isolate before the complete catalogue is handed to the library worker.
final class SubtitleIndexPreferences {
  const SubtitleIndexPreferences({
    required this.videoSubtitleMap,
    required this.languageMode,
    required this.traditional,
    required this.values,
  });

  factory SubtitleIndexPreferences.fromJson(JsonMap json) =>
      SubtitleIndexPreferences(
        videoSubtitleMap: json['videoSubtitleMap'] as String? ?? '{}',
        languageMode: json['languageMode'] as String? ?? 'auto',
        traditional: json['traditional'] as bool? ?? false,
        values: (json['values'] as JsonMap?) ?? const {},
      );

  final String videoSubtitleMap;
  final String languageMode;
  final bool traditional;
  final JsonMap values;

  JsonMap toJson() => {
        'videoSubtitleMap': videoSubtitleMap,
        'languageMode': languageMode,
        'traditional': traditional,
        'values': values,
      };

  ({List<Map<String, dynamic>> subtitles, int? activeIndex}) classicFor(
      String path, int size) {
    final key = '${p.basename(path)}-$size';
    final stored = values['external_subtitles_$key'] as String?;
    return (
      subtitles: stored == null
          ? <Map<String, dynamic>>[]
          : (jsonDecode(stored) as List)
              .map((s) => Map<String, dynamic>.from(s as Map))
              .toList(),
      activeIndex: values['last_active_subtitle_$key'] as int?,
    );
  }
}

/// The complete subtitle pass, kept in one worker message. Results are built
/// and compared here; the UI isolate receives only counters and status.
Future<JsonMap> reconcileSubtitleIndex({
  required Database db,
  required IdentityStore identities,
  required Directory root,
  required List<JsonMap> locations,
  required Future<JsonMap> Function(String) probe,
  required SubtitleIndexPreferences preferences,
}) async {
  final changes = <({String id, JsonMap value, bool initialEmpty})>[];
  var failed = 0;
  String? lastRun, lastError;
  for (final row in locations) {
    final id = row['file_id'] as String;
    final path = row['locator'] as String;
    try {
      final result =
          await _build(db, identities, root, id, path, probe, preferences);
      if (result != null) {
        changes.add((id: id, value: result.$1, initialEmpty: result.$2));
      }
      lastRun = DateTime.now().toUtc().toIso8601String();
      lastError = null;
    } catch (error) {
      failed++;
      lastError = error.runtimeType.toString();
    }
  }
  if (changes.isNotEmpty) {
    final batch = db.batch();
    for (final change in changes) {
      batch.insert('file_subtitles',
          {'file_id': change.id, 'facts': jsonEncode(change.value)},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
  return {
    'scanned': locations.length,
    'changed': changes.length,
    'failed': failed,
    'lastRun': lastRun,
    'error': lastError,
  };
}

Future<(JsonMap, bool)?> _build(
    Database db,
    IdentityStore identities,
    Directory root,
    String id,
    String path,
    Future<JsonMap> Function(String) probe,
    SubtitleIndexPreferences preferences) async {
  final before = await File(path).stat();
  final rows =
      await db.query('file_subtitles', where: 'file_id=?', whereArgs: [id]);
  final old = rows.isEmpty
      ? <String, Object?>{
          'fileId': id,
          'revision': 0,
          'tracks': <JsonMap>[],
          'embeddedStatus': 'pending',
          'selection': null
        }
      : decodeMediaJson(rows.single['facts']);
  final tracks = (old['tracks'] as List).cast<JsonMap>();
  final fingerprint =
      '${before.size}:${before.modified.toUtc().toIso8601String()}';
  final exists = before.type == FileSystemEntityType.file;
  final entity = await identities.entity(id);
  final indexed = (entity['attributes'] as JsonMap)['probe'] as JsonMap;
  final indexedFingerprint = '${indexed['size']}:${indexed['modifiedAt']}';
  final embedded = old['fingerprint'] == fingerprint &&
          old['embeddedStatus'] == 'ready'
      ? null
      : exists
          ? indexed['subtitles'] != null && indexedFingerprint == fingerprint
              ? indexed
              : await probe(path)
          : <String, Object?>{};
  final updated = <JsonMap>[
    if (embedded == null)
      ...tracks.where((t) => t['origin'] == 'embedded')
    else if (embedded['subtitles'] is! List)
      ...tracks
          .where((t) => t['origin'] == 'embedded')
          .map((t) => {...t, 'available': false})
    else
      for (final t in (embedded['subtitles'] as List).cast<Map>())
        {
          'id': 'embedded:${t['index']}',
          'origin': 'embedded',
          ...t,
          'language': subtitleLanguage(t['language'] as String),
          'declaredLanguage': t['language'],
          'languageBasis': 'container',
          'available': true,
          'source': {'label': 'container probe'}
        },
  ];
  if (exists) {
    for (final candidate in await subtitleCandidates(path)) {
      final stat = await File(candidate.path).stat();
      final title = p.basename(candidate.path);
      updated.add({
        'id': stableMediaId('subtitle', candidate.path),
        'origin': 'sidecar',
        'path': candidate.path,
        if (p.extension(candidate.path).toLowerCase() == '.vtt')
          'playbackPath': await prepareWebVtt(candidate.path, root),
        'title': title,
        'format': p.extension(candidate.path).substring(1).toLowerCase(),
        'language': subtitleLanguage(title),
        'languageBasis': 'filename',
        'available': true,
        'matchScore': candidate.score,
        'matchBasis': p.dirname(candidate.path) == p.dirname(path)
            ? 'classic_filename_match'
            : 'single_video_subdirectory',
        'size': stat.size,
        'modifiedAt': stat.modified.toUtc().toIso8601String(),
        'source': {'label': 'adjacent subtitle'}
      });
    }
  }
  for (final t in tracks.where((t) => t['origin'] != 'embedded')) {
    if (updated.any((x) => x['id'] == t['id'])) continue;
    updated.add({
      ...t,
      'available': t['origin'] == 'sidecar'
          ? false
          : await File(t['path'] as String).exists()
    });
  }
  final classic = exists ? preferences.classicFor(path, before.size) : null;
  if (classic != null) {
    for (final t in classic.subtitles) {
      final subPath = t['path'] as String;
      if ((old['detachedPaths'] as List? ?? []).contains(subPath)) continue;
      if (updated
          .any((x) => x['path'] == subPath || x['playbackPath'] == subPath)) {
        continue;
      }
      updated.add({
        'id': stableMediaId('subtitle', subPath),
        'origin': 'classic',
        'path': subPath,
        'title': t['name'] ?? p.basename(subPath),
        'format': p.extension(subPath).substring(1),
        'available': await File(subPath).exists(),
        'language':
            subtitleLanguage(t['name'] as String? ?? p.basename(subPath)),
        'languageBasis': 'filename',
        'source': {'label': 'Classic saved subtitle'}
      });
    }
  }
  final value = <String, Object?>{
    ...old,
    'fileId': id,
    'fingerprint': fingerprint,
    'embeddedStatus': !exists
        ? 'unavailable'
        : embedded == null || embedded.containsKey('subtitles')
            ? 'ready'
            : 'unavailable',
    'tracks': updated
  };
  value['selection'] = _defaultSelection(path, value, preferences, classic);
  if (jsonEncode(old) == jsonEncode(value)) return null;
  value['checkedAt'] = DateTime.now().toUtc().toIso8601String();
  value['revision'] = (old['revision'] as int? ?? 0) + 1;
  return (
    value,
    (old['revision'] as int? ?? 0) == 0 &&
        updated.isEmpty &&
        value['selection'] == null
  );
}

JsonMap? _defaultSelection(
    String path,
    JsonMap facts,
    SubtitleIndexPreferences preferences,
    ({List<Map<String, dynamic>> subtitles, int? activeIndex})? classic) {
  final old = facts['selection'] as JsonMap?;
  final tracks = (facts['tracks'] as List)
      .cast<JsonMap>()
      .where((t) => t['available'] == true)
      .toList();
  if (old?['basis'] == 'explicit' &&
      (old?['trackId'] == null ||
          tracks.any((t) => t['id'] == old?['trackId']))) {
    return old;
  }
  if (tracks.isEmpty) return null;
  final mapping =
      jsonDecode(preferences.videoSubtitleMap) as Map<String, dynamic>;
  final choices = classic?.subtitles ?? const <Map<String, dynamic>>[];
  final active = classic?.activeIndex;
  final previous = tracks
      .where((t) =>
          (mapping[path] is String &&
              (t['path'] == mapping[path] ||
                  t['playbackPath'] == mapping[path])) ||
          (active != null &&
              active >= 0 &&
              active < choices.length &&
              (t['path'] == choices[active]['path'] ||
                  t['playbackPath'] == choices[active]['path'])))
      .firstOrNull;
  if (previous != null &&
      facts['automaticSelection'] != true &&
      !(old?['basis'] == 'language_preference' &&
          old?['trackId'] == previous['id'])) {
    return {'trackId': previous['id'], 'basis': 'classic_choice'};
  }
  final external = tracks
      .where((t) =>
          t['origin'] != 'embedded' &&
          t['format'] != 'idx' &&
          t['format'] != 'sup' &&
          (t['format'] != 'sub' || !isVobSubBinaryFile(t['path'] as String)))
      .toList();
  final preferred = [
    preferences.traditional ? 'zh-Hant' : 'zh-Hans',
    preferences.traditional ? 'zh-Hans' : 'zh-Hant',
    'zh',
    'en'
  ];
  int rank(JsonMap t) {
    final index = preferred.indexOf(t['language'] as String);
    return index < 0 ? 0 : (preferred.length - index) * 100;
  }

  external.sort((a, b) {
    final score = (rank(b) + (b['matchScore'] as int? ?? 0))
        .compareTo(rank(a) + (a['matchScore'] as int? ?? 0));
    return score == 0
        ? (a['id'] as String).compareTo(b['id'] as String)
        : score;
  });
  final embedded = tracks.where((t) => t['origin'] == 'embedded').toList()
    ..sort((a, b) => rank(b).compareTo(rank(a)));
  final chosen = external.firstOrNull ?? embedded.firstOrNull;
  return chosen == null
      ? null
      : {
          'trackId': chosen['id'],
          'basis': 'language_preference',
          'preferredLanguages': preferred,
          'languageMode': preferences.languageMode,
          'externalTextFirst': true
        };
}
