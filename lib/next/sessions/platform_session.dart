import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import '../danmaku/source.dart' show platformSessionLoginHint;

String platformLoginHint(String platform, {String state = 'unavailable'}) =>
    platformSessionLoginHint(platform, state: state);
const sessionPlatforms = ['youku', 'bilibili'];
const _sessionCookieNames = {
  'youku': {'P_sck', 'P_ck', 'yktk', '_m_h5_tk', '_m_h5_tk_enc', 'cna'},
  'bilibili': {
    'SESSDATA',
    'bili_jct',
    'DedeUserID',
    'DedeUserID__ckMd5',
    'buvid3',
    'buvid4',
    'sid',
    'bili_ticket'
  },
};
const _secretCookieNames = {
  'P_sck',
  'P_ck',
  'yktk',
  '_m_h5_tk',
  '_m_h5_tk_enc',
  'SESSDATA',
  'bili_jct',
  'DedeUserID__ckMd5',
  'bili_ticket'
};

/// Only the application-owned WebView may supply secrets to this port.
abstract interface class PlatformLoginPort {
  bool get supported;
  Future<void> open(String platform, String generation);
  Future<void> close(String platform);
}

final class MacOSPlatformLogin implements PlatformLoginPort {
  static const _channel = MethodChannel('nipaplay/platform_login');
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  void bind(PlatformSessions sessions) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'capture') throw MissingPluginException();
      final data = Map<String, Object?>.from(call.arguments as Map);
      try {
        await sessions
            .capture(data['platform'] as String, data['generation'] as String, [
          for (final cookie in data['cookies'] as List)
            SessionCookie.fromJson(Map<String, Object?>.from(cookie as Map))
        ]);
        return {'saved': true};
      } on Failure catch (failure) {
        throw PlatformException(
            code: failure.code.name, message: failure.message);
      } on FormatException {
        throw PlatformException(code: 'invalid_session', message: '会话格式无效。');
      } on TypeError {
        throw PlatformException(code: 'invalid_session', message: '会话格式无效。');
      }
    });
  }

  void unbind() {
    if (supported) _channel.setMethodCallHandler(null);
  }

  @override
  Future<void> open(String platform, String generation) async =>
      _channel.invokeMethod<void>('open', {
        'platform': platform,
        'generation': generation,
      });
  @override
  Future<void> close(String platform) async =>
      _channel.invokeMethod<void>('close', {'platform': platform});
}

/// Host-only cookie model; never exported through a Capability or source port.
final class SessionCookie {
  const SessionCookie(this.name, this.value, this.domain,
      {this.path = '/', this.expiresAt, this.secure = true});
  final String name, value, domain, path;
  final DateTime? expiresAt;
  final bool secure;
  factory SessionCookie.fromJson(JsonMap json) => SessionCookie(
        json['name'] as String,
        json['value'] as String,
        json['domain'] as String,
        path: json['path'] as String,
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int,
                isUtc: true),
        secure: json['secure'] as bool,
      );
  JsonMap toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'expiresAt': expiresAt?.millisecondsSinceEpoch,
        'secure': secure,
      };
  bool validAt(DateTime now) =>
      value.isNotEmpty && (expiresAt == null || expiresAt!.isAfter(now));
  bool matches(Uri uri, DateTime now) {
    final host = domain.startsWith('.') ? domain.substring(1) : domain;
    final domainMatches = uri.host == host ||
        domain.startsWith('.') && uri.host.endsWith('.$host');
    return domainMatches &&
        (!secure || uri.scheme == 'https') &&
        (uri.path == path ||
            uri.path.startsWith(path.endsWith('/') ? path : '$path/')) &&
        validAt(now);
  }
}

final class PlatformSessions extends ChangeNotifier {
  PlatformSessions(this.vault, this.login, {DateTime Function()? now})
      : now = now ?? DateTime.now;
  final CredentialVault vault;
  final PlatformLoginPort login;
  final DateTime Function() now;
  final Map<String, List<SessionCookie>> _cookies = {};
  final Map<String, String> _generation = {};
  final Map<String, String> _loginGeneration = {};
  final Map<String, String> _errors = {};
  final Set<String> _rejected = {};
  Future<void> _tail = Future.value();
  static CredentialRef reference(String platform) =>
      CredentialRef('next.platform-session', '$platform.v1');
  static String accessReference(String platform) =>
      jsonEncode(reference(platform).toJson());

  void _platform(String platform) {
    if (!sessionPlatforms.contains(platform)) {
      throw const Failure(FailureCode.invalidInput, '不支持的平台。');
    }
  }

  Future<T> _serialize<T>(Future<T> Function() work) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await work();
    } finally {
      done.complete();
    }
  }

  Future<void> restore() async {
    if (!login.supported) return;
    for (final platform in sessionPlatforms) {
      try {
        final raw = await _read(platform);
        if (raw == null) continue;
        final record = jsonDecode(raw) as Map;
        final cookies = _validated(platform, [
          for (final item in record['cookies'] as List)
            SessionCookie.fromJson(Map<String, Object?>.from(item as Map))
        ]);
        final generation = record['generation'] as String;
        _cookies[platform] = cookies;
        _generation[platform] = generation;
      } on Failure catch (failure) {
        _errors[platform] = failure.message;
      } on FormatException {
        _errors[platform] = '$platform 已保存的登录态格式无效。';
      } on TypeError {
        _errors[platform] = '$platform 已保存的登录态格式无效。';
      }
    }
  }

  Future<String?> _read(String platform) async {
    try {
      return await vault.read(reference(platform));
    } catch (_) {
      throw const Failure(FailureCode.unavailable, '凭据保险库读取失败。');
    }
  }

  List<SessionCookie> _validated(String platform, List<SessionCookie> cookies) {
    if (cookies.length > 256) {
      throw const Failure(FailureCode.invalidInput, '平台会话过大。');
    }
    final root = platform == 'youku' ? 'youku.com' : 'bilibili.com';
    final result = <SessionCookie>[];
    for (final cookie in cookies) {
      final domain = cookie.domain.startsWith('.')
          ? cookie.domain.substring(1)
          : cookie.domain;
      if (domain != root && !domain.endsWith('.$root')) continue;
      if (!_sessionCookieNames[platform]!.contains(cookie.name)) continue;
      if (!RegExp(r'^[!#$%&\x27*+.^_`|~0-9A-Za-z-]+$').hasMatch(cookie.name) ||
          cookie.value.length > 16384 ||
          !RegExp(r'^[\x21\x23-\x2b\x2d-\x3a\x3c-\x5b\x5d-\x7e]*$')
              .hasMatch(cookie.value) ||
          !cookie.path.startsWith('/')) {
        throw const Failure(FailureCode.invalidInput, '平台会话属性无效。');
      }
      if (_secretCookieNames.contains(cookie.name)) {
        SecretRedactor.remember(reference(platform), cookie.value);
      }
      result.add(cookie);
    }
    return result;
  }

  bool available(String platform) =>
      login.supported && !_rejected.contains(platform) && _hasLogin(platform);
  bool _hasLogin(String platform, [List<SessionCookie>? cookies]) {
    final authNames = platform == 'youku' ? ['P_sck', 'yktk'] : ['SESSDATA'];
    final target = Uri.https(
        platform == 'youku' ? 'acs.youku.com' : 'api.bilibili.com', '/');
    return (cookies ?? _cookies[platform] ?? [])
        .any((c) => authNames.contains(c.name) && c.matches(target, now()));
  }

  JsonMap status(String platform) {
    _platform(platform);
    final present = _cookies.containsKey(platform);
    final state = !login.supported
        ? 'unsupported'
        : _errors.containsKey(platform)
            ? 'unavailable'
            : available(platform)
                ? 'sessionPresent'
                : present
                    ? 'expiredOrRejected'
                    : 'loggedOut';
    return {
      'platform': platform,
      'supported': login.supported,
      'status': state,
      'sessionAvailable': available(platform),
      'credentialRef': reference(platform).toJson(),
      'accessRef': available(platform) ? accessReference(platform) : null,
      'loginHint': platformLoginHint(platform, state: state),
      'verification': 'localCookiesOnly',
      'notice': _errors[platform],
    };
  }

  Future<void> openLogin(String platform) => _serialize(() async {
        _platform(platform);
        if (!login.supported) {
          throw const Failure(FailureCode.unavailable, '平台登录仅支持 macOS。');
        }
        final generation =
            List.generate(24, (_) => Random.secure().nextInt(256))
                .map((n) => n.toRadixString(16).padLeft(2, '0'))
                .join();
        await login.close(platform);
        _loginGeneration[platform] = generation;
        await login.open(platform, generation);
      });

  Future<void> capture(
          String platform, String generation, List<SessionCookie> cookies) =>
      _serialize(() async {
        _platform(platform);
        if (!login.supported || _loginGeneration[platform] != generation) {
          throw const Failure(FailureCode.conflict, '登录窗口已失效，请重新打开。');
        }
        final accepted = _validated(platform, cookies);
        if (!_hasLogin(platform, accepted)) {
          throw Failure(FailureCode.unavailable,
              'authenticationRequired: ${platformLoginHint(platform, state: 'loginNotCaptured')}');
        }
        await _save(platform, accepted, generation);
        _errors.remove(platform);
        _rejected.remove(platform);
        notifyListeners();
      });

  Future<void> _save(
      String platform, List<SessionCookie> cookies, String generation) async {
    final raw = jsonEncode({
      'generation': generation,
      'cookies': cookies.map((c) => c.toJson()).toList(),
    });
    SecretRedactor.remember(reference(platform), raw);
    try {
      await vault.write(reference(platform), raw);
      if (await vault.read(reference(platform)) != raw) {
        throw StateError('session_vault_readback_mismatch');
      }
    } catch (_) {
      throw const Failure(FailureCode.unavailable, '凭据保险库存储或回读失败，会话保存未确认，请重试。');
    }
    _cookies[platform] = cookies;
    _generation[platform] = generation;
  }

  Future<void> logout(String platform) => _serialize(() async {
        _platform(platform);
        _generation.remove(platform);
        _loginGeneration.remove(platform);
        _cookies.remove(platform);
        _rejected.remove(platform);
        _errors.remove(platform);
        notifyListeners();
        if (login.supported) await login.close(platform);
        try {
          await vault.delete(reference(platform));
          if (await vault.read(reference(platform)) != null) {
            throw StateError('session_vault_delete_mismatch');
          }
        } catch (_) {
          _errors[platform] = '保险库注销失败，请重试。当前进程已停止使用会话。';
          notifyListeners();
          throw const Failure(
              FailureCode.unavailable, '保险库注销失败，请重试。当前进程已停止使用会话。');
        }
      });

  Future<void> close() => _serialize(() async {
        _loginGeneration.clear();
        if (login.supported) {
          for (final platform in sessionPlatforms) {
            await login.close(platform);
          }
        }
        if (login case final MacOSPlatformLogin macOS) macOS.unbind();
      });

  /// Resolve only an exact host-issued reference for the built-in v1 source.
  void authorize(String platform, String profile, String? accessRef) {
    _platform(platform);
    final profiles = platform == 'youku'
        ? ['youku.minute']
        : [
            'bilibili.view',
            'bilibili.season',
            'bilibili.segment',
            'bilibili.search',
            'bilibili.wbi'
          ];
    if (!profiles.contains(profile) ||
        accessRef != null && accessRef != accessReference(platform)) {
      throw const Failure(
          FailureCode.invalidInput, '会话引用与来源 v1 / 请求 profile 不匹配。');
    }
    if (!available(platform)) {
      throw Failure(FailureCode.unavailable,
          'authenticationRequired: ${status(platform)['loginHint']}');
    }
  }

  String? generation(String platform) => _generation[platform];
  String cookieHeader(String platform, Uri uri) {
    final cookies = (_cookies[platform] ?? [])
        .where((c) => c.matches(uri, now()))
        .toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  String? cookieValue(String platform, String name, Uri uri) {
    final cookies = (_cookies[platform] ?? [])
        .where((c) => c.name == name && c.matches(uri, now()))
        .toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    return cookies.firstOrNull?.value;
  }

  void rejected(String platform, {String? generation}) {
    if (generation != null && _generation[platform] != generation) return;
    _rejected.add(platform);
    notifyListeners();
  }

  Future<void> update(
          String platform, String generation, List<SessionCookie> cookies) =>
      _serialize(() async {
        if (_generation[platform] != generation || !available(platform)) {
          throw Failure(FailureCode.unavailable,
              'authenticationRequired: ${status(platform)['loginHint']}');
        }
        final merged = [..._cookies[platform]!];
        for (final cookie in _validated(platform, cookies)) {
          merged.removeWhere((c) =>
              c.name == cookie.name &&
              c.domain == cookie.domain &&
              c.path == cookie.path);
          if (cookie.validAt(now())) merged.add(cookie);
        }
        await _save(platform, merged, generation);
        notifyListeners();
      });
}
