import 'package:nipa_harness/nipa_harness.dart';

import '../downloads/download_backend.dart';
import '../downloads/download_service.dart';
import '../downloads/download_source.dart';
import '../downloads/download_paths.dart';
import '../downloads/http_download_backend.dart';
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
  'checksum': ObjectSchema({}, additionalProperties: true),
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
          _WaitFilesAction(downloads),
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
            'Accept source or sources: magnet URIs, HTTP(S) torrent URLs or local .torrent paths. Optional downloadDirectory and createFolderForTask override defaults for these new tasks without changing settings. Returns queued jobs after metadata validation, deduplicated by backend and infoHash; an existing task keeps its original directory. Batch results preserve input order and individual failures. With backend {kind: "http"} the source is instead an http:// or https:// address of one file, downloaded as it is (no torrent, no unpacking, no guessing what it is): the file lands in downloadDirectory or the download directory setting (inside a folder named after the file only when createFolderForTask is true) under the name the server gives (Content-Disposition filename, else the last path segment of the final URL), never over an existing file (a taken name gets " (1)", " (2)" ...). The data is written to NAME.nipaplay-part and renamed when complete, so a partial file is never in the library. Pause, resume, cancel and restart continue with a Range request when the server honours it, otherwise from the start. Optional connections (integer 1-8, default 1) splits the file into that many byte ranges fetched in parallel over separate connections into the same NAME.nipaplay-part; only when the server sends Accept-Ranges: bytes and a Content-Length, otherwise one connection is used. health.http.connections always says {requested, used, reason} (reason null when used equals requested; no_range, unknown_length, too_small or range_ignored otherwise) and, when more than one connection is used, the start, end and completedBytes of each segment. completedBytes is the sum of the segments, a stall means no segment received a byte, and a failing segment is retried on its own; resume after pause, cancel or restart continues every segment from the bytes it already holds. Optional checksum {algorithm: md5|sha1|sha256, value} is compared after the last byte; a mismatch fails the task and the receipt and failure carry expected and actual values (the data stays as NAME.nipaplay-part); without checksum the receipt still records the computed sha256 with matched null. Connection failures and 5xx/408/429 answers are retried and count as no progress (download.stalled applies); other 4xx answers fail the task. The task identity infoHash is "http-" plus the SHA-1 of the normalized URL (fragment removed). Video files are registered like any download; other files (a zip) are reported as not_video and left as they are. Other schemes are refused.',
          'set_paused' =>
            'Set paused for jobId or jobIds, including downloading and seeding. Returns persisted jobs and individual batch failures.',
          'pause' =>
            'Compatibility alias for download.set_paused with paused=true.',
          'resume' =>
            'Compatibility alias for download.set_paused with paused=false.',
          'read' =>
            'Read checked bytes, completeness and playback facts per file, live peer counts, progress observation times and available disk bytes for jobId or jobIds. A completed, registered video file carries its current library entry as media: fileId, workIds and episodes, each episode with the identity sources of its link to the file (see download.file_completed). Unknown seed/piece availability is null. Completed seeding tasks remain readable. File events use objectId JOB_ID:FILE_INDEX.',
          'select_files' =>
            'Replace the included file indices for jobId or jobIds without deleting data or changing paths. Empty selects none. The builtin engine supports inclusion changes, not file priority. Readback verifies the selection. Expanding a finished selection returns a new observation job; the previous receipt is preserved.',
          'import' =>
            'Scan completed local video files for jobId or jobIds with the Classic scanner, even when automatic scanning is disabled. Verifies file sizes first; returns current imported/identification status. Does not rewrite historical download receipts.',
          'remove' =>
            'Remove session entries for jobId or jobIds, keeping downloaded files. A job that had already ended keeps its state, and its receipt then records sessionPresent false, removedAt, dataDeleted false and each file re-read (actualSize, retained, imported). Returns per-item persisted jobs and failures.',
          _ =>
            'Delete session entries and data for jobId or jobIds. Each item checks output containment and records its own destructive audit, including failures. With fileIndices (single jobId only), delete just those files of the download: they are unselected, then their data is removed, while the session, the other files and their downloading or seeding stay. The files must be local manifest files inside the output directory; directories and other files are never touched. The preview and the user prompt list only those files. Returns job, task (readback: the files are no longer included, data gone) and deletedFiles. Deleting a whole download that had already ended keeps its state, and its receipt then records sessionPresent false, removedAt, dataDeleted true and each file re-read (actualSize, retained, imported).',
        },
        effect: operation == 'delete'
            ? Effect.destructive
            : operation == 'read'
                ? Effect.read
                : Effect.write,
        input: operation == 'add'
            ? const ObjectSchema({
                'source': _idSchema,
                'sources': _idsSchema,
                'backend': _backendSchema,
                'downloadDirectory': _idSchema,
                'createFolderForTask': BooleanSchema(),
                'fileIndices': ArraySchema(IntegerSchema(minimum: 0)),
                'connections': IntegerSchema(minimum: 1, maximum: 8),
                'checksum': ObjectSchema({
                  'algorithm':
                      StringSchema(values: HttpDownloadBackend.checksumAlgorithms),
                  'value': StringSchema(minLength: 32),
                }, required: [
                  'algorithm',
                  'value'
                ]),
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
          'deletedFiles': const ArraySchema(ObjectSchema({
            'index': IntegerSchema(minimum: 0),
            'path': _idSchema,
          }, required: [
            'index',
            'path'
          ])),
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
      if (ref.kind != HttpDownloadBackend.kind && json['checksum'] != null) {
        throw const Failure(FailureCode.invalidInput,
            'checksum is only supported by the http backend.');
      }
      if (ref.kind != HttpDownloadBackend.kind && json['connections'] != null) {
        throw const Failure(FailureCode.invalidInput,
            'connections is only supported by the http backend.');
      }
      downloads.backends.resolve(ref);
      if (!await downloads.executor.isEnabled()) {
        throw const Failure(FailureCode.unavailable, 'Downloader is disabled.');
      }
      final directory = json['downloadDirectory'] as String?;
      if (directory != null) validateDownloadDirectory(directory);
      final isHttp = ref.kind == HttpDownloadBackend.kind;
      if (isHttp && json['fileIndices'] != null) {
        throw const Failure(FailureCode.invalidInput,
            'The http backend downloads one file; fileIndices does not apply.');
      }
      final prepared = isHttp
          ? HttpDownloadBackend.prepare(target,
              checksum: json['checksum'] as JsonMap?)
          : await sources.prepare(target);
      final indices = (json['fileIndices'] as List?)?.cast<int>();
      if (indices != null && indices.toSet().length != indices.length) {
        throw const Failure(
            FailureCode.invalidInput, 'File indices must be unique.');
      }
      job = await downloads.add(
          DownloadRequest(
            source: prepared.source,
            infoHash: prepared.infoHash,
            title: prepared.title,
            downloadDirectory: directory,
            createFolderForTask: json['createFolderForTask'] as bool?,
            fileIndices: (json['fileIndices'] as List?)?.cast<int>(),
            checksum: prepared.checksum,
            connections: isHttp ? json['connections'] as int? : null,
          ),
          backend: ref,
          invocation: invocation);
    } else if (operation == 'read') {
      return downloads.read(target);
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

final class _WaitFilesAction extends Action<_DownloadJson, _DownloadJson> {
  _WaitFilesAction(this.downloads);
  final DownloadService downloads;
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'download.wait_files',
        title: 'Wait for download files',
        description:
            'Wait until a video file of the download jobId is complete, verified and registered in the library, and return it. known lists the file indices you have already handled; those are never returned again. Each file has the same facts as an entry of download.read task.files, including media. Returns at once if such files already exist. Otherwise it returns when one completes, when the download has ended (state succeeded, failed or cancelled: ended is true and files holds every remaining one, possibly none), or after waitSeconds (default 300, at most 300) with no files and timedOut true. Reports facts only; it binds nothing.',
        effect: Effect.read,
        input: ObjectSchema({
          'jobId': _idSchema,
          'known': ArraySchema(IntegerSchema(minimum: 0)),
          'waitSeconds': IntegerSchema(minimum: 0, maximum: 300),
        }, required: [
          'jobId'
        ]),
        output: ObjectSchema({
          'jobId': _idSchema,
          'state': StringSchema(),
          'files': ArraySchema(ObjectSchema({}, additionalProperties: true)),
          'ended': BooleanSchema(),
          'timedOut': BooleanSchema(),
        }, required: [
          'jobId',
          'state',
          'files',
          'ended',
          'timedOut'
        ]),
      );
  @override
  _DownloadJson decodeInput(JsonMap json) => _DownloadJson(json);
  @override
  Future<Outcome<_DownloadJson>> run(
          _DownloadJson input, Invocation invocation) async =>
      Completed(_DownloadJson(await downloads.waitFiles(
          input.json['jobId'] as String,
          ((input.json['known'] as List?) ?? const []).cast<int>().toSet(),
          (input.json['waitSeconds'] as num?)?.toInt() ?? 300)));
}
