import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'web_api_service.dart';
import 'package:nipaplay/utils/asset_helper.dart';
import 'package:nipaplay/services/nipaplay_lan_discovery.dart';

class WebServerService {
  // 兼容旧版本：历史上使用 web_server_enabled 来表示“自动启动”
  static const String _legacyAutoStartKey = 'web_server_enabled';
  static const String _autoStartKey = 'web_server_auto_start';
  static const String _portKey = 'web_server_port';
  static const String _devWebUiPortKey = SettingsKeys.devRemoteAccessWebUiPort;

  static const Set<String> _hopByHopHeaders = {
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
  };
  
  HttpServer? _server;
  int _port = 1180;
  bool _isRunning = false;
  bool _autoStart = false;
  int _devWebUiPort = 0;
  http.Client? _devWebUiProxyClient;
  final WebApiService _webApiService = WebApiService();
  final NipaPlayLanDiscoveryResponder _lanDiscoveryResponder =
      NipaPlayLanDiscoveryResponder();

  bool get isRunning => _isRunning;
  int get port => _port;
  bool get autoStart => _autoStart;
  int get devWebUiPort => _devWebUiPort;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _port = prefs.getInt(_portKey) ?? 1180;
    _devWebUiPort = prefs.getInt(_devWebUiPortKey) ?? 0;
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
      // 开发调试：如果设置了 devWebUiPort，则将 Web UI 请求反向代理到本机该端口
      final prefs = await SharedPreferences.getInstance();
      _devWebUiPort = prefs.getInt(_devWebUiPortKey) ?? 0;
      final bool useDevWebUiProxy = _devWebUiPort > 0 && _devWebUiPort < 65536;

      final Handler uiHandler;
      if (useDevWebUiProxy) {
        uiHandler = _createDevWebUiProxyHandler(port: _devWebUiPort);
      } else {
        // 静态文件服务
        final webAppPath =
            p.join((await StorageService.getAppStorageDirectory()).path, 'web');
        // 在启动服务器前，确保Web资源已解压
        await AssetHelper.extractWebAssets(webAppPath);
        uiHandler = createStaticHandler(webAppPath, defaultDocument: 'index.html');
      }

      final apiRouter = Router()..mount('/api/', _webApiService.handler);

      final Handler rootHandler = (Request request) {
        final path = request.url.path;
        // 严格隔离 /api：避免在开发代理模式下被 UI 代理兜底成 index.html
        if (path == 'api' || path.startsWith('api/')) {
          return apiRouter.call(request);
        }
        return uiHandler(request);
      };

      final handler = const Pipeline()
          .addMiddleware(corsHeaders())
          .addMiddleware(logRequests())
          .addHandler(rootHandler);
          
      _server = await shelf_io.serve(handler, '0.0.0.0', _port);
      _isRunning = true;
      if (useDevWebUiProxy) {
        print(
            'Web server started on port ${_server!.port} (dev web ui proxy -> 127.0.0.1:$_devWebUiPort)');
      } else {
        print('Web server started on port ${_server!.port}');
      }
      await _lanDiscoveryResponder.start(webPort: _server!.port);
      await saveSettings();
      return true;
    } catch (e) {
      print('Failed to start web server: $e');
      _isRunning = false;
      await _lanDiscoveryResponder.stop();
      return false;
    }
  }

  Handler _createDevWebUiProxyHandler({required int port}) {
    _devWebUiProxyClient ??= http.Client();
    final http.Client client = _devWebUiProxyClient!;
    final Uri baseUri = Uri.parse('http://127.0.0.1:$port/');

    return (Request request) async {
      final targetUri = baseUri.resolve(request.url.toString());
      final proxyRequest = http.StreamedRequest(request.method, targetUri);

      request.headers.forEach((name, value) {
        final lower = name.toLowerCase();
        if (lower == 'host') return;
        if (_hopByHopHeaders.contains(lower)) return;
        proxyRequest.headers[name] = value;
      });

      try {
        await proxyRequest.sink.addStream(request.read());
      } catch (_) {
        // ignore body stream errors
      } finally {
        await proxyRequest.sink.close();
      }

      try {
        final upstreamResponse = await client.send(proxyRequest);
        final headers = <String, String>{};
        upstreamResponse.headers.forEach((name, value) {
          final lower = name.toLowerCase();
          if (_hopByHopHeaders.contains(lower)) return;
          headers[name] = value;
        });
        return Response(
          upstreamResponse.statusCode,
          body: upstreamResponse.stream,
          headers: headers,
        );
      } catch (e) {
        return Response(
          502,
          body:
              'Dev Web UI proxy failed to connect to http://127.0.0.1:$port\n$e',
          headers: const {'Content-Type': 'text/plain; charset=utf-8'},
        );
      }
    };
  }

  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _isRunning = false;
      await _lanDiscoveryResponder.stop();
      _devWebUiProxyClient?.close();
      _devWebUiProxyClient = null;
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
