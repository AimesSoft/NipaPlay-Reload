import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

class PlayerController {
  final _router = Router();

  PlayerController() {
    _router.get('/status', _getStatus);
    // 在这里添加更多的播放器路由
  }

  Future<Response> _getStatus(Request request) async {
    // TODO: 实现获取播放状态的逻辑
    return Response.ok('{}');
  }

  Router get router => _router;
}

