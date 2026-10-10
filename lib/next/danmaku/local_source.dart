import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/local_danmaku_file.dart';
import 'package:nipaplay/utils/danmaku_parser.dart';
import 'package:nipaplay/utils/danmaku_xml_utils.dart';
import 'source.dart';

/// Explicit local imports use Classic's parser; discovery remains with Classic.
final class LocalDanmakuSource implements DanmakuSource {
  const LocalDanmakuSource(this.authorize);
  final Future<String> Function(String path) authorize;
  @override
  DanmakuDescriptor get describe => const DanmakuDescriptor(
      id: 'local',
      platform: 'unknown',
      hosts: [],
      profiles: [],
      access: 'localFile',
      segmentMs: 0,
      listEpisodes: false);
  @override
  Future<List<DanmakuVideo>> search(String query, DanmakuCancellation cancel) =>
      throw const Failure(
          FailureCode.unavailable, 'Local files do not support title search.');
  @override
  Future<List<DanmakuVideo>> listEpisodes(
          String workId, int page, DanmakuCancellation cancel) =>
      throw const Failure(
          FailureCode.unavailable, 'Local files have no catalogue.');
  @override
  Future<List<DanmakuVideo>> resolve(
      String locator, DanmakuCancellation cancel) async {
    cancel.check();
    final path = await authorize(locator);
    return [
      DanmakuVideo(
          sourceId: 'local',
          videoId: path,
          title: File(path).uri.pathSegments.last,
          durationMs: 0,
          objectType: 'file')
    ];
  }

  @override
  List<DanmakuChunk> planFetch(DanmakuVideo video, int startMs, int endMs) {
    if (video.sourceId != 'local' ||
        video.objectType != 'file' ||
        startMs < 0 ||
        endMs <= startMs ||
        endMs > video.durationMs ||
        video.durationMs > 7200000) {
      throw const Failure(
          FailureCode.invalidInput, 'Invalid local file range.');
    }
    return [DanmakuChunk(0, startMs, endMs)];
  }

  @override
  bool validate(List<DanmakuChunk> plan, Set<int> completed) =>
      plan.length == completed.length &&
      plan.every((c) => completed.contains(c.index));
  @override
  Future<DanmakuChunkResult> fetchChunk(DanmakuVideo video, DanmakuChunk chunk,
      DanmakuAccess? access, DanmakuCancellation cancel) async {
    if (access != null) {
      throw const Failure(
          FailureCode.invalidInput, 'Local files do not take credentials.');
    }
    final path = await authorize(video.videoId);
    final file = File(path);
    if (await file.length() > 8388608) {
      throw const SourceFailure(SourceStatus.schemaChanged);
    }
    final bytes = await file.readAsBytes();
    cancel.check();
    final Map<String, dynamic> data;
    try {
      data = parseLocalDanmakuBytes(bytes);
    } on FormatException {
      throw const SourceFailure(SourceStatus.schemaChanged);
    }
    final rows = parseDanmakuListInBackground(data['comments'] as List);
    if (rows.isEmpty) throw const SourceFailure(SourceStatus.schemaChanged);
    return DanmakuChunkResult([
      for (final row in rows)
        DanmakuEntry(
            sourceId: 'local',
            videoId: path,
            platform: data['platform'] == 'unknown'
                ? row['source'] as String? ?? 'unknown'
                : data['platform'] as String,
            originVideoId: row['platformVideoId'] as String? ??
                data['platformVideoId'] as String?,
            platformId: row['platformDanmakuId'] as String?,
            sourceTimeMs: ((row['time'] as num) * 1000).round(),
            text: row['content'] as String,
            mode: row['type'] == 'top' || row['type'] == 5
                ? 5
                : row['type'] == 'bottom' || row['type'] == 4
                    ? 4
                    : 1,
            colorRgb: parseDanmakuColorToInt(row['color']),
            sender: row['senderId'] as String?)
    ]);
  }
}
