import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

class SettingsController {
  final _router = Router();

  SettingsController() {
    _router.get('/', _getSettings);
    // 在这里添加更多的设置路由
  }

  Future<Response> _getSettings(Request request) async {
    // TODO: 实现获取所有设置的逻辑
    return Response.ok('{}');
  }

  Router get router => _router;
}

