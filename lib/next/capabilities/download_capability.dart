import 'package:nipa_harness/nipa_harness.dart';

import '../downloads/download_backend.dart';
import '../downloads/download_service.dart';
import '../downloads/download_source.dart';
import '../downloads/download_paths.dart';
import '../downloads/file_bindings.dart';
import 'classic_action.dart';

final _downloadJobSchema = ObjectSchema({
  ...jobSnapshotSchema.properties,
  'backend': const ObjectSchema({
    'kind': StringSchema(minLength: 1),
    'id': StringSchema(minLength: 1),
  }, required: [
    'kind'
  ]),
}, required: [
  ...jobSnapshotSchema.required,
  'backend'
], additionalProperties: true);

const _backendSchema = ObjectSchema({
  'kind': StringSchema(minLength: 1),
  'id': StringSchema(minLength: 1),
}, required: [
  'kind'
]);
const _idSchema = StringSchema(minLength: 1);
const _refSchema = ObjectSchema({
  'provider': _idSchema,
  'objectType': _idSchema,
  'externalId': _idSchema,
  'scope': StringSchema(),
}, required: [
  'provider',
  'objectType',
  'externalId',
  'scope'
]);
const _fileBindingsSchema = ArraySchema(
    ObjectSchema({
      'fileIndex': IntegerSchema(minimum: 0),
      'workRef': _refSchema,
      'releaseRef': _refSchema,
      'episodeRefs': ArraySchema(_refSchema, minItems: 1),
      'reason': _idSchema,
    }, required: [
      'fileIndex',
      'workRef',
      'episodeRefs'
    ]),
    minItems: 1);
const _idsSchema = ArraySchema(_idSchema);
const _downloadTaskSchema = ObjectSchema({
  'handle': _idSchema,
  'infoHash': _idSchema,
  'title': StringSchema(),
  'outputDirectory': _idSchema,
  'local': BooleanSchema(),
  'completedBytes': IntegerSchema(minimum: 0),
  'totalBytes': IntegerSchema(minimum: 0),
  'finished': BooleanSchema(),
  'paused': BooleanSchema(),
  'error': StringSchema(nullable: true),
  'state': StringSchema(),
  'downloadSpeedBytesPerSecond': IntegerSchema(minimum: 0),
  'uploadSpeedBytesPerSecond': IntegerSchema(minimum: 0),
  'health': ObjectSchema({}, additionalProperties: true),
  'disk': ObjectSchema({}, additionalProperties: true),
  'files': ArraySchema(ObjectSchema({
    'index': IntegerSchema(minimum: 0),
    'path': _idSchema,
    'local': BooleanSchema(),
    'expectedSize': IntegerSchema(minimum: 0),
    'included': BooleanSchema(),
    'isVideo': BooleanSchema(),
    'completedBytes': IntegerSchema(minimum: 0, nullable: true),
    'actualSize': IntegerSchema(minimum: 0, nullable: true),
    'complete': BooleanSchema(),
    'playable': BooleanSchema(),
    'playbackUnavailableReason': StringSchema(),
    'streamable': BooleanSchema(),
    'imported': BooleanSchema(),
    'identificationPending': BooleanSchema(),
    'media': ObjectSchema({}, additionalProperties: true),
    'declared': BooleanSchema(),
    'binding': ObjectSchema({}, additionalProperties: true),
  }, required: [
    'index',
    'path',
    'local',
    'expectedSize',
    'included',
    'isVideo'
  ])),
}, required: [
  'handle',
  'infoHash',
  'title',
  'outputDirectory',
  'local',
  'completedBytes',
  'totalBytes',
  'finished',
  'paused',
  'error',
  'files'
], nullable: true);

final class DownloadCapability implements Capability {
  DownloadCapability(
      {required DownloadService downloads,
      required DownloadSources sources,
      InvocationObserver? deleteAudit})
      : actions = [
          for (final operation in ['get', 'set'])
            ClassicAction(ActionSpec(id: 'download.limits.$operation', title: '下载会话限速 $operation',
              description: '真实原生内置会话的上传/下载字节预算。0 移除限制，正值至少 16384 字节/秒；省略方向保持现值。返回原生读回值。尚未初始化会话时 applied=false；不自动启动下载器，不改变网关限流。会话重建恢复无限制。',
              effect: operation == 'get' ? Effect.read : Effect.write,
              input: operation == 'get' ? const ObjectSchema({}) : const ObjectSchema({
                'downloadBytesPerSecond': IntegerSchema(minimum: 0, maximum: 4294967295),
                'uploadBytesPerSecond': IntegerSchema(minimum: 0, maximum: 4294967295)}),
              output: const ObjectSchema({}, additionalProperties: true)), (input, _) async {
                if (operation == 'set' && input.isEmpty) {
                  throw const Failure(FailureCode.invalidInput, 'Provide at least one bandwidth direction.');
                }
                return downloads.bandwidth(input);
              }),
          for (final operation in [
            'add',
            'declare_files',
            'set_paused',
            'pause',
            'resume',
            'read',
            'select_files',
            'import',
            'remove',
            'delete'
          ])
            _DownloadAction(downloads, sources, operation, deleteAudit),
        ];
  @override
  final List<Action> actions;
}

final class _DownloadJson implements JsonEncodable {
  const _DownloadJson(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _DownloadAction extends Action<_DownloadJson, _DownloadJson> {
  _DownloadAction(
      this.downloads, this.sources, this.operation, InvocationObserver? audit)
      : deletion = Harness([_DeleteCapability(downloads)],
            observers: [if (audit != null) audit]);
  final DownloadService downloads;
  final DownloadSources sources;
  final String operation;
  final Harness deletion;

  @override
  ActionSpec get spec => ActionSpec(
        id: 'download.$operation',
        title: '$operation download',
        description: switch (operation) {
          'add' =>
            'Accept source or sources: magnet URIs, HTTP(S) torrent URLs or local .torrent paths. Optional downloadDirectory and createFolderForTask override defaults for these new tasks without changing settings. Optional fileBindings (single source only) declares file index -> episode identity: entries are {fileIndex, workRef, releaseRef?, episodeRefs, reason?} with the catalogue-mode refs of media.identity.bind_batch. Indices must be unique and exist (checked at add for torrent files; a magnet has no manifest yet, so its out-of-range indices only appear in the receipt as unboundDeclarations), and lie within fileIndices when given; invalid input rejects the whole add. When a declared file passes verification and is registered, NipaPlay binds it with bind_batch (requestId derived from job and file index, so replays do not duplicate) and records the outcome on that file as binding: bound (workId, releaseId, episodeIds), supersededClassic when the declaration took the place of the Classic automatic match {source, workIds, episodeIds, emptiedWorkIds: works that held only automatic matches and left the library}), already_identified (the file already had episodes from a user or agent binding, left untouched), not_applied or failed (error); binding failure never fails the download. An existing task for the same hash keeps its original declarations; change them with download.declare_files. Returns queued jobs after metadata validation, deduplicated by backend and infoHash; an existing task keeps its original directory. Batch results preserve input order and individual failures.',
          'declare_files' =>
            'Declare or replace, on an existing download jobId, which episodes its files are: fileBindings has the entries and validation of download.add (unique indices; checked against the manifest when it is known, and each index must be among the currently selected files). Declarations merge by fileIndex: the listed indices replace their earlier declaration, the others stay. A file that is not yet completed is bound by the download itself when it completes, as with add; this works in every non-final state and changes neither the torrent nor the job state, so a paused, queued or waiting-retry download keeps its state and binds after it resumes. A file already completed, verified and registered is bound immediately with the logic of bind_batch (requestId derived from job, file index and the declaration content: the same declaration replays the saved result, a changed one binds anew), its binding replaced on the completedFiles row, and the outcome is returned per fileIndex in bindings: bound (workId, releaseId, episodeIds; plus supersededClassic {source, workIds, episodeIds, emptiedWorkIds} when the declaration took the place of the Classic automatic match of the file: the file then sits only under the declared episodes and works that held only automatic matches leave the library), already_identified (the file already has episodes from a user or agent binding; left untouched, existingEpisodeIds), not_applied (reason), failed (error; calling again retries it), or declared (saved, waiting for the file to complete). A file without a prior declaration is bound the same way. No new download.file_completed event is published for an already completed file. A finished download (succeeded, failed, cancelled) keeps its immutable receipt: completed files are still bound and reported, declarationsSaved is false, nothing is written. A download being cancelled returns conflict. Returns job, declarationsSaved and bindings.',
          'set_paused' =>
            'Set paused for jobId or jobIds, including downloading and seeding. Returns persisted jobs and individual batch failures.',
          'pause' =>
            'Compatibility alias for download.set_paused with paused=true.',
          'resume' =>
            'Compatibility alias for download.set_paused with paused=false.',
          'read' =>
            'Read checked bytes, completeness and playback facts per file, live peer counts, progress observation times and available disk bytes for jobId or jobIds. A file declared with fileBindings or declare_files has declared=true; once completed and registered it carries its library entry (media) and binding outcome as in download.file_completed. Unknown seed/piece availability is null. Completed seeding tasks remain readable. File events use objectId JOB_ID:FILE_INDEX.',
          'select_files' =>
            'Replace the included file indices for jobId or jobIds without deleting data or changing paths. Empty selects none. The builtin engine supports inclusion changes, not file priority. Readback verifies the selection. Expanding a finished selection returns a new observation job; the previous receipt is preserved.',
          'import' =>
            'Scan completed local video files for jobId or jobIds with the Classic scanner, even when automatic scanning is disabled. Verifies file sizes first; returns current imported/identification status. Does not rewrite historical download receipts.',
          'remove' =>
            'Remove session entries for jobId or jobIds, keeping downloaded files. Returns per-item persisted jobs and failures.',
          _ =>
            'Delete session entries and data for jobId or jobIds. Each item checks output containment and records its own destructive audit, including failures. With fileIndices (single jobId only), delete just those files of the download: they are unselected, then their data is removed, while the session, the other files and their downloading or seeding stay. The files must be local manifest files inside the output directory; directories and other files are never touched. The preview and the user prompt list only those files. Returns job, task (readback: the files are no longer included, data gone) and deletedFiles.',
        },
        effect: operation == 'delete'
            ? Effect.destructive
            : operation == 'read'
                ? Effect.read
                : Effect.write,
        input: operation == 'declare_files'
            ? const ObjectSchema({
                'jobId': _idSchema,
                'fileBindings': _fileBindingsSchema,
              }, required: [
                'jobId',
                'fileBindings'
              ])
            : operation == 'add'
            ? const ObjectSchema({
                'source': _idSchema,
                'sources': _idsSchema,
                'backend': _backendSchema,
                'downloadDirectory': _idSchema,
                'createFolderForTask': BooleanSchema(),
                'fileIndices': ArraySchema(IntegerSchema(minimum: 0)),
                'fileBindings': _fileBindingsSchema,
              }, oneOfRequired: [
                ['source'],
                ['sources']
              ])
            : ObjectSchema({
                'jobId': _idSchema,
                'jobIds': _idsSchema,
                if (operation == 'set_paused') 'paused': const BooleanSchema(),
                if (operation == 'select_files')
                  'fileIndices': const ArraySchema(IntegerSchema(minimum: 0)),
                if (operation == 'delete')
                  'fileIndices': const ArraySchema(IntegerSchema(minimum: 0),
                      minItems: 1),
              }, required: [
                if (operation == 'set_paused') 'paused',
                if (operation == 'select_files') 'fileIndices'
              ], oneOfRequired: const [
                ['jobId'],
                ['jobIds']
              ]),
        output: ObjectSchema({
          'job': _downloadJobSchema,
          'task': _downloadTaskSchema,
          'declarationsSaved': const BooleanSchema(),
          'deletedFiles': const ArraySchema(ObjectSchema({
            'index': IntegerSchema(minimum: 0),
            'path': _idSchema,
          }, required: [
            'index',
            'path'
          ])),
          'bindings': const ArraySchema(ObjectSchema({
            'fileIndex': IntegerSchema(minimum: 0),
            'status': StringSchema(values: [
              'bound',
              'already_identified',
              'not_applied',
              'failed',
              'declared'
            ]),
          }, required: [
            'fileIndex',
            'status'
          ], additionalProperties: true)),
          'results': ArraySchema(ObjectSchema({
            'index': const IntegerSchema(minimum: 0),
            'source': _idSchema,
            'jobId': _idSchema,
            'status': const StringSchema(values: ['completed', 'failed']),
            'job': _downloadJobSchema,
            'task': _downloadTaskSchema,
            'error': const ObjectSchema({}, additionalProperties: true),
          }, required: const [
            'index',
            'status'
          ], oneOfRequired: const [
            ['job'],
            ['error']
          ])),
        }, oneOfRequired: const [
          ['job'],
          ['results']
        ]),
      );

  @override
  _DownloadJson decodeInput(JsonMap json) => _DownloadJson(json);

  Future<JsonMap> _operate(
      String target, JsonMap json, Invocation invocation) async {
    if (operation == 'delete') {
      final outcome = await deletion.invokeJson(
          'download.delete',
          {
            'jobId': target,
            if (json['fileIndices'] != null) 'fileIndices': json['fileIndices']
          },
          invocation);
      switch (outcome) {
        case Completed(:final value):
          return value.toJson();
        case Failed(:final failure):
          throw failure;
        case NeedsDecision():
          throw StateError('Delete does not produce decisions.');
      }
    }
    final Job job;
    if (operation == 'add') {
      final ref = json['backend'] == null
          ? const DownloadBackendRef.builtin()
          : DownloadBackendRef.fromJson(json['backend'] as JsonMap);
      downloads.backends.resolve(ref);
      if (!await downloads.executor.isEnabled()) {
        throw const Failure(FailureCode.unavailable, 'Downloader is disabled.');
      }
      final directory = json['downloadDirectory'] as String?;
      if (directory != null) validateDownloadDirectory(directory);
      final prepared = await sources.prepare(target);
      final indices = (json['fileIndices'] as List?)?.cast<int>();
      if (indices != null && indices.toSet().length != indices.length) {
        throw const Failure(
            FailureCode.invalidInput, 'File indices must be unique.');
      }
      List<JsonMap>? bindings;
      if (json['fileBindings'] != null) {
        final isMagnet = Uri.tryParse(target)?.scheme == 'magnet';
        bindings = parseFileBindings(json['fileBindings'],
            fileCount: isMagnet
                ? null
                : ((await sources.previewTorrent(prepared))['files'] as List)
                    .length,
            fileIndices: indices);
      }
      job = await downloads.add(
          DownloadRequest(
            source: prepared.source,
            infoHash: prepared.infoHash,
            title: prepared.title,
            downloadDirectory: directory,
            createFolderForTask: json['createFolderForTask'] as bool?,
            fileIndices: (json['fileIndices'] as List?)?.cast<int>(),
            fileBindings: bindings,
            bindingOrigin: bindings == null ? null : invocation.origin,
          ),
          backend: ref,
          invocation: invocation);
    } else if (operation == 'declare_files') {
      return downloads.declareFiles(target, json['fileBindings'],
          origin: invocation.origin);
    } else if (operation == 'read') {
      final read = await downloads.read(target);
      await downloads.onRead?.call(target, invocation);
      return read;
    } else if (operation == 'import') {
      return downloads.importCompleted(target);
    } else if (operation == 'select_files') {
      return downloads.selectFiles(
          target, (json['fileIndices'] as List).cast<int>());
    } else {
      job = switch (operation) {
        'pause' => await downloads.pause(target),
        'resume' => await downloads.resume(target),
        'set_paused' => json['paused'] as bool
            ? await downloads.pause(target)
            : await downloads.resume(target),
        _ => await downloads.remove(target),
      };
    }
    return {'job': job.toJson()};
  }

  @override
  Future<Outcome<_DownloadJson>> run(
      _DownloadJson input, Invocation invocation) async {
    final json = input.json;
    if (operation == 'add' &&
        json.containsKey('sources') &&
        json['fileBindings'] != null) {
      throw const Failure(FailureCode.invalidInput,
          'fileBindings are per torrent; use source, not sources.');
    }
    if (operation == 'delete' &&
        json['fileIndices'] != null &&
        json.containsKey('jobIds')) {
      throw const Failure(FailureCode.invalidInput,
          'fileIndices are per download; use jobId, not jobIds.');
    }
    final field = operation == 'add' ? 'source' : 'jobId';
    final batchField = operation == 'add' ? 'sources' : 'jobIds';
    if (!json.containsKey(batchField)) {
      return Completed(_DownloadJson(
          await _operate(json[field] as String, json, invocation)));
    }
    final targets = (json[batchField] as List).cast<String>();
    final results = <JsonMap>[];
    for (var i = 0; i < targets.length; i++) {
      final identity = {'index': i, field: targets[i]};
      try {
        results.add({
          ...identity,
          'status': 'completed',
          ...await _operate(targets[i], json,
              Invocation(origin: invocation.origin, id: '${invocation.id}/$i'))
        });
      } on Failure catch (failure) {
        results
            .add({...identity, 'status': 'failed', 'error': failure.toJson()});
      } catch (error) {
        results.add({
          ...identity,
          'status': 'failed',
          'error':
              Failure(FailureCode.internal, 'Download operation failed: $error')
                  .toJson()
        });
      }
    }
    return Completed(_DownloadJson({'results': results}));
  }
}

final class _DeleteCapability implements Capability {
  _DeleteCapability(DownloadService downloads)
      : actions = [_DeleteAction(downloads)];
  @override
  final List<Action> actions;
}

final class _DeleteAction extends Action<_DownloadJson, _DownloadJson> {
  _DeleteAction(this.downloads);
  final DownloadService downloads;
  @override
  ActionSpec get spec => ActionSpec(
        id: 'download.delete',
        title: 'Delete download',
        description:
            'Delete one session and its contained data, or only the files at fileIndices.',
        effect: Effect.destructive,
        input: const ObjectSchema({
          'jobId': _idSchema,
          'fileIndices': ArraySchema(IntegerSchema(minimum: 0), minItems: 1),
        }, required: [
          'jobId'
        ]),
        output: ObjectSchema({
          'job': _downloadJobSchema,
          'task': _downloadTaskSchema,
          'deletedFiles': const ArraySchema(ObjectSchema({
            'index': IntegerSchema(minimum: 0),
            'path': _idSchema,
          }, required: [
            'index',
            'path'
          ])),
        }, required: const [
          'job'
        ]),
      );
  @override
  _DownloadJson decodeInput(JsonMap json) => _DownloadJson(json);
  @override
  Future<Outcome<_DownloadJson>> run(
          _DownloadJson input, Invocation invocation) async =>
      Completed(_DownloadJson(input.json['fileIndices'] != null
          ? await downloads.deleteFiles(input.json['jobId'] as String,
              (input.json['fileIndices'] as List).cast<int>())
          : {
              'job': (await downloads.remove(input.json['jobId'] as String,
                      deleteData: true))
                  .toJson()
            }));
}
