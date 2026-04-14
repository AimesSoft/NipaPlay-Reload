import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:nipaplay/services/player_remote_control_bridge.dart';

class RemoteControlApiService {
  RemoteControlApiService() {
    _router.get('/state', _handleState);
    _router.post('/command', _handleCommand);
  }

  final Router _router = Router();

  Router get router => _router;

  Future<Response> _handleState(Request request) async {
    try {
      final payload = await PlayerRemoteControlBridge.instance.buildPayload();
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
}
