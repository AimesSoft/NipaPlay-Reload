import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../providers/service_provider.dart';

// 定义一个通用的API媒体库模型
class ApiLibrary {
  final String id;
  final String name;
  final String type; // 'local', 'jellyfin', 'emby'

  ApiLibrary({required this.id, required this.name, required this.type});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
  };
}

class MediaController {
  final _router = Router();

  MediaController() {
    _router.get('/libraries', _getLibraries);
    // 在这里添加更多的媒体路由
  }

  Future<Response> _getLibraries(Request request) async {
    final List<ApiLibrary> allLibraries = [];

    // 1. 获取本地媒体库 (通过观看历史聚合)
    final watchHistoryProvider = ServiceProvider.watchHistoryProvider;
    if (watchHistoryProvider.history.isNotEmpty) {
      allLibraries.add(ApiLibrary(id: 'local', name: '本地媒体', type: 'local'));
    }

    // 2. 获取Jellyfin媒体库
    final jellyfinProvider = ServiceProvider.jellyfinProvider;
    if (jellyfinProvider.isConnected) {
      final jellyfinLibs = jellyfinProvider.availableLibraries.map((lib) => 
        ApiLibrary(id: lib.id, name: lib.name, type: 'jellyfin')
      ).toList();
      allLibraries.addAll(jellyfinLibs);
    }

    // 3. 获取Emby媒体库
    final embyProvider = ServiceProvider.embyProvider;
    if (embyProvider.isConnected) {
      final embyLibs = embyProvider.availableLibraries.map((lib) => 
        ApiLibrary(id: lib.id, name: lib.name, type: 'emby')
      ).toList();
      allLibraries.addAll(embyLibs);
    }

    final jsonResponse = jsonEncode(allLibraries.map((lib) => lib.toJson()).toList());
    return Response.ok(jsonResponse, headers: {'Content-Type': 'application/json'});
  }

  Router get router => _router;
}

