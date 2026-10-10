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

final class DownloadCapability implements Capability {
  DownloadCapability(
      {required DownloadService downloads, required DownloadSources sources})
      : actions = [
          for (final operation in [
            'add',
            'pause',
            'resume',
            'remove',
            'delete'
          ])
            _DownloadAction(downloads, sources, operation)
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
  _DownloadAction(this.downloads, this.sources, this.operation);
  final DownloadService downloads;
  final DownloadSources sources;
  final String operation;
  @override
  ActionSpec get spec => ActionSpec(
        id: 'download.$operation',
        title: '$operation download',
        description: switch (operation) {
          'add' =>
            'Accept a magnet URI, HTTP(S) torrent URL, or local .torrent path. '
                'Returns a queued job immediately after metadata validation; completion '
                'requires verification and a receipt. Reuses downloads by backend and infoHash.',
          'pause' => 'Pause downloading or seeding. Return the persisted job.',
          'resume' =>
            'Resume downloading or seeding and reconcile the same job.',
          'remove' =>
            'Remove the download session entry, keeping downloaded files.',
          _ =>
            'Remove the session entry and delete its data after checking output containment.',
        },
        effect: operation == 'delete' ? Effect.destructive : Effect.write,
        input: operation == 'add'
            ? const ObjectSchema({
                'source': StringSchema(minLength: 1),
                'backend': ObjectSchema({
                  'kind': StringSchema(minLength: 1),
                  'id': StringSchema(minLength: 1)
                }, required: [
                  'kind'
                ]),
              }, required: [
                'source'
              ])
            : const ObjectSchema({'jobId': StringSchema(minLength: 1)},
                required: ['jobId']),
        output:
            ObjectSchema({'job': _downloadJobSchema}, required: const ['job']),
      );
  @override
  _DownloadJson decodeInput(JsonMap json) => _DownloadJson(json);
  @override
  Future<Outcome<_DownloadJson>> run(
      _DownloadJson input, Invocation invocation) async {
    final json = input.json;
    final Job job;
    if (operation == 'add') {
      final ref = json['backend'] == null
          ? const DownloadBackendRef.builtin()
          : DownloadBackendRef.fromJson(json['backend'] as JsonMap);
      downloads.backends.resolve(ref);
      if (!await downloads.executor.isEnabled()) {
        throw const Failure(FailureCode.unavailable, 'Downloader is disabled.');
      }
      job = await downloads.add(await sources.prepare(json['source'] as String),
          backend: ref);
    } else {
      final id = json['jobId'] as String;
      job = switch (operation) {
        'pause' => await downloads.pause(id),
        'resume' => await downloads.resume(id),
        'remove' => await downloads.remove(id),
        _ => await downloads.remove(id, deleteData: true),
      };
    }
    return Completed(_DownloadJson({'job': job.toJson()}));
  }
}
