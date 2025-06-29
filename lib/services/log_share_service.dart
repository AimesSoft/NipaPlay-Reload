import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:flutter/foundation.dart';

class LogShareService {
  static const String _baseUrl = 'https://www.aimes-soft.com/nipaplay.php';  // 这个地址是正确的

  /// 上传日志并获取查看URL
  static Future<String> uploadLogs() async {
    try {
      final logService = DebugLogService();
      final logs = logService.logEntries.map((entry) => {
        'timestamp': entry.timestamp.toIso8601String(),
        'level': entry.level,
        'tag': entry.tag,
        'message': entry.message,
      }).toList();

      debugPrint('[LogShareService] 开始上传日志...');
      
      final response = await http.post(
        Uri.parse(_baseUrl),
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
          final viewUrl = data['viewUrl'];
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