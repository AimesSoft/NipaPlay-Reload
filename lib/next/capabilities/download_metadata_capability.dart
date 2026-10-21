import 'package:nipa_harness/nipa_harness.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show AnyhowException;
import 'package:nipaplay/models/torrent_magnet_preview.dart';
import 'package:nipaplay/services/torrent_download_service.dart';

import '../downloads/download_paths.dart';
import '../downloads/download_source.dart';

/// Classic's magnet metadata resolution, replaceable in tests.
typedef MagnetPreview = Future<TorrentMagnetPreview> Function(String source,
    {String? downloadDirectory, required TorrentPreviewRequest request});

final class DownloadMetadataCapability implements Capability {
  DownloadMetadataCapability(
      DownloadSources sources, Future<bool> Function() isEnabled,
      {MagnetPreview? previewMagnet})
      : actions = [
          for (final verb in ['preview', 'directories', 'forget_directories'])
            _MetadataAction(verb, sources, isEnabled, previewMagnet),
        ];
  @override
  final List<Action> actions;
}

final class _Json implements JsonEncodable {
  const _Json(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _MetadataAction extends Action<_Json, _Json> {
  _MetadataAction(this.verb, this.sources, this.isEnabled, this.previewMagnet);
  final String verb;
  final DownloadSources sources;
  final Future<bool> Function() isEnabled;
  final MagnetPreview? previewMagnet;
  @override
  ActionSpec get spec => ActionSpec(
        id: 'download.$verb',
        title: 'Download $verb',
        description: switch (verb) {
          'preview' =>
            'Preview a magnet, local torrent path/file URI or HTTP(S) torrent address without adding a task. Torrent bytes reuse download.add preparation and cache; magnets use Classic native metadata resolution. Returns name, folder suggestion and indexed files. No media bytes are downloaded. A magnet\'s metadata comes from its peers; with none, the call waits until Classic gives up (about a minute). waitSeconds bounds that wait: when it passes, the preview stops and fails as unavailable, saying no metadata arrived.',
          'directories' =>
            'Read the Classic default download directory and recent directory choices.',
          _ =>
            'Remove directories from Classic recent choices. Does not change the default directory, move files or delete downloaded data.',
        },
        effect: verb == 'forget_directories' ? Effect.write : Effect.read,
        input: switch (verb) {
          'preview' => const ObjectSchema({
              'source': StringSchema(minLength: 1),
              'downloadDirectory': StringSchema(minLength: 1),
              'waitSeconds': IntegerSchema(minimum: 1, maximum: 300),
            }, required: [
              'source'
            ]),
          'forget_directories' => const ObjectSchema({
              'directories': ArraySchema(StringSchema(minLength: 1)),
            }, required: [
              'directories'
            ]),
          _ => const ObjectSchema({}),
        },
        output: verb == 'preview'
            ? const ObjectSchema({
                'name': StringSchema(),
                'suggestedFolderName': StringSchema(),
                'totalSize': IntegerSchema(minimum: 0),
                'files': ArraySchema(ObjectSchema({
                  'index': IntegerSchema(minimum: 0),
                  'path': StringSchema(),
                  'length': IntegerSchema(minimum: 0),
                }, required: [
                  'index',
                  'path',
                  'length'
                ])),
              }, required: [
                'name',
                'suggestedFolderName',
                'totalSize',
                'files'
              ])
            : const ObjectSchema({
                'defaultDirectory': StringSchema(),
                'recentDirectories': ArraySchema(StringSchema()),
              }, required: [
                'defaultDirectory',
                'recentDirectories'
              ]),
      );
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final service = TorrentDownloadService.instance;
    if (verb == 'preview') {
      if (!await isEnabled()) {
        throw const Failure(FailureCode.unavailable, 'Downloader is disabled.');
      }
      final source = input.json['source'] as String;
      final prepared = await sources.prepare(source);
      final directory = input.json['downloadDirectory'] as String?;
      if (directory != null) validateDownloadDirectory(directory);
      if (Uri.tryParse(source)?.scheme != 'magnet') {
        return Completed(_Json(await sources.previewTorrent(prepared)));
      }
      final request = TorrentPreviewRequest();
      final wait = (input.json['waitSeconds'] as num?)?.toInt();
      try {
        final resolving = (previewMagnet ?? service.previewMagnet)(source,
            downloadDirectory: directory, request: request);
        final preview = wait == null
            ? await resolving
            : await resolving.timeout(Duration(seconds: wait), onTimeout: () {
                request.cancel();
                throw Failure(FailureCode.unavailable,
                    'No metadata arrived from the magnet\'s peers within $wait s.',
                    retryable: true);
              });
        return Completed(_Json({
          'name': preview.name,
          'suggestedFolderName': preview.suggestedFolderName,
          'totalSize': preview.totalSize,
          'files': [
            for (final file in preview.files)
              {
                'index': file.index,
                'path': file.path,
                'length': file.length,
              }
          ],
        }));
      } on AnyhowException catch (error) {
        throw Failure(FailureCode.unavailable, error.toString(),
            retryable: true);
      } on String catch (error) {
        throw Failure(FailureCode.unavailable, error, retryable: true);
      } finally {
        request.cancel();
      }
    }
    if (verb == 'forget_directories') {
      for (final directory
          in (input.json['directories'] as List).cast<String>()) {
        await service.removeRecentDownloadDirectory(directory);
      }
    }
    return Completed(_Json({
      'defaultDirectory': await service.getDownloadDirectory(),
      'recentDirectories': await service.loadRecentDownloadDirectories(),
    }));
  }
}
