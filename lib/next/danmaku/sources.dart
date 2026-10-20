import 'package:nipaplay/utils/dandanplay_comments.dart';
import 'dart:convert';
import 'source.dart';
import 'package:nipa_harness/nipa_harness.dart';

Never schemaChanged() => throw const SourceFailure(SourceStatus.schemaChanged);
JsonMap object(Object? value) {
  if (value is! Map || value.keys.any((k) => k is! String)) schemaChanged();
  return Map<String, Object?>.from(value);
}

List<Object?> array(Object? value) {
  if (value is! List || value.length > 100000) schemaChanged();
  return value;
}

String string(Object? value) {
  if (value is! String) schemaChanged();
  return value;
}

String identifier(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  if (value is int && value > 0) return '$value';
  schemaChanged();
}

JsonMap decodeObject(List<int> bytes) {
  try {
    return object(jsonDecode(utf8.decode(bytes)));
  } on FormatException {
    schemaChanged();
  }
}

abstract base class _Source implements DanmakuSource {
  const _Source(this.host);
  final DanmakuHost host;
  Future<JsonMap> requestJson(
          String profile, JsonMap parameters, DanmakuCancellation c) async =>
      decodeObject(await host.request(profile, parameters, c));
  @override
  Future<List<DanmakuVideo>> search(String query, DanmakuCancellation cancel) =>
      throw const Failure(FailureCode.unavailable,
          'This source does not support title search. Resolve a public video URL or ID.');
  @override
  List<DanmakuChunk> planFetch(DanmakuVideo video, int startMs, int endMs) {
    const objectType = 'episode';
    final validId = RegExp(r'^\d+$').hasMatch(video.videoId);
    if (video.sourceId != describe.id ||
        video.objectType != objectType ||
        !validId ||
        video.videoId.length > 128) {
      throw const Failure(FailureCode.invalidInput,
          'video must be a Dandanplay episode with a numeric videoId.');
    }
    // Search results do not know an episode's length; say so, rather than
    // calling a zero length a range problem.
    if (video.durationMs <= 0) {
      throw const Failure(FailureCode.invalidInput,
          'video.durationMs is unknown (0) and the entity has no local file NipaPlay could measure; give the video\'s duration.');
    }
    if (startMs < 0 ||
        endMs <= startMs ||
        endMs > video.durationMs ||
        video.durationMs > 7200000) {
      throw const Failure(FailureCode.invalidInput,
          'Fetch range must be inside a video of at most two hours.');
    }
    final size = describe.segmentMs;
    if (size == 0) return [DanmakuChunk(0, startMs, endMs)];
    final first = startMs ~/ size, last = (endMs - 1) ~/ size;
    if (last - first + 1 > 120) {
      throw const Failure(
          FailureCode.invalidInput, 'Fetch exceeds the 120 segment budget.');
    }
    return [
      for (var i = first; i <= last; i++)
        DanmakuChunk(
            i,
            i * size,
            (i + 1) * size < video.durationMs
                ? (i + 1) * size
                : video.durationMs)
    ];
  }

  @override
  bool validate(List<DanmakuChunk> plan, Set<int> completed) =>
      completed.length == plan.length &&
      plan.every((c) => completed.contains(c.index));
}

final class DandanplayDanmakuSource extends _Source {
  const DandanplayDanmakuSource(super.host, {required this.allowedHosts});
  final List<String> allowedHosts;
  @override
  DanmakuDescriptor get describe => DanmakuDescriptor(
      id: 'dandanplay',
      platform: 'dandanplay',
      hosts: allowedHosts,
      profiles: [
        'dandanplay.search',
        'dandanplay.episodes',
        'dandanplay.comments'
      ],
      access: 'hostPolicy',
      segmentMs: 0,
      search: true,
      aggregation: true);
  List<DanmakuVideo> episodes(JsonMap data) {
    return [
      for (final raw in array(data['animes']))
        for (final ep in array(object(raw)['episodes']))
          DanmakuVideo(
              sourceId: 'dandanplay',
              videoId: identifier(object(ep)['episodeId']),
              title:
                  '${string(object(raw)['animeTitle'])} · ${string(object(ep)['episodeTitle'])}',
              durationMs: 0,
              objectType: 'episode')
    ];
  }

  @override
  Future<List<DanmakuVideo>> search(
          String query, DanmakuCancellation cancel) async =>
      episodes(
          await requestJson('dandanplay.search', {'query': query}, cancel));
  @override
  Future<List<DanmakuVideo>> listEpisodes(
      String workId, int page, DanmakuCancellation cancel) async {
    if (page != 1) {
      throw const Failure(
          FailureCode.invalidInput, 'Dandanplay catalogue has no pages.');
    }
    final data =
        await requestJson('dandanplay.episodes', {'workId': workId}, cancel);
    return episodes({
      'animes': [object(data['bangumi'])]
    });
  }

  @override
  Future<List<DanmakuVideo>> resolve(
      String locator, DanmakuCancellation cancel) async {
    if (!RegExp(r'^\d+$').hasMatch(locator)) {
      throw const Failure(FailureCode.invalidInput,
          'Dandanplay resolution requires an episode ID.');
    }
    return [
      DanmakuVideo(
          sourceId: 'dandanplay',
          videoId: locator,
          title: locator,
          durationMs: 0,
          objectType: 'episode')
    ];
  }

  @override
  Future<DanmakuChunkResult> fetchChunk(DanmakuVideo video, DanmakuChunk chunk,
      DanmakuCancellation cancel) async {
    final data = await requestJson(
        'dandanplay.comments', {'videoId': video.videoId}, cancel);
    if (data['success'] == false) {
      throw const SourceFailure(SourceStatus.accessDenied);
    }
    final result = <DanmakuEntry>[];
    final comments = array(data['comments']);
    var unreadable = 0;
    for (final raw in comments) {
      final row = object(raw);
      // A pool holds thousands of comments from many platforms; one odd
      // comment is that comment's problem, not the pool's. Only a pool none
      // of whose comments can be read says the format changed. Colors like
      // 255255255 mean white.
      Map<String, dynamic> parsed;
      try {
        parsed = parseDandanplayComment(row);
      } on FormatException {
        unreadable++;
        continue;
      }
      final time = parsed['sourceTimeMs'] as int;
      final text = parsed['content'] as String;
      if (time < 0 || text.length > 16384) continue;
      final color = parsed['colorRgb'] as int;
      result.add(DanmakuEntry(
          sourceId: 'dandanplay',
          videoId: video.videoId,
          platform: parsed['source'] as String,
          originSource: parsed['originSource'] as String?,
          sourceEntryId: parsed['sourceEntryId'] as String?,
          sourceTimeMs: time,
          text: text,
          mode: parsed['originalMode'] as int,
          colorRgb: color < 0 || color > 0xFFFFFF ? 0xFFFFFF : color,
          sender: parsed['senderId'] as String?,
          platformId: parsed['platformDanmakuId'] as String?,
          originVideoId: parsed['platformVideoId'] as String?));
    }
    if (comments.isNotEmpty && unreadable == comments.length) schemaChanged();
    return DanmakuChunkResult(result, coverage: 'relatedPool');
  }
}
