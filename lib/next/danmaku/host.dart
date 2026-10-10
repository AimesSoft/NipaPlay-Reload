import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import '../network/dandanplay_gateway.dart';
import '../network/http_diagnostics.dart';
import 'source.dart';
import '../sessions/platform_session.dart';
import '../sessions/youku_bridge.dart';

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
    if (!_declaration.profiles.contains(profile) ||
        profile.split('.').first != _declaration.id ||
        _declaration.version != '1') {
      throw const Failure(FailureCode.unavailable,
          'Request profile is outside this source grant.');
    }
    return await _host.request(profile, parameters, access, cancel);
  }
}

final class HttpDanmakuHost implements DanmakuHost {
  HttpDanmakuHost(
      {required this.publicClient,
      required this.dandanplay,
      this.youkuSession,
      this.sessions,
      this.interval = const Duration(milliseconds: 300),
      this.timeout = const Duration(seconds: 20)});
  final http.Client publicClient;
  final DandanplayGateway dandanplay;
  final YoukuSessionBridge? youkuSession;
  final PlatformSessions? sessions;
  final Duration interval;
  final Duration timeout;
  final Map<String, Future<void>> _tails = {};
  final Map<String, DateTime> _next = {};
  String? _wbiKey;
  DateTime? _wbiUntil;
  String _loginHint(String platform) =>
      sessions?.status(platform)['loginHint'] as String? ??
      platformLoginHint(platform);
  @override
  bool sessionAvailable(String sourceId) =>
      sourceId == 'youku' && (youkuSession?.available ?? false) ||
      sourceId == 'bilibili' && (sessions?.available('bilibili') ?? false);
  @override
  Future<List<int>> request(String profile, JsonMap parameters,
      DanmakuAccess? access, DanmakuCancellation cancel) async {
    if (profile.startsWith('bilibili.') && access != null) {
      if (sessions == null) {
        throw SourceFailure(SourceStatus.authenticationRequired,
            diagnostics: _loginHint('bilibili'));
      }
      sessions!.authorize('bilibili', profile, access.credentialRef);
    }
    if (profile == 'bilibili.search' &&
        (_wbiUntil == null || DateTime.now().isAfter(_wbiUntil!))) {
      final bytes = await request('bilibili.wbi', {}, null, cancel);
      try {
        final root = jsonDecode(utf8.decode(bytes)) as Map;
        final images = (root['data'] as Map)['wbi_img'] as Map;
        final keys = [
          for (final field in ['img_url', 'sub_url'])
            Uri.parse(images[field] as String)
                .pathSegments
                .last
                .split('.')
                .first
        ].join();
        const order = [
          46,
          47,
          18,
          2,
          53,
          8,
          23,
          32,
          15,
          50,
          10,
          31,
          58,
          3,
          45,
          35,
          27,
          43,
          5,
          49,
          33,
          9,
          42,
          19,
          29,
          28,
          14,
          39,
          12,
          38,
          41,
          13
        ];
        if (keys.length != 64) throw const FormatException('Invalid WBI keys');
        _wbiKey = [for (final i in order) keys[i]].join();
        _wbiUntil = DateTime.now().add(const Duration(hours: 1));
      } on FormatException {
        throw const SourceFailure(SourceStatus.schemaChanged);
      } on TypeError {
        throw const SourceFailure(SourceStatus.schemaChanged);
      }
    }
    final source = profile.split('.').first;
    final requestCancellation = DanmakuCancellation();
    final previous = _tails[source] ?? Future<void>.value();
    final done = Completer<void>();
    _tails[source] = previous.then((_) => done.future);
    await Future.any([previous, cancel.stopped]);
    Uri? target;
    int? statusCode;
    String? contentType;
    SourceFailure failure(SourceStatus status, {DateTime? retryAt}) => SourceFailure(
        status,
        retryAt: retryAt,
        diagnostics:
            '${httpDiagnostics(target, statusCode: statusCode, contentType: contentType)}'
            '${status == SourceStatus.authenticationRequired ? '; ${_loginHint(source)}' : ''}');
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
          throw SourceFailure(SourceStatus.authenticationRequired,
              diagnostics: _loginHint('youku'));
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
      if (access != null && source != 'bilibili') {
        throw const Failure(FailureCode.invalidInput,
            'Anonymous profiles do not accept session references.');
      }
      final endpoint = _uri(profile, parameters);
      final uri = source == 'dandanplay'
          ? await dandanplay.resolve(endpoint)
          : endpoint;
      target = uri;
      final client = source == 'dandanplay' ? dandanplay.client : publicClient;
      cancel.stopped.then((_) => requestCancellation.cancel());
      final request = http.AbortableRequest('GET', uri,
          abortTrigger: requestCancellation.stopped)
        ..followRedirects = false
        ..headers['Accept'] = profile == 'bilibili.segment'
            ? 'application/octet-stream'
            : 'application/json';
      if (source == 'bilibili') {
        request.headers['User-Agent'] = 'Mozilla/5.0 NipaPlay';
        request.headers['Referer'] = 'https://www.bilibili.com/';
        if (access != null || (sessions?.available('bilibili') ?? false)) {
          if (sessions == null) {
            throw SourceFailure(SourceStatus.authenticationRequired,
                diagnostics: _loginHint('bilibili'));
          }
          sessions!.authorize('bilibili', profile, access?.credentialRef);
          request.headers['Cookie'] = sessions!.cookieHeader('bilibili', uri);
        }
      }
      final sessionGeneration = sessions?.generation('bilibili');
      cancel.check();
      final bytes = await (() async {
        final response = await client.send(request);
        statusCode = response.statusCode;
        contentType = response.headers['content-type'];
        if (response.statusCode == 401) {
          if (source == 'bilibili' && request.headers.containsKey('Cookie')) {
            sessions!.rejected('bilibili', generation: sessionGeneration);
          }
          throw failure(SourceStatus.authenticationRequired);
        }
        if (response.statusCode == 403 ||
            response.statusCode >= 300 && response.statusCode < 400) {
          throw failure(SourceStatus.accessDenied);
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
              throw failure(SourceStatus.schemaChanged);
            }
          }
          throw failure(SourceStatus.rateLimited,
              retryAt: DateTime.now()
                  .toUtc()
                  .add(Duration(seconds: seconds.clamp(1, 3600))));
        }
        if (response.statusCode != 200) {
          throw failure(SourceStatus.transportFailed);
        }
        if ((response.contentLength ?? 0) > 8388608) {
          throw failure(SourceStatus.schemaChanged);
        }
        final bytes = <int>[];
        await for (final part in response.stream) {
          cancel.check();
          if (bytes.length + part.length > 8388608) {
            throw failure(SourceStatus.schemaChanged);
          }
          bytes.addAll(part);
        }
        if (source == 'bilibili' && request.headers.containsKey('Cookie')) {
          if (sessions!.generation('bilibili') != sessionGeneration ||
              !sessions!.available('bilibili')) {
            throw SourceFailure(SourceStatus.authenticationRequired,
                diagnostics: _loginHint('bilibili'));
          }
          final cookies = responseCookies(response.headers['set-cookie'], uri,
              now: sessions!.now());
          if (cookies.isNotEmpty) {
            await sessions!.update('bilibili', sessionGeneration!, cookies);
          }
        }
        if (source == 'bilibili' && profile != 'bilibili.segment') {
          try {
            final root = jsonDecode(utf8.decode(bytes)) as Map;
            if (root['code'] == -101 && profile != 'bilibili.wbi') {
              if (request.headers.containsKey('Cookie')) {
                sessions!.rejected('bilibili', generation: sessionGeneration);
              }
              throw SourceFailure(SourceStatus.authenticationRequired,
                  diagnostics: _loginHint('bilibili'));
            }
            return utf8.encode(jsonEncode(safeSessionResponse(root)));
          } on FormatException {
            throw failure(SourceStatus.schemaChanged);
          } on TypeError {
            throw failure(SourceStatus.schemaChanged);
          }
        }
        return bytes;
      })()
          .timeout(timeout, onTimeout: () {
        requestCancellation.cancel();
        throw failure(SourceStatus.transportFailed);
      });
      cancel.check();
      return bytes;
    } on DandanplayLoginRequired {
      throw failure(SourceStatus.authenticationRequired);
    } on http.RequestAbortedException {
      cancel.check();
      throw failure(SourceStatus.transportFailed);
    } on http.ClientException {
      throw failure(SourceStatus.transportFailed);
    } on SocketException {
      throw failure(SourceStatus.transportFailed);
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
      'bilibili.wbi' => <String>{},
      'bilibili.search' => {'query'},
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
      case 'bilibili.wbi':
        return uri('api.bilibili.com', '/x/web-interface/nav', {});
      case 'bilibili.search':
        final query = p['query'];
        if (query is! String || query.trim().isEmpty || query.length > 200) {
          throw const Failure(
              FailureCode.invalidInput, 'Invalid search query.');
        }
        final params = <String, String>{
          'keyword': query.replaceAll(RegExp(r"[!'()*]"), ''),
          'page': '1',
          'search_type': 'video',
          'wts': '${DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000}'
        };
        final keys = params.keys.toList()..sort();
        String encode(String v) => Uri.encodeComponent(v)
            .replaceAll("'", '%27')
            .replaceAll('!', '%21')
            .replaceAll('(', '%28')
            .replaceAll(')', '%29')
            .replaceAll('*', '%2A');
        final signed = keys
            .map((key) => '${encode(key)}=${encode(params[key]!)}')
            .join('&');
        params['w_rid'] =
            md5.convert(utf8.encode('$signed$_wbiKey')).toString();
        return uri(
            'api.bilibili.com', '/x/web-interface/wbi/search/type', params);
      case 'dandanplay.search':
        if (p['query'] is! String ||
            (p['query'] as String).isEmpty ||
            (p['query'] as String).length > 200) {
          throw const Failure(
              FailureCode.invalidInput, 'Invalid search query.');
        }
        return Uri(
            path: '/api/v2/search/episodes',
            queryParameters: {'anime': p['query'] as String});
      case 'dandanplay.episodes':
        return Uri(
            path: '/api/v2/bangumi/${value('workId', pattern: r'^\d+$')}');
      case 'dandanplay.comments':
        return Uri(
            path: '/api/v2/comment/${value('videoId', pattern: r'^\d+$')}',
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
