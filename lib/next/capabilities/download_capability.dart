import 'package:nipa_harness/nipa_harness.dart';

import '../downloads/download_backend.dart';
import '../downloads/download_service.dart';
import '../downloads/download_source.dart';

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

final class DownloadCapability implements Capability {
  DownloadCapability(
      {required DownloadService downloads,
      required DownloadSources sources,
      InvocationObserver? deleteAudit})
      : actions = [
          for (final operation in [
            'add',
            'set_paused',
            'pause',
            'resume',
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
            'Accept source or sources: magnet URIs, HTTP(S) torrent URLs or local .torrent paths. Returns queued jobs after metadata validation, deduplicated by backend and infoHash. Batch results preserve input order and individual failures.',
          'set_paused' =>
            'Set paused for jobId or jobIds, including downloading and seeding. Returns persisted jobs and individual batch failures.',
          'pause' =>
            'Compatibility alias for download.set_paused with paused=true.',
          'resume' =>
            'Compatibility alias for download.set_paused with paused=false.',
          'remove' =>
            'Remove session entries for jobId or jobIds, keeping downloaded files. Returns per-item persisted jobs and failures.',
          _ =>
            'Delete session entries and data for jobId or jobIds. Each item checks output containment and records its own destructive audit, including failures.',
        },
        effect: operation == 'delete' ? Effect.destructive : Effect.write,
        input: operation == 'add'
            ? const ObjectSchema({
                'source': _idSchema,
                'sources': _idsSchema,
                'backend': _backendSchema,
              }, oneOfRequired: [
                ['source'],
                ['sources']
              ])
            : ObjectSchema({
                'jobId': _idSchema,
                'jobIds': _idsSchema,
                if (operation == 'set_paused') 'paused': const BooleanSchema(),
              }, required: [
                if (operation == 'set_paused') 'paused'
              ], oneOfRequired: const [
                ['jobId'],
                ['jobIds']
              ]),
        output: ObjectSchema({
          'job': _downloadJobSchema,
          'results': ArraySchema(ObjectSchema({
            'index': const IntegerSchema(minimum: 0),
            'source': _idSchema,
            'jobId': _idSchema,
            'status': const StringSchema(values: ['completed', 'failed']),
            'job': _downloadJobSchema,
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
          'download.delete', {'jobId': target}, invocation);
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
      job = await downloads.add(await sources.prepare(target), backend: ref);
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
        description: 'Delete one session and its contained data.',
        effect: Effect.destructive,
        input: const ObjectSchema({'jobId': _idSchema}, required: ['jobId']),
        output:
            ObjectSchema({'job': _downloadJobSchema}, required: const ['job']),
      );
  @override
  _DownloadJson decodeInput(JsonMap json) => _DownloadJson(json);
  @override
  Future<Outcome<_DownloadJson>> run(
          _DownloadJson input, Invocation invocation) async =>
      Completed(_DownloadJson({
        'job': (await downloads.remove(input.json['jobId'] as String,
                deleteData: true))
            .toJson()
      }));
}
