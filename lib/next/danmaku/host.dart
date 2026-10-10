import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'source.dart';

/// A session bridge must validate the reference against the current source
/// identity/version and the youku.minute profile before signing internally.
abstract interface class YoukuSessionBridge {
  bool get available;
  Future<List<int>> minute(String videoId, int minute, DanmakuAccess access,
      DanmakuCancellation cancel);
}

/// Mint one of these per registered source execution identity. A plugin cannot
/// choose another source's profile or inspect the underlying credential client.
final class ScopedDanmakuHost implements DanmakuHost {
  const ScopedDanmakuHost(this._host, this._declaration);
  final DanmakuHost _host;
  final DanmakuDescriptor _declaration;
  @override
  bool sessionAvailable(String sourceId) =>
      sourceId == _declaration.id && _host.sessionAvailable(sourceId);
  @override
  Future<List<int>> request(String profile, JsonMap parameters,
      DanmakuAccess? access, DanmakuCancellation cancel) async {
    if (!_declaration.profiles.contains(profile)) {
      throw const Failure(FailureCode.unavailable,
          'Request profile is outside this source grant.');
    }
    return await _host.request(profile, parameters, access, cancel);
  }
}

final class HttpDanmakuHost implements DanmakuHost {
  HttpDanmakuHost(
      {required this.publicClient,
      required this.dandanplayClient,
      required this.dandanplayBase,
      required this.dandanplayHeaders,
      this.youkuSession,
      this.interval = const Duration(milliseconds: 300),
      this.timeout = const Duration(seconds: 20)});
  final http.Client publicClient, dandanplayClient;
  final Uri dandanplayBase;
  final Future<Map<String, String>> Function(String path) dandanplayHeaders;
  final YoukuSessionBridge? youkuSession;
  final Duration interval;
  final Duration timeout;
  final Map<String, Future<void>> _tails = {};
  final Map<String, DateTime> _next = {};
  @override
  bool sessionAvailable(String sourceId) =>
      sourceId == 'youku' && (youkuSession?.available ?? false);
  @override
  Future<List<int>> request(String profile, JsonMap parameters,
      DanmakuAccess? access, DanmakuCancellation cancel) async {
    final source = profile.split('.').first;
    final requestCancellation = DanmakuCancellation();
    final previous = _tails[source] ?? Future<void>.value();
    final done = Completer<void>();
    _tails[source] = previous.then((_) => done.future);
    await Future.any([previous, cancel.stopped]);
    try {
      cancel.check();
      final wait = (_next[source] ?? DateTime.now()).difference(DateTime.now());
      if (wait > Duration.zero) {
        await Future.any([Future<void>.delayed(wait), cancel.stopped]);
      }
      cancel.check();
      if (profile == 'youku.minute') {
        if (parameters.keys
                .toSet()
                .difference({'videoId', 'minute'}).isNotEmpty ||
            parameters.length != 2 ||
            parameters['videoId'] is! String ||
            parameters['minute'] is! int ||
            (parameters['minute'] as int) < 0 ||
            (parameters['minute'] as int) >= 120) {
          throw const Failure(
              FailureCode.invalidInput, 'Invalid minute profile parameters.');
        }
        if (access == null ||
            youkuSession == null ||
            !youkuSession!.available) {
          throw const SourceFailure(SourceStatus.authenticationRequired);
        }
        final bytes = await youkuSession!.minute(
            parameters['videoId'] as String,
            parameters['minute'] as int,
            access,
            cancel);
        if (bytes.length > 8388608) {
          throw const SourceFailure(SourceStatus.schemaChanged);
        }
        cancel.check();
        return bytes;
      }
      if (access != null) {
        throw const Failure(FailureCode.invalidInput,
            'Anonymous profiles do not accept session references.');
      }
      final uri = _uri(profile, parameters);
      final client = source == 'dandanplay' ? dandanplayClient : publicClient;
      cancel.stopped.then((_) => requestCancellation.cancel());
      final request = http.AbortableRequest('GET', uri,
          abortTrigger: requestCancellation.stopped)
        ..followRedirects = false
        ..headers['Accept'] = profile == 'bilibili.segment'
            ? 'application/octet-stream'
            : 'application/json';
      if (source == 'dandanplay') {
        request.headers.addAll(await dandanplayHeaders(uri.path));
      }
      cancel.check();
      final bytes = await (() async {
        final response = await client.send(request);
        if (response.statusCode == 401) {
          throw const SourceFailure(SourceStatus.authenticationRequired);
        }
        if (response.statusCode == 403 ||
            response.statusCode >= 300 && response.statusCode < 400) {
          throw const SourceFailure(SourceStatus.accessDenied);
        }
        if (response.statusCode == 429) {
          final retry = response.headers['retry-after'];
          int seconds;
          if (retry == null) {
            seconds = 30;
          } else if (int.tryParse(retry) case final value?) {
            seconds = value;
          } else {
            try {
              seconds = HttpDate.parse(retry)
                  .difference(DateTime.now().toUtc())
                  .inSeconds;
            } on FormatException {
              throw const SourceFailure(SourceStatus.schemaChanged);
            }
          }
          throw SourceFailure(SourceStatus.rateLimited,
              retryAt: DateTime.now()
                  .toUtc()
                  .add(Duration(seconds: seconds.clamp(1, 3600))));
        }
        if (response.statusCode != 200) {
          throw const SourceFailure(SourceStatus.transportFailed);
        }
        if ((response.contentLength ?? 0) > 8388608) {
          throw const SourceFailure(SourceStatus.schemaChanged);
        }
        final bytes = <int>[];
        await for (final part in response.stream) {
          cancel.check();
          if (bytes.length + part.length > 8388608) {
            throw const SourceFailure(SourceStatus.schemaChanged);
          }
          bytes.addAll(part);
        }
        return bytes;
      })()
          .timeout(timeout, onTimeout: () {
        requestCancellation.cancel();
        throw const SourceFailure(SourceStatus.transportFailed);
      });
      cancel.check();
      return bytes;
    } on http.RequestAbortedException {
      cancel.check();
      throw const SourceFailure(SourceStatus.transportFailed);
    } on http.ClientException {
      throw const SourceFailure(SourceStatus.transportFailed);
    } on SocketException {
      throw const SourceFailure(SourceStatus.transportFailed);
    } finally {
      requestCancellation.cancel();
      _next[source] = DateTime.now().add(interval);
      done.complete();
    }
  }

  Uri _uri(String profile, JsonMap p) {
    final fields = switch (profile) {
      'dandanplay.search' => {'query'},
      'dandanplay.episodes' => {'workId'},
      'dandanplay.comments' => {'videoId'},
      'bilibili.view' => p.containsKey('bvid') ? {'bvid'} : {'aid'},
      'bilibili.season' =>
        p.containsKey('seasonId') ? {'seasonId'} : {'episodeId'},
      'bilibili.segment' => {'videoId', 'segmentIndex'},
      'youku.video' => {'videoId'},
      'youku.episodes' => {'workId', 'page'},
      _ => throw const Failure(
          FailureCode.invalidInput, 'Unknown request profile.')
    };
    if (p.length != fields.length ||
        p.keys.any((key) => !fields.contains(key))) {
      throw const Failure(
          FailureCode.invalidInput, 'Unexpected request profile parameters.');
    }
    String value(String name, {String pattern = r'^[A-Za-z0-9_=]+$'}) {
      final v = p[name];
      if (v is! String || !RegExp(pattern).hasMatch(v)) {
        throw const Failure(
            FailureCode.invalidInput, 'Invalid request profile ID.');
      }
      return v;
    }

    Uri uri(String host, String path, Map<String, String> query) =>
        Uri.https(host, path, query);
    switch (profile) {
      case 'dandanplay.search':
        if (p['query'] is! String ||
            (p['query'] as String).isEmpty ||
            (p['query'] as String).length > 200) {
          throw const Failure(
              FailureCode.invalidInput, 'Invalid search query.');
        }
        return dandanplayBase
            .resolve('/api/v2/search/episodes')
            .replace(queryParameters: {'anime': p['query'] as String});
      case 'dandanplay.episodes':
        return dandanplayBase
            .resolve('/api/v2/bangumi/${value('workId', pattern: r'^\d+$')}');
      case 'dandanplay.comments':
        return dandanplayBase
            .resolve('/api/v2/comment/${value('videoId', pattern: r'^\d+$')}')
            .replace(
                queryParameters: {'withRelated': 'true', 'chConvert': '0'});
      case 'bilibili.view':
        return uri(
            'api.bilibili.com',
            '/x/web-interface/view',
            p.containsKey('bvid')
                ? {'bvid': value('bvid')}
                : {'aid': value('aid', pattern: r'^\d+$')});
      case 'bilibili.season':
        return uri(
            'api.bilibili.com',
            '/pgc/view/web/season',
            p.containsKey('seasonId')
                ? {'season_id': value('seasonId', pattern: r'^\d+$')}
                : {'ep_id': value('episodeId', pattern: r'^\d+$')});
      case 'bilibili.segment':
        final index = p['segmentIndex'];
        if (index is! int || index < 1 || index > 20) {
          throw const Failure(
              FailureCode.invalidInput, 'Invalid segment index.');
        }
        return uri('api.bilibili.com', '/x/v2/dm/web/seg.so', {
          'type': '1',
          'oid': value('videoId', pattern: r'^\d+$'),
          'segment_index': '$index'
        });
      case 'youku.video':
        return uri('openapi.youku.com', '/v2/videos/show.json',
            {'client_id': '53e6cc67237fc59a', 'video_id': value('videoId')});
      case 'youku.episodes':
        final page = p['page'];
        if (page is! int || page < 1 || page > 100) {
          throw const Failure(
              FailureCode.invalidInput, 'Invalid catalogue page.');
        }
        return uri('openapi.youku.com', '/v2/shows/videos.json', {
          'client_id': '53e6cc67237fc59a',
          'package': 'com.huawei.hwvplayer.youku',
          'ext': 'show',
          'show_id': value('workId'),
          'page': '$page',
          'count': '100',
          'show_videotype': '正片'
        });
      default:
        throw const Failure(
            FailureCode.invalidInput, 'Unknown request profile.');
    }
  }
}
