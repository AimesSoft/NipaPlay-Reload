import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import '../danmaku/host.dart';
import '../danmaku/source.dart';
import 'platform_session.dart';

final class VaultYoukuSessionBridge implements YoukuSessionBridge {
  VaultYoukuSessionBridge(this.sessions, this.client,
      {this.timeout = const Duration(seconds: 20), String Function()? guid})
      : guid = guid ?? _guid;
  final PlatformSessions sessions;
  final http.Client client;
  final Duration timeout;
  final String Function() guid;
  static const _appKey = '24679788';
  static const _salt = 'MkmC9SoIw6xCkSKHhJ7b5D2r51kBiREr';
  static final _endpoint =
      Uri.https('acs.youku.com', '/h5/mopen.youku.danmu.list/1.0/');
  static String _guid() {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(22, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  @override
  bool get available => sessions.available('youku');

  @override
  Future<List<int>> minute(String videoId, int minute, DanmakuAccess access,
      DanmakuCancellation cancel) async {
    if (!RegExp(r'^[A-Za-z0-9=]+$').hasMatch(videoId) ||
        minute < 0 ||
        minute >= 120) {
      throw const Failure(
          FailureCode.invalidInput, 'Invalid Youku minute parameters.');
    }
    sessions.authorize('youku', 'youku.minute', access.credentialRef);
    final generation = sessions.generation('youku')!;
    // MTOP's normal token handshake may return a fresh signing cookie once.
    for (var attempt = 0; attempt < 2; attempt++) {
      cancel.check();
      final timestamp = sessions.now().millisecondsSinceEpoch;
      final body = <String, Object?>{
        'ctime': timestamp,
        'ctype': 10004,
        'cver': 'v1.0',
        'guid': guid(),
        'mat': minute,
        'mcount': 1,
        'pid': 0,
        'sver': '3.1.0',
        'type': 1,
        'vid': videoId,
      };
      final encoded = base64Encode(utf8.encode(jsonEncode(body)));
      body['msg'] = encoded;
      body['sign'] = md5.convert(utf8.encode('$encoded$_salt')).toString();
      final data = jsonEncode(body);
      final token = (sessions.cookieValue('youku', '_m_h5_tk', _endpoint) ?? '')
          .split('_')
          .first;
      SecretRedactor.remember(PlatformSessions.reference('youku'), token);
      final sign = md5
          .convert(utf8.encode('$token&$timestamp&$_appKey&$data'))
          .toString();
      SecretRedactor.remember(PlatformSessions.reference('youku'), sign);
      final uri = _endpoint.replace(queryParameters: {
        'jsv': '2.6.1',
        'appKey': _appKey,
        't': '$timestamp',
        'sign': sign,
        'api': 'mopen.youku.danmu.list',
        'v': '1.0',
        'type': 'originaljson',
        'dataType': 'json',
        'timeout': '20000',
      });
      final cancellation = DanmakuCancellation();
      cancel.stopped.then((_) => cancellation.cancel());
      final request =
          http.AbortableRequest('POST', uri, abortTrigger: cancellation.stopped)
            ..followRedirects = false
            ..headers.addAll({
              'Cookie': sessions.cookieHeader('youku', uri),
              'User-Agent': 'Mozilla/5.0 NipaPlay',
              'Referer': 'https://v.youku.com/',
              'Content-Type': 'application/x-www-form-urlencoded',
            })
            ..bodyFields = {'data': data};
      try {
        final response =
            await client.send(request).timeout(timeout, onTimeout: () {
          cancellation.cancel();
          throw const SourceFailure(SourceStatus.transportFailed);
        });
        final bytes = await (() async {
          if (response.statusCode == 401) {
            sessions.rejected('youku', generation: generation);
            throw SourceFailure(SourceStatus.authenticationRequired,
                diagnostics: sessions.status('youku')['loginHint'] as String);
          }
          if (response.statusCode == 403 ||
              response.isRedirect ||
              response.statusCode >= 300 && response.statusCode < 400) {
            throw const SourceFailure(SourceStatus.accessDenied);
          }
          if (response.statusCode == 429) {
            throw const SourceFailure(SourceStatus.rateLimited);
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
          cancellation.cancel();
          throw const SourceFailure(SourceStatus.transportFailed);
        });
        cancel.check();
        if (sessions.generation('youku') != generation || !available) {
          throw SourceFailure(SourceStatus.authenticationRequired,
              diagnostics: sessions.status('youku')['loginHint'] as String);
        }
        final root = jsonDecode(utf8.decode(bytes)) as Map;
        final ret = (root['ret'] as List).cast<String>();
        final updates = responseCookies(
            response.headers['set-cookie'], _endpoint,
            now: sessions.now());
        if (updates.isNotEmpty) {
          await sessions.update('youku', generation, updates);
        }
        if (ret.any((r) => r.startsWith('SUCCESS::'))) {
          final nested =
              jsonDecode((root['data'] as Map)['result'] as String) as Map;
          final rows = (nested['data'] as Map)['result'] as List;
          // Project the public comment response; never return account/session fields.
          final safeRows = [
            for (final raw in rows)
              {
                for (final key in [
                  'id',
                  'playat',
                  'content',
                  'propertis',
                  'createtime'
                ])
                  if ((raw as Map).containsKey(key))
                    key: key == 'propertis'
                        ? _properties(raw[key])
                        : safeSessionResponse(raw[key]),
              }
          ];
          return utf8.encode(jsonEncode({
            'ret': ['SUCCESS::OK'],
            'data': {
              'result': jsonEncode({
                'data': {'result': safeRows}
              })
            },
          }));
        }
        final tokenFailure = ret.any((r) => r.contains('TOKEN'));
        if (tokenFailure &&
            attempt == 0 &&
            updates.any((c) => c.name == '_m_h5_tk')) {
          continue;
        }
        if (tokenFailure ||
            ret.any((r) => r.contains('SESSION') || r.contains('LOGIN'))) {
          sessions.rejected('youku', generation: generation);
          throw SourceFailure(SourceStatus.authenticationRequired,
              diagnostics: sessions.status('youku')['loginHint'] as String);
        }
        if (ret.any((r) => r.contains('LIMIT'))) {
          throw const SourceFailure(SourceStatus.rateLimited);
        }
        throw const SourceFailure(SourceStatus.accessDenied);
      } on FormatException {
        throw const SourceFailure(SourceStatus.schemaChanged);
      } on TypeError {
        throw const SourceFailure(SourceStatus.schemaChanged);
      } on http.RequestAbortedException {
        cancel.check();
        throw const SourceFailure(SourceStatus.transportFailed);
      } on http.ClientException {
        throw const SourceFailure(SourceStatus.transportFailed);
      } on SocketException {
        throw const SourceFailure(SourceStatus.transportFailed);
      } finally {
        cancellation.cancel();
      }
    }
    throw SourceFailure(SourceStatus.authenticationRequired,
        diagnostics: sessions.status('youku')['loginHint'] as String);
  }
}

Object? _properties(Object? value) {
  if (value == null) return null;
  final properties = value is String ? jsonDecode(value) as Map : value as Map;
  return jsonEncode({
    for (final key in ['pos', 'size', 'color'])
      if (properties.containsKey(key))
        key: safeSessionResponse(properties[key]),
  });
}

Object? safeSessionResponse(Object? value) {
  if (value is String) return SecretRedactor.text(value);
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (!RegExp(
                r'cookie|token|secret|session|authorization|csrf|bili_jct|sessdata|p_sck|p_ck|yktk|_m_h5',
                caseSensitive: false)
            .hasMatch(entry.key.toString()))
          entry.key: safeSessionResponse(entry.value),
    };
  }
  if (value is List) {
    return value.map(safeSessionResponse).toList();
  }
  return value;
}

/// Set-Cookie attributes are parsed inside the host, never in a source.
List<SessionCookie> responseCookies(String? header, Uri uri, {DateTime? now}) {
  if (header == null) return [];
  final cookies = <SessionCookie>[];
  for (final item in header.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
    final cookie = Cookie.fromSetCookieValue(item);
    final declaredDomain = cookie.domain;
    final domain = declaredDomain == null
        ? uri.host
        : '.${declaredDomain.startsWith('.') ? declaredDomain.substring(1) : declaredDomain}';
    final host = domain.startsWith('.') ? domain.substring(1) : domain;
    if (host != uri.host &&
        !(domain.startsWith('.') && uri.host.endsWith('.$host'))) {
      continue;
    }
    cookies.add(SessionCookie(cookie.name, cookie.value, domain,
        path: cookie.path ??
            (uri.path.lastIndexOf('/') <= 0
                ? '/'
                : uri.path.substring(0, uri.path.lastIndexOf('/'))),
        secure: cookie.secure,
        expiresAt: cookie.maxAge == null
            ? cookie.expires
            : (now ?? DateTime.now()).add(Duration(seconds: cookie.maxAge!))));
  }
  return cookies;
}
