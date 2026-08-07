import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';

class LogShareService {
  static const String _baseUrl = 'https://nipaplay.aimes-soft.com/nipaplay.php';

  /// 将服务器返回的 URL 中的 localhost 地址重写为官网域名。
  /// 例如 http://localhost:8080/view?id=abc → https://nipaplay.aimes-soft.com/nipaplay.php?id=abc
  static String _toPublicUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '::1' ||
          host.startsWith('192.168.') ||
          host.startsWith('10.') ||
          host.startsWith('172.')) {
        // 提取 id 参数（或其他查询参数），用官网域名重建 URL。
        final id = uri.queryParameters['id'];
        if (id != null && id.isNotEmpty) {
          return '$_baseUrl?id=$id';
        }
        // 如果 URL 路径中包含 ID（如 /view/abc），提取最后一段作为 id。
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.isNotEmpty) {
          final lastSegment = segments.last;
          return '$_baseUrl?id=$lastSegment';
        }
      }
    } catch (_) {
      // 解析失败时保持原 URL。
    }
    return url;
  }

  /// 上传日志并获取查看URL
  static Future<String> uploadLogs() async {
    try {
      final logService = DebugLogService();
      final logs = logService.logEntries
          .map((entry) => {
                'timestamp': entry.timestamp.toIso8601String(),
                'level': entry.level,
                'tag': entry.tag,
                'message': entry.message,
              })
          .toList();

      debugPrint('[LogShareService] 开始上传日志...');

      final response = await http.post(
        WebRemoteAccessService.proxyUri(Uri.parse(_baseUrl)),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'logs': logs,
        }),
      );

      debugPrint('[LogShareService] 服务器响应状态码: ${response.statusCode}');
      debugPrint('[LogShareService] 服务器响应内容: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['viewUrl'] != null) {
          final rawUrl = data['viewUrl'] as String;
          // 服务器可能返回 localhost 内网地址，将其重写为官网域名。
          final viewUrl = _toPublicUrl(rawUrl);
          debugPrint('[LogShareService] 日志上传成功，查看URL: $viewUrl');
          return viewUrl;
        } else {
          final error = data['error'] ?? '未知错误';
          debugPrint('[LogShareService] 服务器返回错误: $error');
          throw '服务器返回错误: $error';
        }
      }

      debugPrint('[LogShareService] 服务器返回非200状态码: ${response.statusCode}');
      throw '上传失败: HTTP ${response.statusCode}';
    } catch (e) {
      debugPrint('[LogShareService] 上传日志时发生错误: $e');
      throw '上传日志失败: $e';
    }
  }
}
