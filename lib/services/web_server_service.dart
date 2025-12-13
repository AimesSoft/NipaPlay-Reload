import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/utils/storage_service.dart';
import 'web_api_service.dart';
import 'package:nipaplay/utils/asset_helper.dart';
import 'package:flutter/foundation.dart';

class WebServerService {
  // 兼容旧版本：历史上使用 web_server_enabled 来表示“自动启动”
  static const String _legacyAutoStartKey = 'web_server_enabled';
  static const String _autoStartKey = 'web_server_auto_start';
  static const String _portKey = 'web_server_port';
  
  HttpServer? _server;
  int _port = 1180;
  bool _isRunning = false;
  bool _autoStart = false;
  final WebApiService _webApiService = WebApiService();

  bool get isRunning => _isRunning;
  int get port => _port;
  bool get autoStart => _autoStart;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _port = prefs.getInt(_portKey) ?? 1180;
    if (prefs.containsKey(_autoStartKey)) {
      _autoStart = prefs.getBool(_autoStartKey) ?? false;
    } else {
      final legacyValue = prefs.getBool(_legacyAutoStartKey) ?? false;
      _autoStart = legacyValue;
      // 迁移旧配置到新Key，避免后续版本再依赖旧字段语义
      if (prefs.containsKey(_legacyAutoStartKey)) {
        await prefs.setBool(_autoStartKey, legacyValue);
      }
    }
    if (_autoStart) {
      await startServer();
    }
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_portKey, _port);
  }

  Future<bool> startServer({int? port}) async {
    if (_isRunning) {
      print('Web server is already running.');
      return true;
    }

    _port = port ?? _port;

    try {
      // 静态文件服务
      final webAppPath = p.join((await StorageService.getAppStorageDirectory()).path, 'web');
      // 在启动服务器前，确保Web资源已解压
      await AssetHelper.extractWebAssets(webAppPath);

      final staticHandler = createStaticHandler(webAppPath, defaultDocument: 'index.html');

      final apiRouter = Router()
        ..mount('/api/', _webApiService.handler);

      final cascade = Cascade()
          .add(apiRouter.call)
          .add(staticHandler);

      final handler = const Pipeline()
          .addMiddleware(corsHeaders())
          .addMiddleware(logRequests())
          .addHandler(cascade.handler);
          
      _server = await shelf_io.serve(handler, '0.0.0.0', _port);
      _isRunning = true;
      print('Web server started on port ${_server!.port}');
      await saveSettings();
      return true;
    } catch (e) {
      print('Failed to start web server: $e');
      _isRunning = false;
      return false;
    }
  }

  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _isRunning = false;
      print('Web server stopped.');
      await saveSettings();
    }
  }
  
  Future<List<String>> getAccessUrls() async {
    if (!_isRunning || _server == null) return [];

    final urls = <String>[];
    urls.add('http://localhost:${_server!.port}');
    urls.add('http://127.0.0.1:${_server!.port}');

    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            urls.add('http://${addr.address}:${_server!.port}');
          }
        }
      }
    } catch (e) {
      print('Error getting network interfaces: $e');
    }
    return urls;
  }

  Future<void> setPort(int newPort) async {
    if (newPort > 0 && newPort < 65536) {
      _port = newPort;
      await saveSettings();
      if (_isRunning) {
        await stopServer();
        await startServer();
      }
    }
  }

  Future<void> setAutoStart(bool enabled) async {
    _autoStart = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStartKey, enabled);
    // 写回旧Key，便于降级/旧版本读取
    await prefs.setBool(_legacyAutoStartKey, enabled);
  }
} 
