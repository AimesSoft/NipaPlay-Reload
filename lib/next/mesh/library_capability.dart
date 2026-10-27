import 'package:nipa_harness/nipa_harness.dart';
import '../state/query.dart';
import 'library.dart';
import 'library_codec.dart';
import 'runtime.dart';

final class MeshLibraryCapability implements Capability {
  MeshLibraryCapability(MeshLibrary library)
      : actions = [
          _MergedSearchAction(library),
          _ManagementTargets(library),
          _LibraryAction(library, 'readable'),
          _LibraryAction(library, 'refresh'),
          _LibraryAction(library, 'progress')
        ];
  @override
  final List<Action> actions;
}

final class _ManagementTargets extends Action<MeshJson, MeshJson> {
  const _ManagementTargets(this.library);
  final MeshLibrary library;
  @override
  ActionSpec get spec => const ActionSpec(id: 'media.management.targets',
    title: '读取作品管理的来源设备和实体',
    description: 'Resolve merged workIds to each owning body\'s original work/episode/file IDs. '
      'Offline targets remain present with source_device_offline. Local writes use these local IDs; '
      'remote writes use mesh.invoke(deviceId, action, input) with the original IDs, so all '
      'domain checks and decisions execute on the owner. Never send a receiving-process path to another body. '
      'Unsupported host actions return unavailable from the target catalogue, not silent success. '
      'Use media.files.list on the target to read all file locations; file deletion retains NeedsDecision.',
    effect: Effect.read,
    input: ObjectSchema({'workIds': ArraySchema(StringSchema(minLength: 1))}, required: ['workIds']),
    output: ObjectSchema({}, additionalProperties: true));
  @override
  MeshJson decodeInput(JsonMap input) => MeshJson(input);
  @override
  Future<Outcome<MeshJson>> run(MeshJson input, Invocation invocation) async =>
    Completed(MeshJson(await library.managementTargets((input.json['workIds'] as List).cast<String>())));
}

final class _MergedSearchAction extends Action<MeshJson, MeshJson> {
  const _MergedSearchAction(this.library);
  final MeshLibrary library;
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'media.library.search_merged',
      title: '搜索合并媒体库',
      description: 'Read the indexed local + authenticated Mesh catalogue. Matches display/original/alternate titles, years and episode titles; whitespace terms are AND, case-insensitive literal substrings. Returns works and episode hits with their work, canonical Next workId/episodeId, year, local artwork paths, devices and playable facts. limit and episodeLimit bound each group (default 12). Exact titles precede prefixes and substrings, then recent additions. Cold first read prepares the index; background catalogue refresh updates it every 5 seconds, media.library.refresh updates immediately. Offline peers retain facts with playable=false. Does not call Classic recorded-library search or browse/register source files.',
      effect: Effect.read,
      input: ObjectSchema({
        'query': StringSchema(minLength: 1),
        'limit': IntegerSchema(minimum: 1, maximum: 100),
        'episodeLimit': IntegerSchema(minimum: 1, maximum: 100),
      }, required: ['query']),
      output: ObjectSchema({
        'works': ArraySchema(ObjectSchema({}, additionalProperties: true)),
        'episodes': ArraySchema(ObjectSchema({}, additionalProperties: true)),
        'workTotal': IntegerSchema(minimum: 0),
        'episodeTotal': IntegerSchema(minimum: 0),
      }, required: ['works', 'episodes', 'workTotal', 'episodeTotal']));
  @override
  MeshJson decodeInput(JsonMap input) => MeshJson(input);
  @override
  Future<Outcome<MeshJson>> run(MeshJson input, Invocation invocation) async =>
      Completed(MeshJson(await library.search(input.json['query'] as String,
          limit: input.json['limit'] as int? ?? 12,
          episodeLimit: input.json['episodeLimit'] as int?)));
}

final class _LibraryAction extends Action<MeshJson, MeshJson> {
  const _LibraryAction(this.library, this.operation);
  final MeshLibrary library;
  final String operation;
  @override
  ActionSpec get spec => ActionSpec(
      id: 'media.library.$operation',
      title: switch (operation) {
        'readable' => '取得剧集可读地址',
        'refresh' => '刷新组网媒体库',
        _ => '记录跨设备观看进度'
      },
      description: switch (operation) {
        'readable' =>
          'Resolve merged or local episode IDs in one batch. Native local files return path; remote files return a process-lifetime loopback HTTP url supporting HEAD/Range for players, ffprobe and ffmpeg. File bytes use authenticated direct Mesh TLS; no file copy. Loopback HTTP must bypass HTTP_PROXY. Offline sources return per-entry errors.',
        'refresh' =>
          'Read authenticated peer catalogues now and update the persistent merged projection. Offline catalogues remain visible with online=false and playable=false. Joining Mesh grants peer access.',
        _ =>
          'Record observed progress (0..1, including resets) for merged/local episode IDs in a batch. Optional positionMs/durationMs are observations. Latest timestamp and device-ID tie break wins across Mesh peers; progress is retained offline and synchronized when reachable.'
      },
      effect: operation == 'progress' ? Effect.write : Effect.read,
      input: operation == 'refresh'
          ? const ObjectSchema({})
          : operation == 'readable'
              ? const ObjectSchema(
                  {'episodeIds': ArraySchema(StringSchema(minLength: 1))},
                  required: ['episodeIds'])
              : const ObjectSchema({
                  'entries': ArraySchema(ObjectSchema({
                    'episodeId': StringSchema(minLength: 1),
                    'progress': NumberSchema(minimum: 0, maximum: 1),
                    'positionMs': IntegerSchema(minimum: 0),
                    'durationMs': IntegerSchema(minimum: 0)
                  }, required: [
                    'episodeId',
                    'progress'
                  ]))
                }, required: [
                  'entries'
                ]),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  MeshJson decodeInput(JsonMap input) => MeshJson(input);
  @override
  Future<Outcome<MeshJson>> run(MeshJson input, Invocation invocation) async {
    if (operation == 'refresh') {
      await library.refresh();
      return Completed(MeshJson({'works': (await library.library()).length,
        ...library.refreshStatus}));
    }
    if (operation == 'progress') {
      final entries = (input.json['entries'] as List).cast<JsonMap>();
      await library.recordProgressBatch(entries);
      return Completed(MeshJson({'updated': entries.length}));
    }
    final results = <JsonMap>[];
    for (final id in (input.json['episodeIds'] as List).cast<String>()) {
      try {
        results.add(await library.readable(id));
      } on Failure catch (e) {
        results.add({'episodeId': id, 'error': e.toJson()});
      }
    }
    return Completed(MeshJson({'entries': results}));
  }
}

void registerMergedLibrary(StateCapability state, MeshLibrary library) {
  state.views['mesh.file_proxy'] = StateView(
      name: 'mesh.file_proxy',
      description:
          'Local loopback file proxy listener: requested and actual port, fixed/random/fallback state. Host-only mesh.json fileProxyPort; no file access tokens are exposed.',
      fields: const ObjectSchema({
        'id': StringSchema(),
        'host': StringSchema(),
        'state': StringSchema(),
        'requestedPort': IntegerSchema(),
        'port': IntegerSchema(nullable: true),
        'fallback': BooleanSchema(),
        'reason': StringSchema(nullable: true),
      }),
      read: (offset, limit) async =>
          [library.fileProxyStatus].skip(offset).take(limit).toList());
  state.views['library.merged'] = StateView(
      name: 'library.merged',
      description:
          'The viewer library: one entry per accepted work identity or identical sampled file; local and Mesh episodes, local artwork cache, last observations offline. IDs accepted by ui.open and media.library.readable/progress.',
      fields: const ObjectSchema({
        'id': StringSchema(),
        'workId': StringSchema(),
        'title': StringSchema(),
        'devices': ArraySchema(ObjectSchema({}, additionalProperties: true)),
        'episodes': ArraySchema(ObjectSchema({}, additionalProperties: true)),
        'next': ObjectSchema({}, additionalProperties: true, nullable: true),
        'artwork': ObjectSchema({}, additionalProperties: true)
      }, additionalProperties: true),
      read: (offset, limit) async => [
            for (final w in (await library.library()).skip(offset).take(limit))
              {
                'id': w.workId,
                ...workJson(w),
                'episodes': [
                  for (final e in await library.episodes(w.workId))
                    episodeJson(e)
                ]
              }
          ]);
}
