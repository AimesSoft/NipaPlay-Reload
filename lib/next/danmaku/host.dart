import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import '../network/dandanplay_gateway.dart';
import '../network/http_diagnostics.dart';
import 'source.dart';

/// Mint one of these per registered source execution identity. A plugin cannot
/// choose another source's profile or inspect the underlying credential client.
final class ScopedDanmakuHost implements DanmakuHost {
  const ScopedDanmakuHost(this._host, this._declaration);
  final DanmakuHost _host;
  final DanmakuDescriptor _declaration;
  @override
  Future<List<int>> request(
      String profile, JsonMap parameters, DanmakuCancellation cancel) async {
    if (!_declaration.profiles.contains(profile) ||
        profile.split('.').first != _declaration.id ||
        _declaration.version != '1') {
      throw const Failure(FailureCode.unavailable,
          'Request profile is outside this source grant.');
    }
    return await _host.request(profile, parameters, cancel);
  }
}

final class HttpDanmakuHost implements DanmakuHost {
  HttpDanmakuHost(
      {required this.dandanplay,
      this.interval = const Duration(milliseconds: 300),
      this.timeout = const Duration(seconds: 20)});
  final DandanplayGateway dandanplay;
  final Duration interval;
  final Duration timeout;
  final Map<String, Future<void>> _tails = {};
  final Map<String, DateTime> _next = {};
  @override
  Future<List<int>> request(
      String profile, JsonMap parameters, DanmakuCancellation cancel) async {
    final source = profile.split('.').first;
    final requestCancellation = DanmakuCancellation();
    final previous = _tails[source] ?? Future<void>.value();
    final done = Completer<void>();
    _tails[source] = previous.then((_) => done.future);
    await Future.any([previous, cancel.stopped]);
    Uri? target;
    int? statusCode;
    String? contentType;
    SourceFailure failure(SourceStatus status, {DateTime? retryAt, String? reasonCode}) =>
        SourceFailure(status,
            retryAt: retryAt,
            diagnostics: '${httpDiagnostics(target,
                statusCode: statusCode, contentType: contentType)}'
                '${reasonCode == null ? "" : "; reason=$reasonCode"}');
    try {
      cancel.check();
      final wait = (_next[source] ?? DateTime.now()).difference(DateTime.now());
      if (wait > Duration.zero) {
        await Future.any([Future<void>.delayed(wait), cancel.stopped]);
      }
      cancel.check();
      final endpoint = _uri(profile, parameters);
      final uri = await dandanplay.resolve(endpoint);
      target = uri;
      final client = dandanplay.client;
      cancel.stopped.then((_) => requestCancellation.cancel());
      final request = http.AbortableRequest('GET', uri,
          abortTrigger: requestCancellation.stopped)
        // Comment pools redirect to Dandanplay's CAS CDN. Delegate this to
        // the Classic client's redirect handling, as Classic playback does.
        ..followRedirects = profile == 'dandanplay.comments'
        ..headers['Accept'] = 'application/json';
      cancel.check();
      final bytes = await (() async {
        final response = await client.send(request);
        statusCode = response.statusCode;
        contentType = response.headers['content-type'];
        if (response.statusCode == 401) {
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
        return bytes;
      })()
          .timeout(timeout, onTimeout: () {
        requestCancellation.cancel();
        throw failure(SourceStatus.transportFailed, reasonCode: 'timeout');
      });
      cancel.check();
      return bytes;
    } on DandanplayLoginRequired {
      throw failure(SourceStatus.authenticationRequired);
    } on http.RequestAbortedException {
      cancel.check();
      throw failure(SourceStatus.transportFailed, reasonCode: 'request_aborted');
    } on http.ClientException catch (error) {
      throw failure(SourceStatus.transportFailed, reasonCode: error is SocketException
          ? 'socket_${(error as SocketException).osError?.errorCode ?? "unavailable"}' : 'http_client');
    } on SocketException {
      throw failure(SourceStatus.transportFailed, reasonCode: 'network_unavailable');
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

    switch (profile) {
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
      default:
        throw const Failure(
            FailureCode.invalidInput, 'Unknown request profile.');
    }
  }
}
