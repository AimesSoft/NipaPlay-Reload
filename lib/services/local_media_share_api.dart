import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'local_media_share_service.dart';

class LocalMediaShareApi {
  LocalMediaShareApi() {
    router.get('/animes', _handleListAnimes);
    router.get('/animes/<animeId|[0-9]+>', _handleAnimeDetail);
    router.get('/episodes/<shareId>/stream', _handleEpisodeStream);
    router.add('HEAD', '/episodes/<shareId>/stream', _handleEpisodeStreamHead);
    router.post('/episodes/<shareId>/progress', _handleUpdateEpisodeProgress);
  }

  final LocalMediaShareService _service = LocalMediaShareService.instance;
  final Router router = Router();

  Future<Response> _handleListAnimes(Request request) async {
    try {
      final items = await _service.getAnimeSummaries();
      return Response.ok(
        json.encode({'success': true, 'items': items}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error listing shared animes: $e');
    }
  }

  Future<Response> _handleAnimeDetail(Request request) async {
    final animeIdStr = request.params['animeId'];
    final animeId = int.tryParse(animeIdStr ?? '');
    if (animeId == null) {
      return Response.badRequest(body: 'Invalid animeId');
    }

    try {
      final detail = await _service.getAnimeDetail(animeId);
      if (detail == null) {
        return Response.notFound('Anime not found');
      }
      return Response.ok(
        json.encode({'success': true, 'data': detail}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error loading shared anime detail: $e');
    }
  }

  Future<Response> _handleEpisodeStream(Request request) async {
    final shareId = request.params['shareId'];
    if (shareId == null || shareId.isEmpty) {
      return Response.badRequest(body: 'Missing shareId');
    }

    final episode = _service.getEpisodeByShareId(shareId);
    if (episode == null) {
      return Response.notFound('Episode not found');
    }

    try {
      return await _service.buildStreamResponse(request, episode);
    } catch (e) {
      return Response.internalServerError(body: 'Error streaming shared episode: $e');
    }
  }

  Future<Response> _handleEpisodeStreamHead(Request request) async {
    final shareId = request.params['shareId'];
    if (shareId == null || shareId.isEmpty) {
      return Response.badRequest(body: 'Missing shareId');
    }

    final episode = _service.getEpisodeByShareId(shareId);
    if (episode == null) {
      return Response.notFound('Episode not found');
    }

    try {
      return await _service.buildStreamResponse(
        request,
        episode,
        headOnly: true,
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error streaming shared episode: $e');
    }
  }


  Future<Response> _handleUpdateEpisodeProgress(Request request) async {
    final shareId = request.params['shareId'];
    if (shareId == null || shareId.isEmpty) {
      return Response.badRequest(body: 'Missing shareId');
    }

    Map<String, dynamic> payload = const {};
    try {
      final rawBody = await request.readAsString();
      if (rawBody.isNotEmpty) {
        payload = json.decode(rawBody) as Map<String, dynamic>;
      }
    } catch (_) {
      return Response.badRequest(body: 'Invalid JSON payload');
    }

    double? progress;
    final progressValue = payload['progress'];
    if (progressValue is num) {
      progress = progressValue.toDouble();
    }

    int? positionMs;
    final positionValue = payload['positionMs'] ?? payload['position'];
    if (positionValue is num) {
      positionMs = positionValue.toInt();
    }

    int? durationMs;
    final durationValue = payload['durationMs'] ?? payload['duration'];
    if (durationValue is num) {
      durationMs = durationValue.toInt();
    }

    DateTime? clientUpdatedAt;
    final clientTime = payload['clientUpdatedAt'] ?? payload['clientTime'];
    if (clientTime is String) {
      clientUpdatedAt = DateTime.tryParse(clientTime);
    }

    try {
      final updatedHistory = await _service.updateEpisodeProgress(
        shareId: shareId,
        progress: progress,
        positionMs: positionMs,
        durationMs: durationMs,
        clientUpdatedAt: clientUpdatedAt,
      );

      if (updatedHistory == null) {
        return Response.notFound('Episode not found');
      }

      return Response.ok(
        json.encode({
          'success': true,
          'data': {
            'progress': updatedHistory.watchProgress,
            'lastPosition': updatedHistory.lastPosition,
            'duration': updatedHistory.duration,
            'lastWatchTime': updatedHistory.lastWatchTime.toIso8601String(),
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Failed to update progress: $e');
    }
  }

}
