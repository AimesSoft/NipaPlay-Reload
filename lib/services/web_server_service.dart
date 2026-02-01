import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_static/shelf_static.dart';
import 'web_api_service.dart';
import 'package:nipaplay/services/nipaplay_lan_discovery.dart';

class WebServerService {
  // 兼容旧版本：历史上使用 web_server_enabled 来表示“自动启动”
  static const String _legacyAutoStartKey = 'web_server_enabled';
  static const String _autoStartKey = 'web_server_auto_start';
  static const String _portKey = 'web_server_port';
  static const String _webAssetsRelativePath = 'assets/web';
  
  HttpServer? _server;
  int _port = 1180;
  bool _isRunning = false;
  bool _autoStart = false;
  String? _lastStartErrorMessage;
  final WebApiService _webApiService = WebApiService();
  final NipaPlayLanDiscoveryResponder _lanDiscoveryResponder =
      NipaPlayLanDiscoveryResponder();
  Handler? _webUiHandler;
  File? _webUiIndexFile;

  bool get isRunning => _isRunning;
  int get port => _port;
  bool get autoStart => _autoStart;
  String? get lastStartErrorMessage => _lastStartErrorMessage;

  Directory? _resolveWebUiRoot() {
    final candidates = <String>[
      path.join(Directory.current.path, _webAssetsRelativePath),
      if (Platform.isLinux || Platform.isWindows)
        path.join(
          path.dirname(Platform.resolvedExecutable),
          'data',
          'flutter_assets',
          _webAssetsRelativePath,
        ),
      if (Platform.isMacOS)
        path.join(
          path.dirname(Platform.resolvedExecutable),
          '..',
          'Frameworks',
          'App.framework',
          'Resources',
          'flutter_assets',
          _webAssetsRelativePath,
        ),
      if (Platform.isIOS)
        path.join(
          path.dirname(Platform.resolvedExecutable),
          'Frameworks',
          'App.framework',
          'flutter_assets',
          _webAssetsRelativePath,
        ),
    ];

    for (final candidate in candidates) {
      final dir = Directory(path.normalize(candidate));
      if (dir.existsSync()) {
        return dir;
      }
    }
    return null;
  }

  bool _shouldInjectApiParam(Request request) {
    if (_webUiHandler == null) return false;
    final query = request.url.queryParameters;
    if (query.containsKey('api') ||
        query.containsKey('apiBase') ||
        query.containsKey('baseUrl')) {
      return false;
    }
    final pathValue = request.url.path;
    if (pathValue.isEmpty || pathValue == 'index.html') {
      return true;
    }
    final segments = request.url.pathSegments;
    if (segments.isNotEmpty) {
      final first = segments.first;
      if (first == 'assets' || first == 'canvaskit' || first == 'icons') {
        return false;
      }
    }
    if (pathValue.contains('.')) {
      return false;
    }
    return true;
  }

  Response _redirectWithApiParam(Request request) {
    final origin = request.requestedUri.origin;
    final updatedQuery = Map<String, String>.from(request.url.queryParameters);
    updatedQuery['api'] = origin;
    final redirectUri = request.requestedUri.replace(queryParameters: updatedQuery);
    return Response.found(redirectUri.toString());
  }

  Future<Response> _handleWebUiRequest(Request request) async {
    final handler = _webUiHandler;
    final indexFile = _webUiIndexFile;
    if (handler == null || indexFile == null || !indexFile.existsSync()) {
      return Response(
        404,
        body: 'Web UI 资源未找到，请先运行 build_and_copy_web.sh 构建。',
        headers: const {'Content-Type': 'text/plain; charset=utf-8'},
      );
    }
    final patchedIndex = _tryServePatchedIndex(request, indexFile);
    if (patchedIndex != null) {
      return patchedIndex;
    }
    final patchedBootstrap = await _tryServePatchedBootstrap(request, indexFile);
    if (patchedBootstrap != null) {
      return patchedBootstrap;
    }
    final response = await handler(request);
    if (response.statusCode != 404) {
      return response;
    }
    final isAssetRequest = _isLikelyAssetRequest(request);
    if (isAssetRequest) {
      _logStaticNotFound(request, indexFile);
      return response;
    }
    _logFallback(request, indexFile);
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
      'X-WebUi-Fallback': '1',
    };
    if (request.method == 'HEAD') {
      return Response.ok(null, headers: headers);
    }
    return Response.ok(indexFile.openRead(), headers: headers);
  }

  Response? _tryServePatchedIndex(Request request, File indexFile) {
    final pathValue = request.url.path;
    if (pathValue.isNotEmpty && pathValue != 'index.html') {
      return null;
    }
    final original = indexFile.readAsStringSync();
    final patched = _patchIndexForRemote(original);
    if (patched == original && request.method == 'HEAD') {
      return Response.ok(null, headers: const {
        HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
      });
    }
    if (request.method == 'HEAD') {
      return Response.ok(null, headers: const {
        HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      });
    }
    return Response.ok(
      patched,
      headers: const {
        HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    );
  }

  Future<Response?> _tryServePatchedBootstrap(
    Request request,
    File indexFile,
  ) async {
    final pathValue = request.url.path;
    if (pathValue != 'flutter_bootstrap.js') {
      return null;
    }
    if (!request.url.queryParameters.containsKey('no-sw')) {
      return null;
    }
    final bootstrapFile = File(path.join(indexFile.parent.path, pathValue));
    if (!bootstrapFile.existsSync()) {
      return null;
    }
    if (request.method == 'HEAD') {
      return Response.ok(null, headers: const {
        HttpHeaders.contentTypeHeader: 'application/javascript',
        'Cache-Control': 'no-store',
      });
    }
    final original = await bootstrapFile.readAsString();
    final patched = _patchBootstrapForRemote(original);
    return Response.ok(
      patched,
      headers: const {
        HttpHeaders.contentTypeHeader: 'application/javascript',
        'Cache-Control': 'no-store',
      },
    );
  }

  String _patchIndexForRemote(String original) {
    const bootstrapTag = '<script src="flutter_bootstrap.js" async></script>';
    const patchedTag =
        '<script>'
        "if ('serviceWorker' in navigator) {"
        'navigator.serviceWorker.getRegistrations().then((regs) => {'
        'if (!regs.length) { return; }'
        'Promise.all(regs.map((reg) => reg.unregister())).then(() => {'
        "if (!sessionStorage.getItem('nipaplay_sw_cleared')) {"
        "sessionStorage.setItem('nipaplay_sw_cleared', '1');"
        'location.reload();'
        '}'
        '});'
        '});'
        '}'
        '</script>'
        '<script src="flutter_bootstrap.js?no-sw=1" async></script>';
    if (original.contains(patchedTag)) {
      return original;
    }
    if (original.contains(bootstrapTag)) {
      return original.replaceFirst(bootstrapTag, patchedTag);
    }
    return original;
  }

  String _patchBootstrapForRemote(String original) {
    final pattern = RegExp(
      r'_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*"[^"]+"\s*\}\s*\}\);',
      dotAll: true,
    );
    if (!pattern.hasMatch(original)) {
      return original;
    }
    return original.replaceFirst(pattern, '_flutter.loader.load({});');
  }

  bool _isLikelyAssetRequest(Request request) {
    final pathValue = request.url.path;
    if (pathValue.isEmpty) {
      return false;
    }
    final segments = request.url.pathSegments;
    if (segments.isNotEmpty) {
      final first = segments.first;
      if (first == 'assets' || first == 'canvaskit' || first == 'icons') {
        return true;
      }
    }
    final baseName = path.basename(pathValue);
    return baseName.contains('.');
  }

  void _logFallback(Request request, File indexFile) {
    _logStaticRouting(
      request,
      indexFile,
      prefix: '404回退index.html',
    );
  }

  void _logStaticNotFound(Request request, File indexFile) {
    _logStaticRouting(
      request,
      indexFile,
      prefix: '静态资源404',
    );
  }

  void _logStaticRouting(Request request, File indexFile, {required String prefix}) {
    final pathValue = request.url.path;
    final accept = request.headers[HttpHeaders.acceptHeader] ?? '';
    final rootDir = indexFile.parent;
    final normalizedPath =
        path.normalize(pathValue.isEmpty ? 'index.html' : pathValue);
    final resolvedPath = path.join(rootDir.path, normalizedPath);
    final exists = File(resolvedPath).existsSync();
    print('[WebServer] $prefix: ${request.requestedUri} '
        'accept="$accept" resolved="$resolvedPath" exists=$exists');
  }

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

  String _formatStartError(Object error) {
    if (error is SocketException) {
      final osError = error.osError;
      final errorCode = osError?.errorCode;
      final rawMessage = (osError?.message ?? error.message).trim();
      final lowerMessage = rawMessage.toLowerCase();
      if (errorCode == 48 ||
          errorCode == 98 ||
          errorCode == 10048 ||
          lowerMessage.contains('address already in use')) {
        return '端口 $_port 已被占用，请修改端口后重试。';
      }
      if (errorCode == 13 ||
          errorCode == 10013 ||
          lowerMessage.contains('permission denied') ||
          lowerMessage.contains('access is denied')) {
        return '没有权限绑定端口 $_port，请尝试 1024 以上端口或以更高权限运行。';
      }
      if (rawMessage.isNotEmpty) {
        return '无法监听端口 $_port：$rawMessage';
      }
    }
    return '远程访问服务启动失败：$error';
  }

  Future<bool> startServer({int? port}) async {
    if (_isRunning) {
      _lastStartErrorMessage = null;
      print('Remote access server is already running.');
      return true;
    }

    _port = port ?? _port;

    try {
      final webRoot = _resolveWebUiRoot();
      if (webRoot != null) {
        _webUiHandler = createStaticHandler(
          webRoot.path,
          defaultDocument: 'index.html',
          serveFilesOutsidePath: false,
        );
        _webUiIndexFile = File(path.join(webRoot.path, 'index.html'));
      } else {
        _webUiHandler = null;
        _webUiIndexFile = null;
      }
      // 挂载在 '/api'，剥离前缀后保留子路径的前导斜杠 (e.g. /api/info -> /info)
      final apiRouter = Router()..mount('/api', _webApiService.handler);

      final Handler rootHandler = (Request request) async {
        final path = request.url.path;
        //print('[WebServer] 收到请求: "$path", handlerPath: "${request.handlerPath}"');
        
        if (path == 'api' || path.startsWith('api/')) {
          //print('[WebServer] 匹配到API路径，尝试分发...');
          try {
            final response = await apiRouter.call(request);
            //print('[WebServer] API路由器响应状态码: ${response.statusCode}');
            if (response.statusCode == 404) {
               //print('[WebServer] 警告：API路由器返回404。请检查 web_api_service.dart 中的路由定义是否与请求路径匹配。');
            }
            return response;
          } catch (e) {
            //print('[WebServer] API处理异常: $e');
            return Response.internalServerError(body: 'API Error: $e');
          }
        }
        if (_shouldInjectApiParam(request)) {
          return _redirectWithApiParam(request);
        }
        return _handleWebUiRequest(request);
      };

      final handler = const Pipeline()
          .addMiddleware(corsHeaders())
          .addMiddleware(logRequests())
          .addHandler(rootHandler);
          
      _server = await shelf_io.serve(handler, '0.0.0.0', _port);
      _isRunning = true;
      _lastStartErrorMessage = null;
      print('Remote access server started on port ${_server!.port}');
      await _lanDiscoveryResponder.start(webPort: _server!.port);
      await saveSettings();
      return true;
    } catch (e) {
      _isRunning = false;
      _server = null;
      _lastStartErrorMessage = _formatStartError(e);
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
