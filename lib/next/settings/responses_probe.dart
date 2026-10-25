import 'dart:convert';
import 'dart:io';

import '../ui_data/host_settings.dart';

/// Codex appends /responses itself. Accept a pasted endpoint without doubling
/// the suffix; keep the saved address unchanged so existing vault refs survive.
Uri responsesBase(Uri uri) {
  var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (path.endsWith('/responses')) {
    path = path.substring(0, path.length - '/responses'.length);
  }
  return uri.replace(path: path);
}

/// A chat-completions address may be pasted with its endpoint suffix.
Uri chatBase(Uri uri) {
  var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (path.endsWith('/chat/completions')) {
    path = path.substring(0, path.length - '/chat/completions'.length);
  }
  return uri.replace(path: path);
}

/// An account out of balance or quota fails every request; it is not a
/// refusal of the model, the endpoint or tools.
final _balance = RegExp(
    r'insufficient.(balance|quota|funds)|quota.exceeded|exceeded.*quota|billing|余额不足|欠费');

/// One bounded, non-streaming chat-completions request: a few tokens of
/// answer, with one harmless tool declared so that an endpoint refusing
/// tools says so. Upstream bodies are inspected for classification only.
Future<UiModelCheck> probeChatCompletions(
    HttpClient client, Uri base, String model, String key) async {
  base = chatBase(base);
  final request = await client
      .postUrl(base.replace(path: '${base.path}/chat/completions'));
  request.followRedirects = false;
  request.headers.contentType = ContentType.json;
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
  request.write(jsonEncode({
    'model': model,
    'messages': [
      {'role': 'user', 'content': 'Reply with OK.'}
    ],
    'tools': [
      {
        'type': 'function',
        'function': {
          'name': 'nipaplay_connection_check',
          'description': 'Harmless connection check; no action is performed.',
          'parameters': {'type': 'object', 'properties': {}},
        }
      }
    ],
    'max_tokens': 256,
    'stream': false,
  }));
  final response = await request.close();
  final bytes = <int>[];
  await for (final chunk in response) {
    if (bytes.length + chunk.length > 65536) {
      return const UiModelCheck(ok: false, message: '接口检查响应过大');
    }
    bytes.addAll(chunk);
  }
  Object? body;
  try {
    body = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    body = null;
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    final error = body is Map ? body['error'] : null;
    final description = error is Map
        ? '${error['code']} ${error['type']} ${error['param']} ${error['message']}'
            .toLowerCase()
        : '';
    final String message;
    if (response.statusCode == 401 || response.statusCode == 403) {
      message = '密钥无效或没有权限';
    } else if (response.statusCode == 402 || _balance.hasMatch(description)) {
      message = '账户余额不足或额度已用完';
    } else if (RegExp(
            r'model_not_found|unknown.model|invalid.model|model.*(not exist|not found|does not exist)|模型.*(不存在|未找到)')
        .hasMatch(description)) {
      message = '模型名不存在';
    } else if (description.contains('tool') &&
        RegExp(r'unsupported|not.support|not.allowed|invalid|unknown')
            .hasMatch(description)) {
      message = '此模型不支持工具调用';
    } else if (response.statusCode == 404 ||
        response.statusCode == 405 ||
        response.statusCode == 501) {
      message = '端点不支持 Chat Completions 接口';
    } else if (response.statusCode == 429) {
      message = '额度不足或请求过多';
    } else {
      message = '服务器未接受接口检查请求';
    }
    return UiModelCheck(ok: false, message: message);
  }
  final choices = body is Map ? body['choices'] : null;
  return choices is List && choices.isNotEmpty && choices.first is Map
      ? const UiModelCheck(ok: true, message: '可以使用')
      : const UiModelCheck(ok: false, message: '端点不支持 Chat Completions 接口');
}

/// One bounded, non-streaming Responses request with a forced harmless tool.
/// Some upstreams accept tools but refuse naming the one to call; then the
/// tool is offered once more without forcing it, and only a model that calls
/// it passes. Upstream bodies are inspected for classification only and never
/// returned.
Future<UiModelCheck> probeResponses(
    HttpClient client, Uri base, String model, String key) async {
  base = responsesBase(base);
  return _probeResponses(client, base, model, key, forced: true);
}

Future<UiModelCheck> _probeResponses(
    HttpClient client, Uri base, String model, String key,
    {required bool forced}) async {
  final request =
      await client.postUrl(base.replace(path: '${base.path}/responses'));
  request.followRedirects = false;
  request.headers.contentType = ContentType.json;
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
  request.write(jsonEncode({
    'model': model,
    'input': 'Call nipaplay_connection_check with no arguments.',
    'tools': [
      {
        'type': 'function',
        'name': 'nipaplay_connection_check',
        'description': 'Harmless connection check; no action is performed.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
          'additionalProperties': false
        }
      }
    ],
    'tool_choice': forced
        ? {'type': 'function', 'name': 'nipaplay_connection_check'}
        : 'auto',
    'max_output_tokens': 256,
    'store': false
  }));
  final response = await request.close();
  final bytes = <int>[];
  await for (final chunk in response) {
    if (bytes.length + chunk.length > 65536) {
      return const UiModelCheck(ok: false, message: '接口检查响应过大');
    }
    bytes.addAll(chunk);
  }
  Object? body;
  try {
    body = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    body = null;
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    final error = body is Map ? body['error'] : null;
    final description = error is Map
        ? '${error['code']} ${error['type']} ${error['param']} ${error['message']}'
            .toLowerCase()
        : '';
    final String message;
    if (response.statusCode == 401 || response.statusCode == 403) {
      message = '密钥无效或没有权限';
    } else if (response.statusCode == 402 || _balance.hasMatch(description)) {
      message = '账户余额不足或额度已用完';
    } else if (RegExp(
            r'model_not_found|unknown.model|invalid.model|model.*(not exist|not found|does not exist)|模型.*(不存在|未找到)')
        .hasMatch(description)) {
      message = '模型名不存在';
    } else if (forced && description.contains('tool_choice')) {
      return _probeResponses(client, base, model, key, forced: false);
    } else if (description.contains('tool') &&
        RegExp(r'unsupported|not.support|not.allowed|invalid|unknown')
            .hasMatch(description)) {
      message = '此模型不支持工具调用';
    } else if (response.statusCode == 404 ||
        response.statusCode == 405 ||
        response.statusCode == 501 ||
        RegExp(r'responses.*(unsupported|not.support|not.found)|chat.completions')
            .hasMatch(description)) {
      message = '端点不支持 Responses 接口';
    } else if (response.statusCode == 429) {
      message = '额度不足或请求过多';
    } else {
      message = '服务器未接受接口检查请求';
    }
    return UiModelCheck(ok: false, message: message);
  }
  if (body is! Map || body['object'] != 'response') {
    return const UiModelCheck(ok: false, message: '端点不支持 Responses 接口');
  }
  final output = body['output'];
  final tool = output is List &&
      output.any((item) =>
          item is Map &&
          item['type'] == 'function_call' &&
          item['name'] == 'nipaplay_connection_check' &&
          item['call_id'] is String &&
          item['arguments'] is String);
  return tool && body['status'] == 'completed'
      ? const UiModelCheck(ok: true, message: '可以使用，支持工具调用')
      : const UiModelCheck(ok: false, message: '未通过工具调用检查');
}
