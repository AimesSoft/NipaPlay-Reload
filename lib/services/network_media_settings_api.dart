import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/dandanplay_remote_service.dart';

class NetworkMediaSettingsApi {
  NetworkMediaSettingsApi() {
    router.get('/jellyfin', _handleGetJellyfinSettings);
    router.post('/jellyfin', _handleUpdateJellyfinSettings);
    
    router.get('/emby', _handleGetEmbySettings);
    router.post('/emby', _handleUpdateEmbySettings);
    
    router.get('/dandanplay', _handleGetDandanplaySettings);
    router.post('/dandanplay', _handleUpdateDandanplaySettings);
  }

  final Router router = Router();

  // --- Jellyfin ---

  Future<Response> _handleGetJellyfinSettings(Request request) async {
    try {
      final service = JellyfinService.instance;
      return _jsonOk({
        'serverUrl': service.serverUrl,
        'username': service.username,
        'isConnected': service.isConnected,
        'selectedLibraryIds': service.selectedLibraryIds,
        // 注意：不返回密码和 AccessToken 等敏感信息，除非必要
        // 实际上为了 Web 端能代理连接，可能需要一部分信息，但最佳实践是 Web 端只下发指令
        // 如果 Web 端要复用 Service 逻辑，它需要这些凭证来直连（如果是局域网）或通过代理
        // 考虑到 Web Remote 模式下，Web 端可能无法直接访问 Jellyfin（如 NipaPlay 代理），
        // 或者 NipaPlay 本身作为中间人。
        // 目前简单起见，Web 端仅作为“配置同步器”，它获取配置后，调用 connectToServer，
        // 这会在 Web 端触发连接逻辑。这要求 Web 端能访问 Jellyfin 服务器。
        // 如果 Jellyfin 是内网的，Web 端也是内网的，这没问题。
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, 'Failed to get Jellyfin settings: $e');
    }
  }

  Future<Response> _handleUpdateJellyfinSettings(Request request) async {
    try {
      final payload = await _parseJsonBody(request);
      final service = JellyfinService.instance;
      
      final String? serverUrl = payload['serverUrl'];
      final String? username = payload['username'];
      final String? password = payload['password'];
      final List<String>? selectedLibraryIds = payload['selectedLibraryIds'] != null
          ? List<String>.from(payload['selectedLibraryIds'])
          : null;
      
      if (serverUrl != null && username != null && password != null) {
        // 执行连接操作
        final success = await service.connect(serverUrl, username, password);
        if (!success) {
          return _jsonError(HttpStatus.badRequest, 'Jellyfin connection failed');
        }
      }
      
      if (selectedLibraryIds != null) {
        await service.updateSelectedLibraries(selectedLibraryIds);
      }
      
      return _jsonOk({'success': true});
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, 'Failed to update Jellyfin settings: $e');
    }
  }

  // --- Emby ---

  Future<Response> _handleGetEmbySettings(Request request) async {
    try {
      final service = EmbyService.instance;
      return _jsonOk({
        'serverUrl': service.serverUrl,
        'username': service.username,
        'isConnected': service.isConnected,
        'selectedLibraryIds': service.selectedLibraryIds,
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, 'Failed to get Emby settings: $e');
    }
  }

  Future<Response> _handleUpdateEmbySettings(Request request) async {
    try {
      final payload = await _parseJsonBody(request);
      final service = EmbyService.instance;
      
      final String? serverUrl = payload['serverUrl'];
      final String? username = payload['username'];
      final String? password = payload['password'];
      final List<String>? selectedLibraryIds = payload['selectedLibraryIds'] != null
          ? List<String>.from(payload['selectedLibraryIds'])
          : null;
      
      if (serverUrl != null && username != null && password != null) {
        final success = await service.connect(serverUrl, username, password);
        if (!success) {
          return _jsonError(HttpStatus.badRequest, 'Emby connection failed');
        }
      }
      
      if (selectedLibraryIds != null) {
        await service.updateSelectedLibraries(selectedLibraryIds);
      }
      
      return _jsonOk({'success': true});
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, 'Failed to update Emby settings: $e');
    }
  }

  // --- Dandanplay ---

  Future<Response> _handleGetDandanplaySettings(Request request) async {
    try {
      final service = DandanplayRemoteService.instance;
      return _jsonOk({
        'serverUrl': service.serverUrl,
        'isConnected': service.isConnected,
        'lastSyncedAt': service.lastSyncedAt?.toIso8601String(),
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, 'Failed to get Dandanplay settings: $e');
    }
  }

  Future<Response> _handleUpdateDandanplaySettings(Request request) async {
    try {
      final payload = await _parseJsonBody(request);
      final service = DandanplayRemoteService.instance;
      
      final String? serverUrl = payload['serverUrl'];
      final String? token = payload['token'];
      final bool disconnect = payload['disconnect'] == true;

      if (disconnect) {
        await service.disconnect();
      } else if (serverUrl != null) {
        final success = await service.connect(serverUrl, token: token);
        if (!success) {
          return _jsonError(HttpStatus.badRequest, 'Dandanplay connection failed');
        }
      }
      
      return _jsonOk({'success': true});
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, 'Failed to update Dandanplay settings: $e');
    }
  }

  // Helpers

  Future<Map<String, dynamic>> _parseJsonBody(Request request) async {
    final body = await request.readAsString();
    if (body.isEmpty) return {};
    return json.decode(body) as Map<String, dynamic>;
  }

  Response _jsonOk(Map<String, dynamic> body) {
    return Response.ok(
      json.encode(body),
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Response _jsonError(int status, String message) {
    return Response(
      status,
      body: json.encode({'success': false, 'message': message}),
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
    );
  }
}
