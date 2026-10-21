import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import '../../models/torrent_task.dart';
import '../downloads/download_backend.dart';
import '../downloads/download_paths.dart';
import '../downloads/download_source.dart';
import '../media/media_service.dart';
import 'native.dart';

final class HeadlessDownloadBackend
    implements DownloadBackend, SelectableDownloadBackend, BandwidthDownloadBackend {
  HeadlessDownloadBackend(
      {this.native,
      this.root,
      this.configuration = const {},
      this.readOnlyRoots = const []});
  final HeadlessNative? native;
  final Directory? root;
  final JsonMap configuration;
  final List<String> readOnlyRoots;
  static const reason = 'Headless native download library is not configured.';
  @override
  Future<JsonMap> bandwidth(JsonMap input) async => native == null
    ? {'supported': false, 'applied': false, 'reason': 'native_backend_not_configured'}
    : Map<String, Object?>.from(await native!.call('torrent_limits', {
      'download': input['downloadBytesPerSecond'] ?? -1, 'upload': input['uploadBytesPerSecond'] ?? -1}) as Map);
  Future<void>? _ready;
  @override
  DownloadBackendRef get reference => const DownloadBackendRef.builtin();
  @override
  String? get credentialRef => null;
  @override
  Future<void> initialize() => _ready ??= _initialize();
  Future<void> _initialize() async {
    if (native == null || root == null) {
      throw const Failure(FailureCode.unavailable, reason);
    }
    await native!.call('configure',
        {'root': root!.path, 'configuration': jsonEncode(configuration)});
    await native!.call('torrent_init', {
      'download_dir': p.join(root!.path, 'downloads'),
      'session_dir': p.join(root!.path, 'torrent-session')
    });
  }

  @override
  Future<List<DownloadSnapshot>> list() async {
    await initialize();
    final tasks = TorrentTask.listFromJson(await native!.call(
            'torrent_list', {'download_dir': p.join(root!.path, 'downloads')})
        as String);
    return [for (final task in tasks) await read('${task.id}')];
  }

  @override
  Future<DownloadSnapshot> read(String handle) async {
    await initialize();
    final facts = jsonDecode(await native!
        .call('torrent_facts', {'id': int.parse(handle)}) as String) as JsonMap;
    final task = TorrentTask.fromMap(
        {...facts['details'] as JsonMap, 'stats': facts['stats']});
    final progress =
        ((facts['stats'] as Map)['file_progress'] as List).cast<int>();
    return DownloadSnapshot(
        handle: handle,
        infoHash: task.infoHash.toLowerCase(),
        title: task.name,
        output: DownloadLocation(path: task.outputFolder, isLocal: true),
        libraryKey: task.autoScanKey,
        state: task.state,
        completed: task.progressBytes,
        total: task.totalBytes,
        finished: task.finished,
        paused: task.isPaused,
        downloadSpeedBytesPerSecond: task.downloadSpeedBytesPerSecond,
        uploadSpeedBytesPerSecond: task.uploadSpeedBytesPerSecond,
        error: task.hasError ? task.error : null,
        disk: facts['disk'] as JsonMap,
        health: {
          'sources': facts['sources'],
          'fileSelectionSupported': true,
          'filePrioritySupported': false
        },
        files: [
          for (final file in task.files)
            DownloadFile(
                location: DownloadLocation(
                    path: p
                        .normalize(p.join(task.outputFolder, file.displayName)),
                    isLocal: true),
                expectedSize: file.length,
                completedBytes:
                    file.index < progress.length ? progress[file.index] : null,
                isVideo: file.isVideo,
                included: file.included)
        ]);
  }

  @override
  Future<DownloadSnapshot> add(DownloadRequest request,
      {Future<void>? stopRequested}) async {
    final output = request.downloadDirectory ?? p.join(root!.path, 'downloads');
    final real = await prepareDirectory(output);
    await initialize();
    Object? response;
    if (request.source.startsWith('magnet:')) {
      final preview = await native!.call('torrent_begin_preview') as int;
      var cancelled = false;
      stopRequested?.then((_) async {
        cancelled = true;
        await native!.call('torrent_cancel_preview', {'request_id': preview});
      });
      try {
        await native!.call('torrent_preview_magnet', {
          'source': request.source,
          'download_dir': real,
          'request_id': preview
        });
        if (cancelled) throw const DownloadAddStopped();
        response = await native!.call('torrent_add_magnet', {
          'source': request.source,
          'download_dir': real,
          'create_folder': request.createFolderForTask ?? true,
          'only_files': request.fileIndices,
          'request_id': preview
        });
      } on Failure {
        if (cancelled) throw const DownloadAddStopped();
        rethrow;
      } finally {
        await native!.call('torrent_cancel_preview', {'request_id': preview});
      }
    } else {
      response = await native!.call('torrent_add_file', {
        'path': request.source,
        'download_dir': real,
        'create_folder': request.createFolderForTask ?? true,
        'only_files': request.fileIndices
      });
    }
    final result = jsonDecode(response as String) as Map;
    return read('${result['id']}');
  }

  Future<String> prepareDirectory(String output) async {
    validateDownloadDirectory(output);
    output = p.normalize(output);
    for (final mediaRoot in readOnlyRoots) {
      if (p.equals(mediaRoot, output) ||
          p.isWithin(mediaRoot, output) ||
          p.isWithin(output, mediaRoot)) {
        throw const Failure(FailureCode.invalidInput,
            'Download targets must be separate from read-only media roots.');
      }
    }
    var ancestor = output;
    while (await FileSystemEntity.type(ancestor, followLinks: false) ==
        FileSystemEntityType.notFound) {
      ancestor = p.dirname(ancestor);
    }
    final canonicalAncestor = await File(ancestor).resolveSymbolicLinks();
    final real = p.normalize(
        p.join(canonicalAncestor, p.relative(output, from: ancestor)));
    for (final mediaRoot in readOnlyRoots) {
      final media = await Directory(mediaRoot).resolveSymbolicLinks();
      if (p.equals(media, real) ||
          p.isWithin(media, real) ||
          p.isWithin(real, media)) {
        throw const Failure(FailureCode.invalidInput,
            'Download targets must be separate from read-only media roots.');
      }
    }
    await Directory(real).create(recursive: true);
    return Directory(real).resolveSymbolicLinks();
  }

  Future<JsonMap> preview(String source, String? directory) async {
    final real =
        await prepareDirectory(directory ?? p.join(root!.path, 'downloads'));
    await initialize();
    final request = await native!.call('torrent_begin_preview') as int;
    try {
      final result = jsonDecode(await native!.call('torrent_preview_magnet', {
        'source': source,
        'download_dir': real,
        'request_id': request
      }) as String) as JsonMap;
      return {
        'name': result['name'],
        'suggestedFolderName': result['suggested_folder_name'],
        'totalSize': result['total_size'],
        'files': result['files']
      };
    } finally {
      await native!.call('torrent_cancel_preview', {'request_id': request});
    }
  }

  @override
  Future<void> selectFiles(String handle, List<int> indices) async {
    await native!
        .call('torrent_select', {'id': int.parse(handle), 'indices': indices});
  }

  @override
  Future<void> pause(String handle) async {
    await native!.call('torrent_pause', {'id': int.parse(handle)});
  }

  @override
  Future<void> resume(String handle) async {
    await native!.call('torrent_resume', {'id': int.parse(handle)});
  }

  @override
  Future<void> remove(String handle) async {
    await native!.call('torrent_forget', {'id': int.parse(handle)});
  }

  @override
  Future<void> delete(String handle) async => throw const Failure(
      FailureCode.unavailable, 'Headless disk deletion is not exposed.');
  @override
  Future<int?> readSize(DownloadFile file) async =>
      await File(file.location.path).exists()
          ? File(file.location.path).length()
          : null;
}

final class HeadlessDownloadMetadata implements Capability {
  HeadlessDownloadMetadata(this.backend, this.sources);
  final HeadlessDownloadBackend backend;
  final DownloadSources sources;
  @override
  List<Action> get actions => [
        for (final verb in ['preview', 'directories'])
          _MetadataAction(this, verb)
      ];
}

final class _MetadataJson implements JsonEncodable {
  const _MetadataJson(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _MetadataAction extends Action<_MetadataJson, _MetadataJson> {
  const _MetadataAction(this.service, this.verb);
  final HeadlessDownloadMetadata service;
  final String verb;
  @override
  ActionSpec get spec => ActionSpec(
      id: 'download.$verb',
      title: 'Download $verb',
      description: verb == 'preview'
          ? 'Preview magnet metadata, local torrent path/file URI or HTTP(S) torrent address without adding a task. Prepared torrent bytes are cached; no media bytes are downloaded.'
          : 'Read this device\'s default download directory. The headless host does not keep recent directory choices.',
      effect: Effect.read,
      input: verb == 'preview'
          ? const ObjectSchema({
              'source': StringSchema(minLength: 1),
              'downloadDirectory': StringSchema(minLength: 1)
            }, required: [
              'source'
            ])
          : const ObjectSchema({}),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  _MetadataJson decodeInput(JsonMap json) => _MetadataJson(json);
  @override
  Future<Outcome<_MetadataJson>> run(
      _MetadataJson input, Invocation invocation) async {
    if (verb == 'directories') {
      return Completed(_MetadataJson({
        'defaultDirectory': p.join(service.backend.root!.path, 'downloads'),
        'recentDirectories': <String>[]
      }));
    }
    final source = input.json['source'] as String;
    final prepared = await service.sources.prepare(source);
    final directory = input.json['downloadDirectory'] as String?;
    if (directory != null) validateDownloadDirectory(directory);
    if (Uri.tryParse(source)?.scheme != 'magnet') {
      return Completed(_MetadataJson(await service.sources.previewTorrent(prepared)));
    }
    return Completed(_MetadataJson(await service.backend
        .preview(source, input.json['downloadDirectory'] as String?)));
  }
}

final class HeadlessDownloadLibrary implements DownloadLibrary {
  HeadlessDownloadLibrary(this.media);
  final MediaService media;
  @override
  Future<bool> get enabled async => true;
  @override
  bool get isBusy => false;
  @override
  Future<bool> wasImported(String key) async =>
      (await media.store.database.query('ui_cache',
              where: 'id=?', whereArgs: ['download-import:$key']))
          .isNotEmpty;
  @override
  Future<void> markImported(String key) =>
      media.store.database.insert('ui_cache', {
        'id': 'download-import:$key',
        'fingerprint': 'verified',
        'payload': 'true'
      }).then((_) {});
  @override
  Future<JsonMap?> lookup(String path) async {
    final id = await media.store.ensureFile(path, via: 'download_import');
    final episodes = await media.store.database.rawQuery(
        'SELECT e.id AS episodeId, e.parent_id AS workId, e.attributes FROM media_file_episodes fe JOIN media_entities e ON e.id=fe.episode_id WHERE fe.file_id=?',
        [id]);
    final sources = await media.store.linkSources(id);
    return {
      'path': path,
      'fileId': id,
      'workIds': episodes.map((e) => e['workId']).toSet().toList(),
      'episodeIds': [for (final e in episodes) e['episodeId']],
      'episodes': [
        for (final e in episodes)
          {...e, 'identitySources': sources[e['episodeId']] ?? <JsonMap>[]}
      ],
      'identificationPending': episodes.isEmpty
    };
  }

  @override
  Future<bool> importFiles(List<String> paths, String outputDirectory) async {
    for (final path in paths) {
      await media.index(path, via: 'download_import');
    }
    return true;
  }
}
