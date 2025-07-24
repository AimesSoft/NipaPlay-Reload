import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:path/path.dart' as p;
import '../utils/storage_service.dart';
import 'web_api_service.dart';
import '../utils/asset_helper.dart';
import 'package:flutter/foundation.dart';

class WebServerService {
  static const String _enabledKey = 'web_server_enabled';
  static const String _portKey = 'web_server_port';
  
  HttpServer? _server;
  int _port = 8080;
  bool _isRunning = false;
  final WebApiService _webApiService = WebApiService();

  bool get isRunning => _isRunning;
  int get port => _port;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _port = prefs.getInt(_portKey) ?? 8080;
    final enabled = prefs.getBool(_enabledKey) ?? false;
    if (enabled) {
      await startServer();
    }
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, _isRunning);
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
          .add(apiRouter)
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }
} 