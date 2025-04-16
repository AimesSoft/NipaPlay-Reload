import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class NetworkChecker {
  /// 检查网络连接
  /// 
  /// [url] - 要检查的URL，默认是百度
  /// [timeout] - 超时时间，单位为秒
  /// [verbose] - 是否显示详细的请求信息
  /// 
  /// 返回一个Map，包含是否连接成功以及详细信息
  static Future<Map<String, dynamic>> checkConnection({
    String url = 'https://www.baidu.com',
    int timeout = 5,
    bool verbose = false,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    
    try {
      if (verbose) {
        debugPrint('开始检查网络连接: $url');
        debugPrint('设备信息: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
      }
      
      // 先检查DNS解析
      if (verbose) debugPrint('正在解析DNS...');
      final List<InternetAddress> addresses = await InternetAddress.lookup(url.replaceAll(RegExp(r'https?://'), ''));
      
      if (addresses.isEmpty) {
        if (verbose) debugPrint('DNS解析失败: 无法解析域名');
        return {
          'connected': false,
          'message': 'DNS解析失败: 无法解析域名',
          'error': 'DNS lookup returned no addresses',
          'duration': stopwatch.elapsed.inMilliseconds,
        };
      }
      
      if (verbose) {
        debugPrint('DNS解析成功: ${addresses.length} 个地址');
        for (var address in addresses) {
          debugPrint(' - ${address.address} (${address.type == InternetAddressType.IPv4 ? 'IPv4' : 'IPv6'})');
        }
      }
      
      // 然后尝试HTTP请求
      if (verbose) debugPrint('正在发送HTTP请求...');
      final response = await http.get(Uri.parse(url)).timeout(
        Duration(seconds: timeout),
        onTimeout: () {
          throw TimeoutException('请求超时');
        },
      );
      
      stopwatch.stop();
      final connectionSpeed = stopwatch.elapsed.inMilliseconds;
      
      if (verbose) {
        debugPrint('HTTP请求完成，状态码: ${response.statusCode}');
        debugPrint('响应时间: ${connectionSpeed}ms');
        //debugPrint('响应头: ${response.headers}');
        debugPrint('响应大小: ${response.bodyBytes.length} 字节');
      }
      
      return {
        'connected': response.statusCode >= 200 && response.statusCode < 300,
        'message': '网络连接正常，状态码: ${response.statusCode}',
        'statusCode': response.statusCode,
        'duration': connectionSpeed,
        'responseSize': response.bodyBytes.length,
        'headers': response.headers,
      };
    } on SocketException catch (e) {
      stopwatch.stop();
      if (verbose) {
        debugPrint('连接失败(Socket异常): ${e.toString()}');
        debugPrint('错误详情: ${e.message}, 地址: ${e.address?.address}, 端口: ${e.port}');
      }
      
      return {
        'connected': false,
        'message': '网络连接失败: 无法连接到服务器',
        'error': e.toString(),
        'errorType': 'SocketException',
        'duration': stopwatch.elapsed.inMilliseconds,
      };
    } on TimeoutException catch (e) {
      stopwatch.stop();
      if (verbose) debugPrint('连接超时: ${e.toString()}');
      
      return {
        'connected': false,
        'message': '网络连接超时',
        'error': e.toString(),
        'errorType': 'TimeoutException',
        'duration': stopwatch.elapsed.inMilliseconds,
      };
    } catch (e) {
      stopwatch.stop();
      if (verbose) debugPrint('未知错误: ${e.toString()}');
      
      return {
        'connected': false,
        'message': '未知网络错误',
        'error': e.toString(),
        'errorType': e.runtimeType.toString(),
        'duration': stopwatch.elapsed.inMilliseconds,
      };
    }
  }
  
  /// 检查当前网络代理设置
  static Map<String, dynamic> checkProxySettings() {
    try {
      final Map<String, String> envVars = Platform.environment;
      final Map<String, dynamic> result = {};
      
      // 检查常见的代理环境变量
      final proxyVars = [
        'http_proxy', 'HTTP_PROXY',
        'https_proxy', 'HTTPS_PROXY',
        'all_proxy', 'ALL_PROXY',
        'no_proxy', 'NO_PROXY'
      ];
      
      for (var v in proxyVars) {
        if (envVars.containsKey(v)) {
          result[v] = envVars[v];
        }
      }
      
      // iOS特定代理信息
      if (Platform.isIOS) {
        result['note'] = '无法直接获取iOS系统代理设置，需要在设置应用中查看';
      }
      
      return {
        'hasProxy': result.isNotEmpty,
        'proxySettings': result,
      };
    } catch (e) {
      return {
        'hasProxy': false,
        'error': e.toString(),
      };
    }
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  
  @override
  String toString() => message;
} 