import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'bangumi_service.dart';
import 'dandanplay_service.dart';
import 'package:http/http.dart' as http;

class WebApiService {
  final Router _router = Router();

  WebApiService() {
    _router.get('/bangumi/calendar', handleBangumiCalendarRequest);
    _router.get('/bangumi/detail/<id>', handleBangumiDetailRequest);
    _router.get('/danmaku/video_info', handleVideoInfoRequest);
    _router.get('/danmaku/load', handleDanmakuLoadRequest);
    _router.get('/image_proxy', handleImageProxyRequest);
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
    final imageUrl = request.url.queryParameters['url'];
    if (imageUrl == null || imageUrl.isEmpty) {
      return Response.badRequest(body: 'Missing image URL');
    }

    try {
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

