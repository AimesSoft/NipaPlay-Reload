import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'bangumi_service.dart';
import 'dandanplay_service.dart';
import 'package:http/http.dart' as http;
import 'search_service.dart'; // 导入SearchService
import 'package:flutter/foundation.dart'; // 导入debugPrint

class WebApiService {
  final Router _router = Router();
  final SearchService _searchService = SearchService.instance; // 获取SearchService实例

  WebApiService() {
    _router.get('/bangumi/calendar', handleBangumiCalendarRequest);
    _router.get('/bangumi/detail/<id>', handleBangumiDetailRequest);
    _router.get('/danmaku/video_info', handleVideoInfoRequest);
    _router.get('/danmaku/load', handleDanmakuLoadRequest);
    _router.get('/image_proxy', handleImageProxyRequest);
    
    // 新增搜索相关的API路由
    _router.get('/search/config', handleSearchConfigRequest);
    _router.post('/search/by-tags', handleSearchByTagsRequest);
    _router.post('/search/advanced', handleAdvancedSearchRequest);
    
    // 弹弹play账号相关API路由
    _router.get('/dandanplay/login_status', handleLoginStatusRequest);
    _router.post('/dandanplay/login', handleLoginRequest);
    _router.post('/dandanplay/logout', handleLogoutRequest);
    _router.get('/dandanplay/play_history', handlePlayHistoryRequest);
    _router.get('/dandanplay/favorites', handleFavoritesRequest);
    _router.post('/dandanplay/send_danmaku', handleSendDanmakuRequest);
    _router.post('/dandanplay/add_play_history', handleAddPlayHistoryRequest);
    _router.post('/dandanplay/add_favorite', handleAddFavoriteRequest);
    _router.delete('/dandanplay/remove_favorite/<animeId>', handleRemoveFavoriteRequest);
  }

  Handler get handler => _router;

  Future<Response> handleBangumiCalendarRequest(Request request) async {
    try {
      final animes = await BangumiService.instance.getCalendar();
      final animesJson = animes.map((anime) => anime.toJson()).toList();
      return Response.ok(
        json.encode(animesJson),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: 'Error getting bangumi calendar: $e',
      );
    }
  }

  Future<Response> handleBangumiDetailRequest(Request request) async {
    final id = int.tryParse(request.params['id'] ?? '');
    if (id == null) {
      return Response.badRequest(body: 'Invalid or missing anime ID');
    }
    try {
      final anime = await BangumiService.instance.getAnimeDetails(id);
      return Response.ok(
        json.encode(anime.toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error getting anime details: $e');
    }
  }

  Future<Response> handleImageProxyRequest(Request request) async {
    final urlParam = request.url.queryParameters['url'];
    if (urlParam == null || urlParam.isEmpty) {
      return Response.badRequest(body: 'Missing image URL');
    }

    try {
      String imageUrl;
      // URL可能未编码，也可能经过了Base64编码。
      // 我们先尝试进行Base64解码，如果失败，就认为它是一个普通URL。
      try {
        imageUrl = utf8.decode(base64Url.decode(urlParam));
      } catch (e) {
        // 解码失败（非法的Base64格式），则假定它是一个未经编码的普通URL
        imageUrl = urlParam;
      }
      
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        return Response.ok(
          response.bodyBytes,
          headers: {'Content-Type': response.headers['content-type'] ?? 'image/jpeg'},
        );
      } else {
        return Response(response.statusCode, body: 'Failed to fetch image');
      }
    } catch (e) {
      return Response.internalServerError(body: 'Error proxying image: $e');
    }
  }

  // 新增处理函数
  Future<Response> handleSearchConfigRequest(Request request) async {
    try {
      final config = await _searchService.getSearchConfig();
      // SearchConfig 模型没有 toJson 方法，我们需要手动构建或者在模型中添加
      final configJson = {
        'success': true,
        'errorCode': 0,
        'errorMessage': null,
        'tags': config.tags.map((t) => {'key': t.key, 'value': t.value}).toList(),
        'types': config.types.map((t) => {'key': t.key, 'value': t.value}).toList(),
        'minYear': config.minYear,
        'maxYear': config.maxYear,
      };
      return Response.ok(
        json.encode(configJson),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error getting search config: $e');
    }
  }

  Future<Response> handleSearchByTagsRequest(Request request) async {
    try {
      final body = await request.readAsString();
      final Map<String, dynamic> data = json.decode(body);
      final List<String> tags = List<String>.from(data['tags'] ?? []);

      if (tags.isEmpty) {
        return Response.badRequest(body: 'Tags list cannot be empty');
      }

      final result = await _searchService.searchAnimeByTags(tags);
      // -- 调试代码开始 --
      debugPrint('[WebApiService] Raw search result from service:');
      debugPrint(json.encode(result.animes.map((a) => a.toJson()).toList()));
      // -- 调试代码结束 --

      // SearchResult 模型同样需要 toJson 支持
      final resultJson = {
        'success': true,
        'bangumis': result.animes.map((a) => a.toJson()).toList(), // 修正字段名
      };

      return Response.ok(
        json.encode(resultJson),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error searching by tags: $e');
    }
  }

  Future<Response> handleAdvancedSearchRequest(Request request) async {
    try {
      final body = await request.readAsString();
      final Map<String, dynamic> params = json.decode(body);
      
      final result = await _searchService.searchAnimeAdvanced(
        keyword: params['keyword'],
        type: params['type'],
        tagIds: params['tagIds'] != null ? List<int>.from(params['tagIds']) : null,
        year: params['year'],
        minRate: params['minRate'] ?? 0,
        maxRate: params['maxRate'] ?? 10,
        sort: params['sort'] ?? 0,
      );
      
      final resultJson = {
        'success': true,
        'bangumis': result.animes.map((a) => a.toJson()).toList(), // 修正字段名
      };

      return Response.ok(
        json.encode(resultJson),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error with advanced search: $e');
    }
  }

  // 新增弹弹play账号相关处理函数
  Future<Response> handleLoginStatusRequest(Request request) async {
    try {
      final status = {
        'isLoggedIn': DandanplayService.isLoggedIn,
        'userName': DandanplayService.userName,
        'screenName': DandanplayService.screenName,
      };
      
      return Response.ok(
        json.encode(status),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error getting login status: $e');
    }
  }

  Future<Response> handleLoginRequest(Request request) async {
    try {
      final body = await request.readAsString();
      final Map<String, dynamic> data = json.decode(body);
      final String username = data['username'] ?? '';
      final String password = data['password'] ?? '';
      
      if (username.isEmpty || password.isEmpty) {
        return Response.badRequest(body: 'Username and password are required');
      }
      
      final result = await DandanplayService.login(username, password);
      
      return Response.ok(
        json.encode(result),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error during login: $e');
    }
  }

  Future<Response> handleLogoutRequest(Request request) async {
    try {
      await DandanplayService.clearLoginInfo();
      
      return Response.ok(
        json.encode({'success': true, 'message': 'Logged out successfully'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error during logout: $e');
    }
  }

  Future<Response> handlePlayHistoryRequest(Request request) async {
    try {
      final fromDateStr = request.url.queryParameters['fromDate'];
      final toDateStr = request.url.queryParameters['toDate'];
      
      DateTime? fromDate;
      DateTime? toDate;
      
      if (fromDateStr != null) {
        fromDate = DateTime.tryParse(fromDateStr);
      }
      
      if (toDateStr != null) {
        toDate = DateTime.tryParse(toDateStr);
      }
      
      final result = await DandanplayService.getUserPlayHistory(
        fromDate: fromDate,
        toDate: toDate,
      );
      
      return Response.ok(
        json.encode(result),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error getting play history: $e');
    }
  }

  Future<Response> handleFavoritesRequest(Request request) async {
    try {
      final onlyOnAirParam = request.url.queryParameters['onlyOnAir'];
      final onlyOnAir = onlyOnAirParam == 'true';
      
      final result = await DandanplayService.getUserFavorites(
        onlyOnAir: onlyOnAir,
      );
      
      return Response.ok(
        json.encode(result),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error getting favorites: $e');
    }
  }

  Future<Response> handleSendDanmakuRequest(Request request) async {
    try {
      final body = await request.readAsString();
      final Map<String, dynamic> data = json.decode(body);
      
      final episodeId = data['episodeId'] as int?;
      final time = (data['time'] as num?)?.toDouble();
      final mode = data['mode'] as int?;
      final color = data['color'] as int?;
      final comment = data['comment'] as String?;
      
      if (episodeId == null || time == null || mode == null || color == null || comment == null) {
        return Response.badRequest(body: 'Missing required parameters');
      }
      
      final result = await DandanplayService.sendDanmaku(
        episodeId: episodeId,
        time: time,
        mode: mode,
        color: color,
        comment: comment,
      );
      
      return Response.ok(
        json.encode(result),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error sending danmaku: $e');
    }
  }

  Future<Response> handleAddPlayHistoryRequest(Request request) async {
    try {
      final body = await request.readAsString();
      final Map<String, dynamic> data = json.decode(body);
      
      final episodeIdList = List<int>.from(data['episodeIdList'] ?? []);
      final addToFavorite = data['addToFavorite'] as bool? ?? false;
      final rating = data['rating'] as int? ?? 0;
      
      if (episodeIdList.isEmpty) {
        return Response.badRequest(body: 'Episode ID list cannot be empty');
      }
      
      final result = await DandanplayService.addPlayHistory(
        episodeIdList: episodeIdList,
        addToFavorite: addToFavorite,
        rating: rating,
      );
      
      return Response.ok(
        json.encode(result),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error adding play history: $e');
    }
  }

  Future<Response> handleAddFavoriteRequest(Request request) async {
    try {
      final body = await request.readAsString();
      final Map<String, dynamic> data = json.decode(body);
      
      final animeId = data['animeId'] as int?;
      final favoriteStatus = data['favoriteStatus'] as String?;
      final rating = data['rating'] as int? ?? 0;
      final comment = data['comment'] as String?;
      
      if (animeId == null) {
        return Response.badRequest(body: 'Anime ID is required');
      }
      
      final result = await DandanplayService.addFavorite(
        animeId: animeId,
        favoriteStatus: favoriteStatus,
        rating: rating,
        comment: comment,
      );
      
      return Response.ok(
        json.encode(result),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error adding favorite: $e');
    }
  }

  Future<Response> handleRemoveFavoriteRequest(Request request) async {
    try {
      final animeId = int.tryParse(request.params['animeId'] ?? '');
      
      if (animeId == null) {
        return Response.badRequest(body: 'Invalid or missing anime ID');
      }
      
      final result = await DandanplayService.removeFavorite(animeId);
      
      return Response.ok(
        json.encode(result),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error removing favorite: $e');
    }
  }

  Future<Response> handleVideoInfoRequest(Request request) async {
    final videoPath = request.url.queryParameters['videoPath'];
    if (videoPath == null) {
      return Response.badRequest(body: 'Missing "videoPath" parameter');
    }
    try {
      final videoInfo = await DandanplayService.getVideoInfo(videoPath);
      return Response.ok(
        json.encode(videoInfo),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error getting video info: $e');
    }
  }

  Future<Response> handleDanmakuLoadRequest(Request request) async {
    final episodeId = request.url.queryParameters['episodeId'];
    final animeId = int.tryParse(request.url.queryParameters['animeId'] ?? '');

    if (episodeId == null || animeId == null) {
      return Response.badRequest(body: 'Missing or invalid "episodeId" or "animeId" parameters');
    }

    try {
      await DandanplayService.loadToken();
      final danmaku = await DandanplayService.getDanmaku(episodeId, animeId);
      return Response.ok(
        json.encode(danmaku),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error loading danmaku: $e');
    }
  }
}

