import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum SpoilerAiApiFormat {
  openai,
  gemini,
}

class DanmakuSpoilerFilterService {
  DanmakuSpoilerFilterService._();

  static const String defaultEndpoint = 'https://ffmpeg.dfsteve.top/nipaplay.php';
  static const Duration _timeout = Duration(seconds: 60);

  static Future<List<String>> detectSpoilerDanmakuTexts({
    required List<String> danmakuTexts,
    SpoilerAiApiFormat apiFormat = SpoilerAiApiFormat.openai,
    String? apiUrl,
    String? apiKey,
    String model = 'gpt-5',
    double temperature = 0.5,
    int maxPromptChars = 24000,
    bool debugPrintResponse = false,
  }) async {
    final prompt = _buildPrompt(
      danmakuTexts,
      maxPromptChars: maxPromptChars,
    );
    if (prompt.trim().isEmpty) return <String>[];

    final resolvedTemperature = temperature.clamp(0.0, 2.0).toDouble();
    final resolvedApiUrl = (apiUrl ?? '').trim().isEmpty
        ? defaultEndpoint
        : (apiUrl ?? '').trim();
    final resolvedApiKey = (apiKey ?? '').trim();

    switch (apiFormat) {
      case SpoilerAiApiFormat.openai:
        final payload = <String, dynamic>{
          'model': model,
          'temperature': resolvedTemperature,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        };

        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        };
        if (resolvedApiKey.isNotEmpty) {
          headers['Authorization'] = resolvedApiKey.toLowerCase().startsWith('bearer ')
              ? resolvedApiKey
              : 'Bearer $resolvedApiKey';
        }

        final response = await http
            .post(
              Uri.parse(resolvedApiUrl),
              headers: headers,
              body: jsonEncode(payload),
            )
            .timeout(_timeout);

        if (response.statusCode != 200) {
          throw Exception(
            'AI请求失败: HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}',
          );
        }

        if (debugPrintResponse) {
          debugPrint('[防剧透AI] OpenAI响应: ${_clampForLog(response.body)}');
        }

        final rawText = _extractTextFromResponseBody(response.body);
        final parsed = _parseSpoilerTexts(rawText);
        if (debugPrintResponse) {
          debugPrint('[防剧透AI] 提取文本: ${_clampForLog(rawText)}');
          debugPrint('[防剧透AI] 解析结果(${parsed.length}): ${_clampForLog(parsed.join('||'))}');
        }
        return parsed;

      case SpoilerAiApiFormat.gemini:
        final resolvedModel = model.trim();
        if (resolvedModel.isEmpty) {
          throw Exception('Gemini 模式下 model 不能为空');
        }

        final requestUri = _buildGeminiGenerateContentUri(
          baseUrl: resolvedApiUrl,
          model: resolvedModel,
          apiKey: resolvedApiKey,
        );

        final payload = <String, dynamic>{
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'temperature': resolvedTemperature,
          },
        };

        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        };
        if (resolvedApiKey.isNotEmpty) {
          headers['x-goog-api-key'] = resolvedApiKey;
        }

        final response = await http
            .post(
              requestUri,
              headers: headers,
              body: jsonEncode(payload),
            )
            .timeout(_timeout);

        if (response.statusCode != 200) {
          throw Exception(
            'AI请求失败: HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}',
          );
        }

        if (debugPrintResponse) {
          debugPrint('[防剧透AI] Gemini响应: ${_clampForLog(response.body)}');
        }

        final rawText = _extractTextFromResponseBody(response.body);
        final parsed = _parseSpoilerTexts(rawText);
        if (debugPrintResponse) {
          debugPrint('[防剧透AI] 提取文本: ${_clampForLog(rawText)}');
          debugPrint('[防剧透AI] 解析结果(${parsed.length}): ${_clampForLog(parsed.join('||'))}');
        }
        return parsed;
    }
  }

  static String _buildPrompt(
    List<String> danmakuTexts, {
    required int maxPromptChars,
  }) {
    const header =
        '将下面弹幕内容中你认为涉及剧透的弹幕文本原样返回给我，弹幕之间使用||分割，除了返还内容本身以外什么都不做：\n';
    final buffer = StringBuffer(header);

    for (final text in danmakuTexts) {
      final normalized = text
          .replaceAll('\r', ' ')
          .replaceAll('\n', ' ')
          .trim();
      if (normalized.isEmpty) continue;

      final line = '$normalized\n';
      if (buffer.length + line.length > maxPromptChars) {
        break;
      }
      buffer.write(line);
    }

    return buffer.toString();
  }

  static Uri _buildGeminiGenerateContentUri({
    required String baseUrl,
    required String model,
    required String apiKey,
  }) {
    String normalized = baseUrl.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    final lower = normalized.toLowerCase();
    String fullUrl;
    if (lower.contains(':generatecontent') || lower.contains(':streamgeneratecontent')) {
      fullUrl = normalized;
    } else if (lower.endsWith('/models')) {
      fullUrl = '$normalized/$model:generateContent';
    } else if (lower.endsWith('/v1beta') || lower.endsWith('/v1')) {
      fullUrl = '$normalized/models/$model:generateContent';
    } else if (lower.contains('/models/')) {
      fullUrl = '$normalized:generateContent';
    } else {
      fullUrl = '$normalized/$model:generateContent';
    }

    Uri uri = Uri.parse(fullUrl);
    if (apiKey.trim().isNotEmpty && !uri.queryParameters.containsKey('key')) {
      final next = Map<String, String>.from(uri.queryParameters);
      next['key'] = apiKey.trim();
      uri = uri.replace(queryParameters: next);
    }
    return uri;
  }

  static String _clampForLog(String text, {int maxChars = 8000}) {
    final trimmed = text.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars)}...(truncated)';
  }

  static String _extractTextFromResponseBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '';

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final map = decoded.cast<String, dynamic>();

        final direct =
            (map['content'] ?? map['text'] ?? map['result'])?.toString();
        if (direct != null && direct.trim().isNotEmpty) {
          return direct.trim();
        }

        final candidates = map['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final candidate0 = candidates.first;
          if (candidate0 is Map) {
            final candidate = candidate0.cast<String, dynamic>();
            final content = candidate['content'];
            if (content is Map) {
              final parts = content['parts'];
              if (parts is List) {
                final texts = parts
                    .map((p) => p is Map ? p['text']?.toString() : null)
                    .whereType<String>()
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                if (texts.isNotEmpty) {
                  return texts.join('');
                }
              }
            }
            final text = candidate['output']?.toString();
            if (text != null && text.trim().isNotEmpty) {
              return text.trim();
            }
          }
        }

        final choices = map['choices'];
        if (choices is List && choices.isNotEmpty) {
          final choice0 = choices.first;
          if (choice0 is Map) {
            final choice = choice0.cast<String, dynamic>();
            final message = choice['message'];
            if (message is Map) {
              final content = message['content']?.toString();
              if (content != null && content.trim().isNotEmpty) {
                return content.trim();
              }
            }
            final text = choice['text']?.toString();
            if (text != null && text.trim().isNotEmpty) {
              return text.trim();
            }
          }
        }

        final output = map['output'];
        if (output is List && output.isNotEmpty) {
          final output0 = output.first;
          if (output0 is Map) {
            final content = output0['content'];
            if (content is List) {
              final texts = content
                  .map((e) => e is Map ? e['text']?.toString() : null)
                  .whereType<String>()
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              if (texts.isNotEmpty) {
                return texts.join('');
              }
            }
          }
        }
      }

      if (decoded is List) {
        final items = decoded
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
        return items.join('||');
      }
    } catch (e) {
      debugPrint('[DanmakuSpoilerFilterService] 解析AI响应失败，按纯文本处理: $e');
    }

    return trimmed;
  }

  static List<String> _parseSpoilerTexts(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return <String>[];

    final unquoted = _stripWrappingQuotes(trimmed);

    // 尝试JSON（用户有时会返回json格式）
    if (unquoted.startsWith('{') || unquoted.startsWith('[')) {
      try {
        final decoded = jsonDecode(unquoted);
        if (decoded is List) {
          return decoded
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
        }
        if (decoded is Map) {
          final map = decoded.cast<String, dynamic>();
          final listCandidate = map['spoilers'] ?? map['blocked'] ?? map['data'];
          if (listCandidate is List) {
            return listCandidate
                .map((e) => e?.toString().trim() ?? '')
                .where((e) => e.isNotEmpty)
                .toList();
          }
          final textCandidate = (map['content'] ?? map['text'])?.toString();
          if (textCandidate != null) {
            return _parseSpoilerTexts(textCandidate);
          }
        }
      } catch (_) {
        // ignore
      }
    }

    if (unquoted.contains('||')) {
      return unquoted
          .split('||')
          .map((e) => _stripWrappingQuotes(e.trim()))
          .where((e) => e.isNotEmpty)
          .toList();
    }

    if (unquoted.contains('\n')) {
      return unquoted
          .split('\n')
          .map((e) => _stripWrappingQuotes(e.trim()))
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return <String>[_stripWrappingQuotes(unquoted)];
  }

  static String _stripWrappingQuotes(String text) {
    final trimmed = text.trim();
    if (trimmed.length >= 2) {
      final first = trimmed.codeUnitAt(0);
      final last = trimmed.codeUnitAt(trimmed.length - 1);
      final isDoubleQuoted = first == 0x22 && last == 0x22; // "
      final isSingleQuoted = first == 0x27 && last == 0x27; // '
      if (isDoubleQuoted || isSingleQuoted) {
        return trimmed.substring(1, trimmed.length - 1).trim();
      }
    }
    return trimmed;
  }
}
