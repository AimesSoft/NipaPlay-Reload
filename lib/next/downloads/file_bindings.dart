import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';

import '../media/identity_store.dart' show stableMediaId;
import '../media/media_service.dart';

const _refKeys = {'provider', 'objectType', 'externalId', 'scope'};

/// Validates the `fileBindings` declared by `download.add` and returns them
/// normalized. [fileCount] is known for torrent files and null for magnets,
/// whose manifest only exists after the engine fetched the metadata.
/// [fileIndices] is the selection the files must lie in, when it is known;
/// [selection] names it in the message.
List<JsonMap> parseFileBindings(Object? raw,
    {int? fileCount,
    List<int>? fileIndices,
    String selection = 'fileIndices'}) {
  if (raw is! List || raw.isEmpty) {
    throw const Failure(
        FailureCode.invalidInput, 'fileBindings must be a non-empty array.');
  }
  final seen = <int>{};
  final result = <JsonMap>[];
  for (var i = 0; i < raw.length; i++) {
    Failure bad(String message) =>
        Failure(FailureCode.invalidInput, 'fileBindings[$i]: $message');
    final entry = raw[i];
    if (entry is! Map) throw bad('expected an object.');
    final index = entry['fileIndex'];
    if (index is! int || index < 0) {
      throw bad('fileIndex must be a non-negative integer.');
    }
    if (!seen.add(index)) throw bad('fileIndex $index is declared twice.');
    if (fileCount != null && index >= fileCount) {
      throw bad('fileIndex $index does not exist; the torrent has '
          '$fileCount files.');
    }
    if (fileIndices != null && !fileIndices.contains(index)) {
      throw bad('fileIndex $index is not in $selection, so it is not downloaded.');
    }
    final unknown = entry.keys
        .where((k) => !const {
              'fileIndex',
              'workRef',
              'releaseRef',
              'episodeRefs',
              'reason'
            }.contains(k))
        .toList();
    if (unknown.isNotEmpty) throw bad('unknown fields $unknown.');
    JsonMap ref(Object? value, String name) {
      if (value is! Map ||
          !_refKeys.every((k) => value[k] is String) ||
          value.keys.any((k) => !_refKeys.contains(k)) ||
          (value['provider'] as String).isEmpty ||
          (value['objectType'] as String).isEmpty ||
          (value['externalId'] as String).isEmpty) {
        throw bad('$name must be {provider, objectType, externalId, scope}.');
      }
      return {for (final k in _refKeys) k: value[k]};
    }

    final workRef = ref(entry['workRef'], 'workRef');
    final episodes = entry['episodeRefs'];
    if (episodes is! List || episodes.isEmpty) {
      throw bad('episodeRefs must list at least one episode.');
    }
    final refs = [
      for (var j = 0; j < episodes.length; j++)
        ref(episodes[j], 'episodeRefs[$j]')
    ];
    if (refs.map(jsonEncode).toSet().length != refs.length) {
      throw bad('episodeRefs must be distinct.');
    }
    final reason = entry['reason'];
    if (reason != null && (reason is! String || reason.isEmpty)) {
      throw bad('reason must be a non-empty string.');
    }
    result.add({
      'fileIndex': index,
      'workRef': workRef,
      if (entry['releaseRef'] != null)
        'releaseRef': ref(entry['releaseRef'], 'releaseRef'),
      'episodeRefs': refs,
      if (reason != null) 'reason': reason,
    });
  }
  return result;
}

/// The stable id of one file's binding request: replays return the saved
/// result instead of binding again. A declaration made with
/// `download.declare_files` carries a [declarationId] derived from its
/// content, so a changed declaration is a new request while the same one
/// stays a replay.
String fileBindingRequestId(String jobId, int fileIndex,
        {String? declarationId}) =>
    'download:$jobId:file:$fileIndex${declarationId == null ? '' : ':$declarationId'}';

/// What `download.declare_files` stores for one validated entry: the
/// normalized entry plus who declared it and a digest of its content.
JsonMap declaredByAction(JsonMap entry, String origin) => {
      ...entry,
      'declarationId': stableMediaId('declaration', entry).substring(12, 36),
      'declaredWith': 'download.declare_files',
      'origin': origin,
    };

/// The declarations in force for [job]: those given with `download.add`,
/// replaced per file index by those of `download.declare_files`.
List<JsonMap> effectiveFileBindings(Job job) {
  final byIndex = <int, JsonMap>{};
  for (final source in [
    job.input['fileBindings'],
    job.checkpoint['fileBindings']
  ]) {
    for (final entry in source as List? ?? []) {
      byIndex[(entry as Map)['fileIndex'] as int] =
          Map<String, Object?>.from(entry);
    }
  }
  return [for (final index in byIndex.keys.toList()..sort()) byIndex[index]!];
}

JsonMap? fileBindingFor(Job job, int index) {
  for (final entry in effectiveFileBindings(job)) {
    if (entry['fileIndex'] == index) return entry;
  }
  return null;
}

/// Binds one downloaded file with the logic of `media.identity.bind_batch`
/// (catalogue mode, kind=file) and returns that batch's single entry.
Future<JsonMap> bindDownloadedFile(MediaService media,
    {required String fileId,
    required JsonMap declaration,
    required String requestId,
    required String origin}) async {
  final index = declaration['fileIndex'];
  final declaredWith = declaration['declaredWith'] ?? 'download.add';
  final result = await media.bindBatch({
    'requestId': requestId,
    'entries': [
      {
        'kind': 'file',
        'entityId': fileId,
        'workRef': declaration['workRef'],
        if (declaration['releaseRef'] != null)
          'releaseRef': declaration['releaseRef'],
        'episodeRefs': declaration['episodeRefs'],
        'reason': declaration['reason'] ??
            'Declared with $declaredWith for file index $index.',
        'evidence': [
          {
            'source': declaredWith,
            'detail': 'File index $index of the download was declared as these '
                '${declaredWith == 'download.add' ? 'episodes when the download was ordered.' : 'episodes with $declaredWith.'}'
          }
        ],
      }
    ]
  }, Invocation(origin: origin, id: requestId));
  return (result['entries'] as List).single as JsonMap;
}
