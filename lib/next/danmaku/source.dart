import 'dart:async';
import 'package:nipa_harness/nipa_harness.dart';

const platformSessionLoginHint = '在 NipaPlay「设置 → 实验室 → 平台登录」中登录（仅 macOS）；'
    'Agent 可用 ui.open_platform_login 打开登录页，密码由用户输入。';

enum SourceStatus {
  validEmpty,
  complete,
  partial,
  authenticationRequired,
  accessDenied,
  rateLimited,
  schemaChanged,
  transportFailed,
  cancelled
}

final class SourceFailure implements Exception {
  const SourceFailure(this.status, {this.retryAt, this.diagnostics});
  final SourceStatus status;
  final DateTime? retryAt;
  final String? diagnostics;
  String get message =>
      '${status.name}${diagnostics == null ? "" : "; $diagnostics"}';
}

final class DanmakuCancellation {
  DanmakuCancellation();
  final _stop = Completer<void>();
  bool get cancelled => _stop.isCompleted;
  Future<void> get stopped => _stop.future;
  void cancel() {
    if (!cancelled) _stop.complete();
  }

  void check() {
    if (cancelled) throw const SourceFailure(SourceStatus.cancelled);
  }
}

/// The host binds this opaque reference to an account, source version and profile.
/// No secret or signed request is returned to a source.
final class DanmakuAccess {
  const DanmakuAccess(this.credentialRef);
  final String credentialRef;
}

final class DanmakuVideo implements JsonEncodable {
  const DanmakuVideo(
      {required this.sourceId,
      required this.videoId,
      required this.title,
      required this.durationMs,
      this.objectType = 'video'});
  final String sourceId, videoId, title, objectType;
  final int durationMs;
  factory DanmakuVideo.fromJson(JsonMap json) => DanmakuVideo(
      sourceId: json['sourceId'] as String,
      videoId: json['videoId'] as String,
      title: json['title'] as String,
      durationMs: json['durationMs'] as int,
      objectType: json['objectType'] as String);
  @override
  JsonMap toJson() => {
        'sourceId': sourceId,
        'videoId': videoId,
        'title': title,
        'durationMs': durationMs,
        'objectType': objectType
      };
}

final class DanmakuEntry implements JsonEncodable {
  const DanmakuEntry(
      {required this.sourceId,
      required this.videoId,
      required this.platform,
      required this.sourceTimeMs,
      required this.text,
      required this.mode,
      required this.colorRgb,
      this.platformId,
      this.sourceEntryId,
      this.originSource,
      this.originVideoId,
      this.sender,
      this.fontSize,
      this.sentAt});
  final String sourceId, videoId, platform, text;
  final String? platformId,
      sourceEntryId,
      originSource,
      originVideoId,
      sender,
      sentAt;
  final int sourceTimeMs, mode, colorRgb;
  final int? fontSize;
  factory DanmakuEntry.fromJson(JsonMap j) => DanmakuEntry(
      sourceId: j['sourceId'] as String,
      videoId: j['videoId'] as String,
      platform: j['platform'] as String,
      sourceTimeMs: j['sourceTimeMs'] as int,
      text: j['text'] as String,
      mode: j['mode'] as int,
      colorRgb: j['colorRgb'] as int,
      platformId: j['platformId'] as String?,
      sourceEntryId: j['sourceEntryId'] as String?,
      originSource: j['originSource'] as String?,
      originVideoId: j['originVideoId'] as String?,
      sender: j['sender'] as String?,
      fontSize: j['fontSize'] as int?,
      sentAt: j['sentAt'] as String?);
  @override
  JsonMap toJson() => {
        'sourceId': sourceId,
        'videoId': videoId,
        'platform': platform,
        'sourceTimeMs': sourceTimeMs,
        'text': text,
        'mode': mode,
        'colorRgb': colorRgb,
        'platformId': platformId,
        'sourceEntryId': sourceEntryId,
        'originSource': originSource,
        'originVideoId': originVideoId,
        'sender': sender,
        'fontSize': fontSize,
        'sentAt': sentAt
      };
  Map<String, dynamic> toPlayer() => {
        'time': sourceTimeMs / 1000,
        'content': text,
        'type': mode == 4
            ? 'bottom'
            : mode == 5
                ? 'top'
                : 'scroll',
        'color':
            'rgb(${colorRgb >> 16},${(colorRgb >> 8) & 255},${colorRgb & 255})',
        'source': platform,
        'sourceId': sourceId,
        'platformVideoId': originVideoId,
        'platformDanmakuId': platformId,
        'sourceEntryId': sourceEntryId,
        'originSource': originSource,
        'senderId': sender,
        'sourceTimeMs': sourceTimeMs,
        'originalMode': mode,
        'modeDowngraded': ![1, 4, 5].contains(mode),
        if (fontSize != null) 'fontSize': fontSize,
        if (sentAt != null) 'sentAt': sentAt,
      };
}

JsonMap localDanmakuProvenance(List<DanmakuEntry> entries) {
  final first = entries.firstOrNull;
  if (first == null ||
      entries.any((entry) =>
          entry.platform != first.platform ||
          entry.originVideoId != first.originVideoId)) {
    return {'platform': 'unknown', 'platformVideoId': null};
  }
  return {'platform': first.platform, 'platformVideoId': first.originVideoId};
}

final class DanmakuChunk implements JsonEncodable {
  const DanmakuChunk(this.index, this.startMs, this.endMs);
  final int index, startMs, endMs;
  @override
  JsonMap toJson() => {'index': index, 'startMs': startMs, 'endMs': endMs};
}

final class DanmakuChunkResult {
  const DanmakuChunkResult(this.entries, {this.coverage = 'currentPool'});
  final List<DanmakuEntry> entries;
  final String coverage;
  SourceStatus get status =>
      entries.isEmpty ? SourceStatus.validEmpty : SourceStatus.complete;
}

final class DanmakuDescriptor implements JsonEncodable {
  const DanmakuDescriptor(
      {required this.id,
      required this.platform,
      required this.hosts,
      required this.profiles,
      required this.access,
      required this.segmentMs,
      this.search = false,
      this.listEpisodes = true,
      this.aggregation = false});
  final String id, platform, access;
  final List<String> hosts, profiles;
  final int segmentMs;
  final bool search, listEpisodes, aggregation;
  String get version => '1';
  @override
  JsonMap toJson() => {
        'sourceId': id,
        'contractVersion': 1,
        'implementationVersion': version,
        'platform': platform,
        'runtimePlatforms': ['io'],
        'access': access,
        'allowedHosts': hosts,
        'requestProfiles': profiles,
        'search': search,
        'listEpisodes': listEpisodes,
        'resolve': true,
        'segmentedFetch': segmentMs > 0,
        'rangeFetch': true,
        'resumableFetch': true,
        'cursorFetch': false,
        'supportedModes': [1, 4, 5],
        'aggregation': aggregation,
        'compositionKnown': !aggregation,
        'concurrency': 1,
        'requestBudget': 120,
        'responseBytes': 8388608,
        'itemCount': 100000,
        'historyFetch': false
      };
}

/// Pure Dart plugin boundary. Requests, sessions, budgets and cache belong to host.
abstract interface class DanmakuSource {
  DanmakuDescriptor get describe;
  Future<List<DanmakuVideo>> search(String query, DanmakuCancellation cancel);
  Future<List<DanmakuVideo>> listEpisodes(
      String workId, int page, DanmakuCancellation cancel);
  Future<List<DanmakuVideo>> resolve(
      String locator, DanmakuCancellation cancel);
  List<DanmakuChunk> planFetch(DanmakuVideo video, int startMs, int endMs);
  Future<DanmakuChunkResult> fetchChunk(DanmakuVideo video, DanmakuChunk chunk,
      DanmakuAccess? access, DanmakuCancellation cancel);
  bool validate(List<DanmakuChunk> plan, Set<int> completed);
}

/// Implementations accept only named profiles and typed business parameters.
/// In particular youku.minute must sign and send inside the host, never expose
/// token material to a plugin, and reject unbound sessions or redirects.
abstract interface class DanmakuHost {
  Future<List<int>> request(String profile, JsonMap parameters,
      DanmakuAccess? access, DanmakuCancellation cancel);
  bool sessionAvailable(String sourceId);
}
