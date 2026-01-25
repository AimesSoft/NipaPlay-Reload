import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'web_api_service.dart';
import 'package:nipaplay/services/nipaplay_lan_discovery.dart';

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
  final NipaPlayLanDiscoveryResponder _lanDiscoveryResponder =
      NipaPlayLanDiscoveryResponder();

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
      print('Remote access server is already running.');
      return true;
    }

    _port = port ?? _port;

    try {
      final apiRouter = Router()..mount('/api/', _webApiService.handler);

      final Handler rootHandler = (Request request) {
        final path = request.url.path;
        if (path == 'api' || path.startsWith('api/')) {
          return apiRouter.call(request);
        }
        return Response(
          404,
          body: 'Web UI 已移除，请使用 NipaPlay 客户端连接远程访问 API。',
          headers: const {'Content-Type': 'text/plain; charset=utf-8'},
        );
      };

      final handler = const Pipeline()
          .addMiddleware(corsHeaders())
          .addMiddleware(logRequests())
          .addHandler(rootHandler);
          
      _server = await shelf_io.serve(handler, '0.0.0.0', _port);
      _isRunning = true;
      print('Remote access server started on port ${_server!.port}');
      await _lanDiscoveryResponder.start(webPort: _server!.port);
      await saveSettings();
      return true;
    } catch (e) {
      print('Failed to start remote access server: $e');
      _isRunning = false;
      await _lanDiscoveryResponder.stop();
      return false;
    }
  }

  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _isRunning = false;
      await _lanDiscoveryResponder.stop();
      print('Remote access server stopped.');
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
