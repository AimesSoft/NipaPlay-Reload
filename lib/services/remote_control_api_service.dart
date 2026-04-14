import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:nipaplay/services/player_remote_control_bridge.dart';
import 'package:nipaplay/services/remote_control_access_guard_service.dart';

class RemoteControlApiService {
  RemoteControlApiService() {
    _router.get('/state', _handleState);
    _router.post('/command', _handleCommand);
  }

  final Router _router = Router();
  final RemoteControlAccessGuardService _accessGuard =
      RemoteControlAccessGuardService.instance;

  Router get router => _router;

  Future<Response> _handleState(Request request) async {
    try {
      final rawPaneId = request.url.queryParameters['paneId']?.trim();
      final paneId =
          (rawPaneId == null || rawPaneId.isEmpty) ? null : rawPaneId;
      final includeParameters =
          request.url.queryParameters['includeParameters'] == '1' ||
              paneId != null;
      final requestAccess = request.url.queryParameters['requestAccess'] == '1';
      final access = await _accessGuard.evaluate(
        request,
        requestAccess: requestAccess,
      );

      final payload = await PlayerRemoteControlBridge.instance.buildPayload(
        paneId: paneId,
        includeParameters: includeParameters,
      );
      payload['controlAuthorized'] = access.isAuthorized;
      payload['controlAuthorizationStatus'] = access.status.name;
      payload['controlAuthorizationMessage'] = _stateAuthMessage(access.status);
      return _json(<String, dynamic>{
        'success': true,
        'data': payload,
      });
    } catch (e) {
      return _json(
        <String, dynamic>{
          'success': false,
          'message': '获取遥控状态失败: $e',
        },
        statusCode: 500,
      );
    }
  }

  Future<Response> _handleCommand(Request request) async {
    Map<String, dynamic> body;
    try {
      final raw = await request.readAsString();
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        return _json(
          <String, dynamic>{
            'success': false,
            'message': '请求体必须是 JSON 对象',
          },
          statusCode: 400,
        );
      }
      body = decoded;
    } catch (_) {
      return _json(
        <String, dynamic>{
          'success': false,
          'message': '无效的 JSON',
        },
        statusCode: 400,
      );
    }

    final command = body['command']?.toString().trim() ?? '';
    if (command.isEmpty) {
      return _json(
        <String, dynamic>{
          'success': false,
          'message': '缺少 command',
        },
        statusCode: 400,
      );
    }

    final args = <String, dynamic>{};
    final rawArgs = body['args'];
    if (rawArgs is Map<String, dynamic>) {
      args.addAll(rawArgs);
    } else if (rawArgs is Map) {
      args.addAll(Map<String, dynamic>.from(rawArgs));
    }

    final access = await _accessGuard.evaluate(
      request,
      requestAccess: true,
    );
    if (!access.isAuthorized) {
      return _json(
        <String, dynamic>{
          'success': false,
          'code': 'remote_control_not_authorized',
          'authorizationStatus': access.status.name,
          'message': _commandAuthMessage(access.status),
        },
        statusCode: 403,
      );
    }

    try {
      final result = await PlayerRemoteControlBridge.instance.executeCommand(
        command,
        args,
      );
      return _json(result);
    } catch (e) {
      return _json(
        <String, dynamic>{
          'success': false,
          'message': '执行命令失败: $e',
        },
        statusCode: 500,
      );
    }
  }

  Response _json(Map<String, dynamic> body, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: json.encode(body),
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  String _stateAuthMessage(RemoteControlAccessStatus status) {
    switch (status) {
      case RemoteControlAccessStatus.authorized:
        return '已授权';
      case RemoteControlAccessStatus.pending:
        return '等待被控端确认连接';
      case RemoteControlAccessStatus.denied:
        return '被控端拒绝了连接请求';
      case RemoteControlAccessStatus.required:
        return '尚未发起连接请求';
    }
  }

  String _commandAuthMessage(RemoteControlAccessStatus status) {
    switch (status) {
      case RemoteControlAccessStatus.authorized:
        return '已授权';
      case RemoteControlAccessStatus.pending:
        return '等待被控端确认连接';
      case RemoteControlAccessStatus.denied:
        return '被控端拒绝了连接请求';
      case RemoteControlAccessStatus.required:
        return '未获得被控端授权';
    }
  }
}
