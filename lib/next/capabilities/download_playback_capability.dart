import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/services/torrent_download_service.dart';

import '../downloads/download_runtime.dart';

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
            'Play the video at fileIndex from download.read. Uses Classic disk/history resolution for completed files, including unimported files, and Classic streaming for unfinished files. Resumes a paused unfinished task as the Classic Play button does.',
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
    final service = TorrentDownloadService.instance;
    final task = (await service.listTasks())
        .singleWhere((t) => t.id.toString() == snapshot.handle);
    if (!task.canPlay) {
      throw const Failure(FailureCode.unavailable,
          'Download has no playable metadata or has a backend error.',
          retryable: true);
    }
    final index = (input.json['fileIndex'] as num).toInt();
    final files =
        (await service.listPlayableFiles(task)).where((f) => f.index == index);
    if (files.isEmpty) {
      throw const Failure(
          FailureCode.invalidInput, 'fileIndex must select an included video.');
    }
    final file = files.single;
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
      'finished': task.finished
    }));
  }
}
