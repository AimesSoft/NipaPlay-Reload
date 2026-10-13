import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../media/file_identity_merge.dart';
import '../public_url.dart';
import 'detection.dart';
import 'operations.dart';

Future<JsonMap> mutateSubtitleFacts(SubtitleOperations library, String fileId,
    String operation, JsonMap input, Invocation invocation,
    {Future<JsonMap?> Function(JsonMap)? defaultSelection}) async {
  final id = await canonicalFileId(library.db, fileId);
  final value = await library.facts(id);
  final before = jsonDecode(jsonEncode(value));
  final revision = value['revision'] as int? ?? 0;
  if (input['expectedRevision'] != null &&
      input['expectedRevision'] != revision) {
    throw const Failure(FailureCode.conflict,
        'Subtitle facts changed; read tracks and retry with current revision.');
  }
  final tracks = (value['tracks'] as List).cast<JsonMap>().toList();
  JsonMap? removed;
  if (operation == 'reset_selection') {
    value['selection'] = null;
    value['automaticSelection'] = true;
  } else {
    final index = tracks.indexWhere((t) => t['id'] == input['trackId']);
    if (index < 0) {
      throw const Failure(
          FailureCode.notFound, 'Subtitle track not found for file.');
    }
    final track = tracks[index];
    if (track['origin'] != 'import') {
      throw const Failure(FailureCode.invalidInput,
          'Only imported tracks have editable persistent associations.');
    }
    if (operation == 'remove') {
      removed = tracks.removeAt(index);
      value['detachedPaths'] = [
        ...(value['detachedPaths'] as List? ?? []),
        removed['path'],
        if (removed['playbackPath'] != null) removed['playbackPath']
      ];
      if ((value['selection'] as Map?)?['trackId'] == removed['id']) {
        value['selection'] = null;
      }
    } else {
      final patch = input['patch'] as JsonMap;
      if (patch.isEmpty) {
        throw const Failure(
            FailureCode.invalidInput, 'patch must change a field.');
      }
      final language = patch['language'] as String?;
      final url = (patch['source'] as Map?)?['url'] as String?;
      if (language != null &&
              !RegExp(r'^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*$')
                  .hasMatch(language) ||
          url != null &&
              (!url.startsWith('https://') || redactPrivateUrls(url) != url)) {
        throw const Failure(FailureCode.invalidInput,
            'Use BCP-47 language and public HTTPS source URL.');
      }
      tracks[index] = {
        ...track,
        ...patch,
        if (language != null) 'language': subtitleLanguage(language),
        if (language != null) 'declaredLanguage': language,
        'editedAt': DateTime.now().toUtc().toIso8601String(),
        'originInvocation': invocation.origin,
        'invocationId': invocation.id
      };
    }
  }
  value['tracks'] = tracks;
  if (defaultSelection != null) {
    value['selection'] = await defaultSelection(value);
  }
  value['revision'] = revision + 1;
  await library.db.transaction((tx) async {
    await tx.insert(
        'file_subtitles', {'file_id': id, 'facts': jsonEncode(value)},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await tx.insert('body_changes', {
      'at': DateTime.now().toUtc().toIso8601String(),
      'type': 'subtitle.$operation',
      'subject_id': id,
      'actor': invocation.origin == 'gui' ? 'user' : 'agent',
      'origin': invocation.origin,
      'invocation_id': invocation.id,
      'facts': jsonEncode({'before': before, 'after': value})
    });
  });
  return {
    'fileId': id,
    'facts': value,
    'copyRetained': true,
    'factsCommitted': true,
    if (removed != null) 'removedTrack': removed
  };
}
