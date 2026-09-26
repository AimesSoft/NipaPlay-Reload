import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nipaplay/plugins/js_runtime_types.dart';

class PluginResolutionCancelled implements Exception {
  const PluginResolutionCancelled();
}

class PluginUrlChoice {
  PluginUrlChoice(Map<String, dynamic> json)
      : id = _requiredText(json, 'id'),
        title = _requiredText(json, 'title');

  final String id;
  final String title;
}

class PluginResolvedUrl {
  PluginResolvedUrl(Map<String, dynamic> json, {required this.isActive})
      : url = checkedHttpUri(json['url']).toString(),
        sourceUrl = checkedHttpUri(json['sourceUrl']).toString(),
        title = _requiredText(json, 'title'),
        searchTitle = json['searchTitle'] as String?,
        headers = checkedHttpHeaders(json['headers']);

  final bool Function() isActive;
  final String url;
  final String sourceUrl;
  final String title;
  final String? searchTitle;
  final Map<String, String> headers;
}

typedef PluginUrlSelector = Future<String?> Function(
  String title,
  List<PluginUrlChoice> items,
  String? preferredId,
);

Uri checkedHttpUri(dynamic value) {
  final uri = value is String ? Uri.tryParse(value) : null;
  if (uri == null ||
      !const ['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('插件返回了无效的 HTTP 地址');
  }
  return uri;
}

Map<String, String> checkedHttpHeaders(dynamic value) {
  if (value == null) return const {};
  if (value is! Map) throw const FormatException('无效的请求头');
  final headers = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String ||
        entry.value is! String ||
        !RegExp(r"^[!#$%&'*+.^_`|~0-9a-zA-Z-]+$").hasMatch(entry.key) ||
        RegExp(r'[\r\n\x00]').hasMatch(entry.value)) {
      throw const FormatException('无效的请求头');
    }
    final name = (entry.key as String).toLowerCase();
    if (const ['host', 'content-length', 'connection', 'transfer-encoding']
        .contains(name)) {
      throw const FormatException('不支持的请求头');
    }
    headers[name] = entry.value as String;
  }
  return Map.unmodifiable(headers);
}

String _requiredText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('插件缺少有效的 $key');
  }
  return value.trim();
}

/// Drives synchronous script continuations while performing I/O asynchronously.
class PluginUrlResolver {
  PluginUrlResolver(
      {required this.runtime, required this.isActive, http.Client? client})
      : _client = client ?? http.Client();

  final PluginJsRuntime runtime;
  final bool Function() isActive;
  final http.Client _client;
  static const maxResponseBytes = 4 * 1024 * 1024;

  Future<PluginResolvedUrl?> resolve(
    String url, {
    required PluginUrlSelector select,
    bool Function()? isCancelled,
  }) async {
    void checkActive() {
      if (!isActive() || (isCancelled?.call() ?? false)) {
        throw const PluginResolutionCancelled();
      }
    }

    var input = <String, dynamic>{'url': url};
    try {
      for (var step = 0; step < 16; step++) {
        checkActive();
        final encoded = runtime.evaluate('''
          JSON.stringify(typeof pluginResolveUrl === 'function'
            ? pluginResolveUrl(${jsonEncode(input)}) : null)
        ''');
        final decoded = jsonDecode(encoded);
        if (decoded == null && step == 0) return null;
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('插件返回了无效的解析结果');
        }
        final next = <String, dynamic>{'url': url, 'state': decoded['state']};
        switch (decoded['type']) {
          case 'request':
            final request = decoded['request'];
            if (request is! Map<String, dynamic>) {
              throw const FormatException('插件返回了无效的请求');
            }
            next['response'] = await _request(request);
          case 'select':
            final rawItems = decoded['items'];
            if (rawItems is! List ||
                rawItems.isEmpty ||
                rawItems.length > 2000) {
              throw const FormatException('插件返回了无效的选集列表');
            }
            final items = rawItems
                .map((item) => PluginUrlChoice(
                      Map<String, dynamic>.from(item as Map),
                    ))
                .toList(growable: false);
            if (items.map((item) => item.id).toSet().length != items.length) {
              throw const FormatException('插件返回了重复的选集编号');
            }
            checkActive();
            final selected = await select(
              _requiredText(decoded, 'title'),
              items,
              decoded['preferredId'] as String?,
            );
            if (selected == null) throw const PluginResolutionCancelled();
            if (!items.any((item) => item.id == selected)) {
              throw const FormatException('无效的选集编号');
            }
            next['selectedId'] = selected;
          case 'play':
            checkActive();
            return PluginResolvedUrl(decoded, isActive: isActive);
          case 'error':
            throw FormatException(_requiredText(decoded, 'message'));
          default:
            throw const FormatException('插件返回了未知的解析步骤');
        }
        input = next;
      }
      throw const FormatException('插件解析步骤过多');
    } finally {
      _client.close();
    }
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> data) async {
    final uri = checkedHttpUri(data['url']);
    final request = http.Request('GET', uri)
      ..headers.addAll(checkedHttpHeaders(data['headers']))
      ..followRedirects = false;
    return (() async {
      final response = await _client.send(request);
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw const FormatException('插件请求的响应过大');
        }
        bytes.addAll(chunk);
      }
      return <String, dynamic>{
        'url': uri.toString(),
        'status': response.statusCode,
        'headers': response.headers,
        'body': utf8.decode(bytes, allowMalformed: true),
      };
    })()
        .timeout(const Duration(seconds: 20));
  }
}
