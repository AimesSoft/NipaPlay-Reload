import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:path/path.dart' as p;

import '../downloads/download_runtime.dart';
import '../downloads/download_paths.dart';

final class DownloadPlaybackCapability implements Capability {
  DownloadPlaybackCapability(
      DownloadRuntime runtime, Future<bool> Function(PlayableItem) start)
      : actions = [_PlayDownload(runtime, start)];
  @override
  final List<Action> actions;
}

final class _Json implements JsonEncodable {
  const _Json(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _PlayDownload extends Action<_Json, _Json> {
  _PlayDownload(this.runtime, this.start);
  final DownloadRuntime runtime;
  final Future<bool> Function(PlayableItem) start;
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'download.play',
        title: 'Play a download file',
        description:
            'Play an included video at fileIndex from download.read. A complete, size-verified local file plays from disk without resuming the rest of the task. Unfinished files use Classic streaming and resume a paused task. finished describes the task; fileComplete describes the selected file.',
        effect: Effect.write,
        input: ObjectSchema({
          'jobId': StringSchema(minLength: 1),
          'fileIndex': IntegerSchema(minimum: 0),
        }, required: [
          'jobId',
          'fileIndex'
        ]),
        output: ObjectSchema({
          'path': StringSchema(minLength: 1),
          'fileIndex': IntegerSchema(minimum: 0),
          'finished': BooleanSchema(),
          'fileComplete': BooleanSchema(),
        }, required: [
          'path',
          'fileIndex',
          'finished'
        ]),
      );
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final id = input.json['jobId'] as String;
    final snapshot = await runtime.downloads.snapshot(id);
    if (snapshot == null) {
      throw const Failure(
          FailureCode.notFound, 'Download is absent from its backend session.');
    }
    final index = (input.json['fileIndex'] as num).toInt();
    if (index >= snapshot.files.length ||
        !snapshot.files[index].included ||
        !snapshot.files[index].isVideo) {
      throw const Failure(
          FailureCode.invalidInput, 'fileIndex must select an included video.');
    }
    final observed = snapshot.files[index];
    final completeLocal = observed.complete && observed.location.isLocal;
    if (completeLocal) {
      final path = await checkedDownloadPath(
          snapshot.output.path, observed.location.path);
      final local = File(path);
      if (!await local.exists() ||
          await local.length() != observed.expectedSize) {
        throw const Failure(FailureCode.unavailable,
            'Completed video is missing or has an incorrect size.');
      }
      final history = await WatchHistoryManager.getHistoryItem(path);
      if (!await start(PlayableItem(
          videoPath: path,
          historyItem: history,
          title: history?.animeName ?? p.basename(path),
          subtitle: history?.episodeTitle ?? snapshot.title))) {
        throw const Failure(FailureCode.unavailable,
            'NipaPlay cannot start playback right now.',
            retryable: true);
      }
      return Completed(_Json({
        'path': path,
        'fileIndex': index,
        'finished': snapshot.finished,
        'fileComplete': true
      }));
    }
    final service = TorrentDownloadService.instance;
    final task = (await service.listTasks())
        .singleWhere((t) => t.id.toString() == snapshot.handle);
    final file = (await service.listPlayableFiles(task))
        .singleWhere((f) => f.index == index);
    if (!task.canPlay) {
      throw const Failure(FailureCode.unavailable,
          'Download has no playable metadata or has a backend error.',
          retryable: true);
    }
    if (!task.finished && task.isPaused) await runtime.downloads.resume(id);
    final source = await service.getPlaybackSource(task, file);
    if (!await start(PlayableItem(
      videoPath: source.videoPath,
      actualPlayUrl: source.actualPlayUrl,
      historyItem: source.historyItem,
      title: source.historyItem?.animeName ?? file.fileName,
      subtitle: source.historyItem?.episodeTitle ?? task.name,
    ))) {
      throw const Failure(
          FailureCode.unavailable, 'NipaPlay cannot start playback right now.',
          retryable: true);
    }
    return Completed(_Json({
      'path': source.videoPath,
      'fileIndex': index,
      'finished': task.finished,
      'fileComplete': observed.complete
    }));
  }
}
