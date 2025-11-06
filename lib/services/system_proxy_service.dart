import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 提供系统代理的解析结果，并用于 HttpClient.findProxy。
class SystemProxyService {
  SystemProxyService._();

  static final SystemProxyService instance = SystemProxyService._();

  bool _initialized = false;
  bool _proxyEnabled = false;
  bool _bypassSimpleLocal = false;
  final Map<String, String> _schemeProxy = {};
  String? _defaultProxy;
  final List<_BypassRule> _bypassRules = [];

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (kIsWeb) {
      return;
    }

    try {
      final envConfig = _loadFromEnvironment();
      if (envConfig != null) {
        _applyConfig(envConfig);
        return;
      }

      if (Platform.isWindows) {
        await _loadWindowsProxySettings();
      } else {
        // 其他平台暂时依赖环境变量，后续可按需补充。
      }
    } catch (e) {
      debugPrint('SystemProxyService initialize error: $e');
    }
  }

  /// 返回 HttpClient.findProxy 所需的字符串。
  String findProxy(Uri uri) {
    if (!_proxyEnabled || uri.host.isEmpty) {
      return 'DIRECT';
    }

    final host = uri.host;
    if (_shouldBypass(host)) {
      return 'DIRECT';
    }

    final scheme = uri.scheme.toLowerCase();
    final proxy = _schemeProxy[scheme] ?? _defaultProxy;
    if (proxy == null || proxy.isEmpty) {
      return 'DIRECT';
    }

    return 'PROXY $proxy;DIRECT';
  }

  void _applyConfig(_ProxyConfig config) {
    _proxyEnabled = config.enabled;
    _bypassSimpleLocal = config.bypassSimpleLocal;
    _schemeProxy
      ..clear()
      ..addAll(config.schemeProxy);
    _defaultProxy = config.defaultProxy;

    _bypassRules
      ..clear()
      ..addAll(config.bypassPatterns.map(_BypassRule.new));
  }

  _ProxyConfig? _loadFromEnvironment() {
    final env = Platform.environment;
    final httpsRaw = env['https_proxy'] ?? env['HTTPS_PROXY'];
    final httpRaw = env['http_proxy'] ?? env['HTTP_PROXY'];
    final allRaw = env['all_proxy'] ?? env['ALL_PROXY'];

    if ((httpsRaw == null || httpsRaw.isEmpty) &&
        (httpRaw == null || httpRaw.isEmpty) &&
        (allRaw == null || allRaw.isEmpty)) {
      return null;
    }

    final schemeProxy = <String, String>{};
    String? defaultProxy;

    void assign(String? raw, String scheme) {
      if (raw == null || raw.isEmpty) return;
      final normalized = _normalizeProxyUri(raw);
      if (normalized != null && normalized.isNotEmpty) {
        schemeProxy[scheme] = normalized;
      }
    }

    assign(httpRaw, 'http');
    assign(httpsRaw, 'https');

    if (allRaw != null && allRaw.isNotEmpty) {
      defaultProxy = _normalizeProxyUri(allRaw) ?? allRaw;
    } else if (schemeProxy.isNotEmpty) {
      defaultProxy = schemeProxy.values.first;
    }

    final bypassRaw = env['no_proxy'] ?? env['NO_PROXY'];
    final bypass = _parseBypassList(bypassRaw);

    return _ProxyConfig(
      enabled: true,
      defaultProxy: defaultProxy,
      schemeProxy: schemeProxy,
      bypassPatterns: bypass,
      bypassSimpleLocal: bypass.contains('<local>'),
    );
  }

  Future<void> _loadWindowsProxySettings() async {
    try {
      final result = await Process.run(
        'reg',
        [
          'query',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        ],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        debugPrint(
            'SystemProxyService: failed to query registry, code=${result.exitCode}');
        return;
      }

      final output = (result.stdout as String?) ?? '';
      final lines = output.split(RegExp(r'\r?\n'));

      int? proxyEnable;
      String? proxyServer;
      String? proxyOverride;

      final enableReg = RegExp(r'^ProxyEnable\s+REG_DWORD\s+0x([0-9a-fA-F]+)$');
      final serverReg = RegExp(r'^ProxyServer\s+REG_SZ\s+(.+)$');
      final overrideReg = RegExp(r'^ProxyOverride\s+REG_SZ\s+(.+)$');

      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        final enableMatch = enableReg.firstMatch(line);
        if (enableMatch != null) {
          proxyEnable = int.tryParse(enableMatch.group(1) ?? '', radix: 16);
          continue;
        }

        final serverMatch = serverReg.firstMatch(line);
        if (serverMatch != null) {
          proxyServer = serverMatch.group(1)?.trim();
          continue;
        }

        final overrideMatch = overrideReg.firstMatch(line);
        if (overrideMatch != null) {
          proxyOverride = overrideMatch.group(1)?.trim();
        }
      }

      if (proxyEnable != 1 || proxyServer == null || proxyServer.isEmpty) {
        _proxyEnabled = false;
        return;
      }

      final config = _parseWindowsProxyServer(proxyServer, proxyOverride);
      if (config != null) {
        _applyConfig(config);
      }
    } catch (e) {
      debugPrint('SystemProxyService: error loading windows proxy: $e');
    }
  }

  _ProxyConfig? _parseWindowsProxyServer(String raw, String? bypassRaw) {
    final schemeProxy = <String, String>{};
    String? defaultProxy;

    for (final entry in raw.split(';')) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split('=');
      if (parts.length == 2) {
        final scheme = parts[0].toLowerCase();
        final value = _normalizeProxyUri(parts[1].trim());
        if (value != null && value.isNotEmpty) {
          schemeProxy[scheme] = value;
        }
      } else {
        final value = _normalizeProxyUri(trimmed);
        if (value != null && value.isNotEmpty) {
          defaultProxy ??= value;
        }
      }
    }

    if (schemeProxy.isEmpty && (defaultProxy == null || defaultProxy.isEmpty)) {
      return null;
    }

    final bypass = _parseBypassList(bypassRaw);

    return _ProxyConfig(
      enabled: true,
      defaultProxy: defaultProxy,
      schemeProxy: schemeProxy,
      bypassPatterns: bypass,
      bypassSimpleLocal: bypass.contains('<local>'),
    );
  }

  bool _shouldBypass(String host) {
    if (!_proxyEnabled) {
      return true;
    }

    if (_bypassSimpleLocal && !_containsDot(host) && !_isIpAddress(host)) {
      return true;
    }

    for (final rule in _bypassRules) {
      if (rule.matches(host)) {
        return true;
      }
    }
    return false;
  }

  static List<String> _parseBypassList(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    return raw
        .split(';')
        .map((e) => e.trim())
        .where((element) => element.isNotEmpty)
        .toList(growable: false);
  }

  static String? _normalizeProxyUri(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return trimmed;
    }

    if ((uri.scheme.isEmpty || uri.scheme == 'http') &&
        uri.host.isEmpty &&
        uri.path.isNotEmpty) {
      // 处理形如 127.0.0.1:7890 的情况
      return trimmed;
    }

    if (uri.host.isNotEmpty && uri.port != 0) {
      return '${uri.host}:${uri.port}';
    }
    if (uri.hasAuthority && uri.port == 0) {
      return '${uri.host}:80';
    }

    if (uri.scheme.isEmpty && uri.host.isEmpty && uri.path.isNotEmpty) {
      return uri.path;
    }

    return trimmed;
  }

  static bool _containsDot(String host) => host.contains('.');

  static bool _isIpAddress(String host) =>
      InternetAddress.tryParse(host) != null;
}

class _ProxyConfig {
  _ProxyConfig({
    required this.enabled,
    required this.defaultProxy,
    required this.schemeProxy,
    required this.bypassPatterns,
    required this.bypassSimpleLocal,
  });

  final bool enabled;
  final String? defaultProxy;
  final Map<String, String> schemeProxy;
  final List<String> bypassPatterns;
  final bool bypassSimpleLocal;
}

class _BypassRule {
  _BypassRule(String pattern)
      : _isLocalKeyword = pattern == '<local>',
        _regex = pattern == '<local>'
            ? null
            : RegExp(
                '^${RegExp.escape(pattern).replaceAll(r'\*', '.*')}\$',
                caseSensitive: false,
              );

  final bool _isLocalKeyword;
  final RegExp? _regex;

  bool matches(String host) {
    if (_isLocalKeyword) {
      return !_containsDot(host) && InternetAddress.tryParse(host) == null;
    }
    if (_regex == null) {
      return false;
    }
    return _regex!.hasMatch(host);
  }

  static bool _containsDot(String host) => host.contains('.');
}
