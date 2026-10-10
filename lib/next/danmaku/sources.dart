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

int integer(Object? value) {
  if (value is int) return value;
  if (value is String) {
    final n = int.tryParse(value);
    if (n != null) return n;
  }
  schemaChanged();
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

JsonMap jsonObject(Object? value) {
  if (value is! String) return object(value);
  try {
    return object(jsonDecode(value));
  } on FormatException {
    schemaChanged();
  }
}

abstract base class _Source implements DanmakuSource {
  const _Source(this.host);
  final DanmakuHost host;
  Future<JsonMap> requestJson(
          String profile, JsonMap parameters, DanmakuCancellation c,
          [DanmakuAccess? access]) async =>
      decodeObject(await host.request(profile, parameters, access, c));
  @override
  Future<List<DanmakuVideo>> search(String query, DanmakuCancellation cancel) =>
      throw const Failure(FailureCode.unavailable,
          'This source does not support title search. Resolve a public video URL or ID.');
  @override
  List<DanmakuChunk> planFetch(DanmakuVideo video, int startMs, int endMs) {
    final objectType = switch (describe.id) {
      'bilibili' => 'cid',
      'dandanplay' => 'episode',
      _ => 'video'
    };
    final validId =
        RegExp(describe.id == 'youku' ? r'^[A-Za-z0-9=]+$' : r'^\d+$')
            .hasMatch(video.videoId);
    if (video.sourceId != describe.id ||
        video.objectType != objectType ||
        !validId ||
        video.videoId.length > 128 ||
        startMs < 0 ||
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
  const DandanplayDanmakuSource(super.host,
      {this.allowedHosts = const ['api.dandanplay.net']});
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
      DanmakuAccess? access, DanmakuCancellation cancel) async {
    final data = await requestJson(
        'dandanplay.comments', {'videoId': video.videoId}, cancel, access);
    if (data['success'] == false) {
      throw const SourceFailure(SourceStatus.accessDenied);
    }
    final result = <DanmakuEntry>[];
    for (final raw in array(data['comments'])) {
      final row = object(raw);
      Map<String, dynamic> parsed;
      try {
        parsed = parseDandanplayComment(row);
      } on FormatException {
        schemaChanged();
      }
      result.add(DanmakuEntry(
          sourceId: 'dandanplay',
          videoId: video.videoId,
          platform: parsed['source'] as String,
          originSource: parsed['originSource'] as String?,
          sourceEntryId: parsed['sourceEntryId'] as String?,
          sourceTimeMs: parsed['sourceTimeMs'] as int,
          text: parsed['content'] as String,
          mode: parsed['originalMode'] as int,
          colorRgb: parsed['colorRgb'] as int,
          sender: parsed['senderId'] as String?,
          platformId: parsed['platformDanmakuId'] as String?,
          originVideoId: parsed['platformVideoId'] as String?));
    }
    return DanmakuChunkResult(result, coverage: 'relatedPool');
  }
}

final class BilibiliDanmakuSource extends _Source {
  const BilibiliDanmakuSource(super.host);
  @override
  DanmakuDescriptor get describe => const DanmakuDescriptor(
      id: 'bilibili',
      platform: 'bilibili',
      hosts: ['api.bilibili.com'],
      profiles: [
        'bilibili.view',
        'bilibili.season',
        'bilibili.segment',
        'bilibili.search'
      ],
      access: 'anonymous',
      search: true,
      segmentMs: 360000);
  JsonMap data(JsonMap root) {
    final code = integer(root['code']);
    if (code == -101) {
      throw const SourceFailure(SourceStatus.authenticationRequired,
          diagnostics: platformSessionLoginHint);
    }
    if (code == -403) throw const SourceFailure(SourceStatus.accessDenied);
    if (code == -412) throw const SourceFailure(SourceStatus.rateLimited);
    if (code != 0) throw const SourceFailure(SourceStatus.accessDenied);
    return object(root['data'] ?? root['result']);
  }

  @override
  Future<List<DanmakuVideo>> search(
      String query, DanmakuCancellation cancel) async {
    final root =
        data(await requestJson('bilibili.search', {'query': query}, cancel));
    return [
      for (final raw in array(root['result']).take(20))
        DanmakuVideo(
            sourceId: 'bilibili',
            videoId: identifier(object(raw)['bvid']),
            title: string(object(raw)['title'])
                .replaceAll(RegExp(r'<[^>]*>'), '')
                .replaceAll('&amp;', '&')
                .replaceAll('&quot;', '"')
                .replaceAll('&#39;', "'"),
            durationMs: 0,
            objectType: 'bvid')
    ];
  }

  @override
  Future<List<DanmakuVideo>> listEpisodes(
      String workId, int page, DanmakuCancellation cancel) async {
    if (page != 1) {
      throw const Failure(
          FailureCode.invalidInput, 'Bilibili catalogue has no pages.');
    }
    final root = data(
        await requestJson('bilibili.season', {'seasonId': workId}, cancel));
    return [
      for (final ep in array(root['episodes']))
        DanmakuVideo(
            sourceId: 'bilibili',
            videoId: identifier(object(ep)['cid']),
            title: string(object(ep)['title']),
            durationMs: integer(object(ep)['duration']),
            objectType: 'cid')
    ];
  }

  @override
  Future<List<DanmakuVideo>> resolve(
      String locator, DanmakuCancellation cancel) async {
    final uri = Uri.tryParse(locator);
    String id = locator;
    if (uri != null && uri.hasScheme) {
      if (uri.scheme != 'https' ||
          !['www.bilibili.com', 'bilibili.com'].contains(uri.host)) {
        throw const Failure(
            FailureCode.invalidInput, 'Expected a public Bilibili URL.');
      }
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) {
        throw const Failure(
            FailureCode.invalidInput, 'Expected a Bilibili video page.');
      }
      id = segments.last;
      final episode = uri.queryParameters['ep_id'];
      if (episode != null) {
        if (!RegExp(r'^\d+$').hasMatch(episode)) {
          throw const Failure(
              FailureCode.invalidInput, 'Invalid episode selector.');
        }
        id = 'ep$episode';
      }
    }
    if (RegExp(r'^ss\d+$').hasMatch(id)) {
      return listEpisodes(id.substring(2), 1, cancel);
    }
    if (RegExp(r'^ep\d+$').hasMatch(id)) {
      final root = data(await requestJson(
          'bilibili.season', {'episodeId': id.substring(2)}, cancel));
      final eps = array(root['episodes'])
          .where((e) => identifier(object(e)['id']) == id.substring(2));
      return [
        for (final e in eps)
          DanmakuVideo(
              sourceId: 'bilibili',
              videoId: identifier(object(e)['cid']),
              title: string(object(e)['title']),
              durationMs: integer(object(e)['duration']),
              objectType: 'cid')
      ];
    }
    if (RegExp(r'^\d+$').hasMatch(id)) {
      return [
        DanmakuVideo(
            sourceId: 'bilibili',
            videoId: id,
            title: id,
            durationMs: 0,
            objectType: 'cid')
      ];
    }
    if (!RegExp(r'^(BV[0-9A-Za-z]+|av\d+)$').hasMatch(id)) {
      throw const Failure(
          FailureCode.invalidInput, 'Expected BV, av, ep, ss or cid.');
    }
    final root = data(await requestJson(
        'bilibili.view',
        {
          id.startsWith('BV') ? 'bvid' : 'aid':
              id.startsWith('BV') ? id : id.substring(2)
        },
        cancel));
    var pages = array(root['pages']);
    final part = uri?.queryParameters['p'];
    if (part != null) {
      if (!RegExp(r'^[1-9]\d*$').hasMatch(part)) {
        throw const Failure(FailureCode.invalidInput, 'Invalid part selector.');
      }
      pages = pages.where((p) => '${object(p)['page']}' == part).toList();
    }
    return [
      for (final p in pages)
        DanmakuVideo(
            sourceId: 'bilibili',
            videoId: identifier(object(p)['cid']),
            title: '${string(root['title'])} · ${string(object(p)['part'])}',
            durationMs: integer(object(p)['duration']) * 1000,
            objectType: 'cid')
    ];
  }

  @override
  Future<DanmakuChunkResult> fetchChunk(DanmakuVideo video, DanmakuChunk chunk,
          DanmakuAccess? access, DanmakuCancellation cancel) async =>
      DanmakuChunkResult(decodeBilibili(
          await host.request(
              'bilibili.segment',
              {'videoId': video.videoId, 'segmentIndex': chunk.index + 1},
              access,
              cancel),
          video));
}

/// Bounded protobuf wire reader for DmSegMobileReply / DanmakuElem. Unknown
/// fields are skipped by wire type; IDs use BigInt to avoid truncation.
final class _Proto {
  _Proto(this.bytes);
  final List<int> bytes;
  int pos = 0;
  BigInt varint() {
    var value = BigInt.zero;
    for (var shift = 0; shift < 70; shift += 7) {
      if (pos >= bytes.length) schemaChanged();
      final b = bytes[pos++];
      if (shift == 63 && b > 1) schemaChanged();
      value |= BigInt.from(b & 127) << shift;
      if (b < 128) return value;
    }
    schemaChanged();
  }

  Map<int, Object> fields({bool elements = false}) {
    final out = <int, Object>{};
    while (pos < bytes.length) {
      final rawTag = varint();
      if (rawTag > BigInt.from(4294967295)) schemaChanged();
      final tag = rawTag.toInt(), field = tag >> 3, wire = tag & 7;
      if (field == 0) schemaChanged();
      final Object value;
      if (wire == 0) {
        value = varint();
      } else if (wire == 2) {
        final size = varint();
        if (size > BigInt.from(bytes.length - pos)) schemaChanged();
        value = bytes.sublist(pos, pos + size.toInt());
        pos += size.toInt();
      } else if (wire == 1 || wire == 5) {
        final size = wire == 1 ? 8 : 4;
        if (pos + size > bytes.length) schemaChanged();
        pos += size;
        continue;
      } else {
        schemaChanged();
      }
      if (elements && field == 1) {
        if (value is! List<int>) schemaChanged();
        final items = (out[1] ??= <List<int>>[]) as List<List<int>>;
        if (items.length >= 100000) schemaChanged();
        items.add(value);
      } else {
        out[field] = value;
      }
    }
    return out;
  }
}

List<DanmakuEntry> decodeBilibili(List<int> bytes, DanmakuVideo video) {
  if (bytes.length > 8388608) schemaChanged();
  final root = _Proto(bytes).fields(elements: true);
  if (bytes.isNotEmpty && !root.containsKey(1)) schemaChanged();
  final entries = <DanmakuEntry>[];
  for (final raw in (root[1] as List<List<int>>? ?? const [])) {
    final f = _Proto(raw).fields();
    int number(int key) {
      final v = f[key];
      if (v == null) return 0;
      if (v is! BigInt || v > BigInt.from(9007199254740991)) schemaChanged();
      return v.toInt();
    }

    String text(int key) {
      final v = f[key];
      if (v == null) return '';
      if (v is! List<int>) schemaChanged();
      try {
        return utf8.decode(v);
      } on FormatException {
        schemaChanged();
      }
    }

    final rawId =
        f[12] == null ? (f[1] is BigInt ? '${f[1]}' : null) : text(12);
    final id = rawId == null || rawId.isEmpty || rawId == '0' ? null : rawId;
    entries.add(DanmakuEntry(
        sourceId: 'bilibili',
        videoId: video.videoId,
        platform: 'bilibili',
        originVideoId: video.videoId,
        platformId: id,
        sourceTimeMs: number(2),
        mode: number(3),
        fontSize: number(4),
        colorRgb: number(5),
        sender: f[6] == null ? null : text(6),
        text: text(7),
        sentAt: f[8] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(number(8) * 1000, isUtc: true)
                .toIso8601String()));
  }
  return entries;
}

final class YoukuDanmakuSource extends _Source {
  const YoukuDanmakuSource(super.host);
  @override
  DanmakuDescriptor get describe => const DanmakuDescriptor(
      id: 'youku',
      platform: 'youku',
      hosts: ['openapi.youku.com', 'acs.youku.com'],
      profiles: ['youku.video', 'youku.episodes', 'youku.minute'],
      access: 'requiredSession',
      segmentMs: 60000);
  DanmakuVideo video(JsonMap v) => DanmakuVideo(
      sourceId: 'youku',
      videoId: identifier(v['id']),
      title: string(v['title']),
      durationMs: ((v['duration'] is num
                  ? v['duration'] as num
                  : num.tryParse('${v['duration']}') ?? (schemaChanged())) *
              1000)
          .round());
  @override
  Future<List<DanmakuVideo>> listEpisodes(
      String workId, int page, DanmakuCancellation cancel) async {
    final root = await requestJson(
        'youku.episodes', {'workId': workId, 'page': page}, cancel);
    if (root.containsKey('error')) {
      throw const SourceFailure(SourceStatus.accessDenied);
    }
    return [for (final v in array(root['videos'])) video(object(v))];
  }

  @override
  Future<List<DanmakuVideo>> resolve(
      String locator, DanmakuCancellation cancel) async {
    var id = locator;
    final uri = Uri.tryParse(locator);
    if (uri != null && uri.hasScheme) {
      if (uri.scheme != 'https' || uri.host != 'v.youku.com') {
        throw const Failure(
            FailureCode.invalidInput, 'Expected a public Youku URL.');
      }
      final match =
          RegExp(r'^/v_show/id_([A-Za-z0-9=]+)\.html$').firstMatch(uri.path);
      if (match == null) {
        throw const Failure(
            FailureCode.invalidInput, 'Expected a Youku video page.');
      }
      id = match[1]!;
    }
    if (!RegExp(r'^[A-Za-z0-9=]+$').hasMatch(id)) {
      throw const Failure(FailureCode.invalidInput, 'Invalid Youku vid.');
    }
    final root = await requestJson('youku.video', {'videoId': id}, cancel);
    if (root.containsKey('error')) {
      throw const SourceFailure(SourceStatus.accessDenied);
    }
    return [video(root)];
  }

  @override
  Future<DanmakuChunkResult> fetchChunk(DanmakuVideo video, DanmakuChunk chunk,
      DanmakuAccess? access, DanmakuCancellation cancel) async {
    if (access == null) {
      throw const SourceFailure(SourceStatus.authenticationRequired,
          diagnostics: platformSessionLoginHint);
    }
    final root = await requestJson('youku.minute',
        {'videoId': video.videoId, 'minute': chunk.index}, cancel, access);
    final ret = array(root['ret']).map(string).toList();
    if (!ret.any((s) => s.startsWith('SUCCESS::'))) {
      if (ret.any((s) => s.contains('TOKEN') || s.contains('SESSION'))) {
        throw const SourceFailure(SourceStatus.authenticationRequired,
            diagnostics: platformSessionLoginHint);
      }
      if (ret.any((s) => s.contains('LIMIT'))) {
        throw const SourceFailure(SourceStatus.rateLimited);
      }
      throw const SourceFailure(SourceStatus.accessDenied);
    }
    final nested = jsonObject(object(root['data'])['result']);
    final items = array(object(nested['data'])['result']);
    final entries = <DanmakuEntry>[];
    for (final raw in items) {
      final row = object(raw);
      final props = row['propertis'] == null
          ? <String, Object?>{}
          : jsonObject(row['propertis']);
      final pos = props['pos'] == null ? 1 : integer(props['pos']);
      entries.add(DanmakuEntry(
          sourceId: 'youku',
          videoId: video.videoId,
          platform: 'youku',
          originVideoId: video.videoId,
          platformId: row['id'] == null ? null : identifier(row['id']),
          sourceTimeMs: integer(row['playat']),
          text: string(row['content']),
          mode: pos == 4
              ? 5
              : pos == 3
                  ? 1
                  : 4,
          fontSize: props['size'] == null ? null : integer(props['size']),
          colorRgb: props['color'] == null ? 16777215 : integer(props['color']),
          sentAt:
              row['createtime'] == null ? null : string(row['createtime'])));
    }
    return DanmakuChunkResult(entries);
  }
}
