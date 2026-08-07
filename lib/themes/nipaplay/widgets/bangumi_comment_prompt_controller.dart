import 'package:flutter/material.dart';
import 'package:nipaplay/models/bangumi_collection_submit_result.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/server_connectivity_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/bangumi_comment_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class BangumiCommentPromptController {
  const BangumiCommentPromptController._();

  static bool get isAvailable => shouldOfferComment(
        bangumiAvailable:
            ServerConnectivityService.instance.bangumiAvailable == true,
        isLoggedIn: BangumiApiService.isLoggedIn,
      );

  static bool shouldOfferComment({
    required bool bangumiAvailable,
    required bool isLoggedIn,
  }) =>
      bangumiAvailable && isLoggedIn;

  static Future<void> showForCurrentAnime(
    BuildContext context,
    VideoPlayerState videoState,
  ) async {
    if (!context.mounted) return;
    if (!isAvailable) {
      BlurSnackBar.show(context, 'Bangumi 当前不可用');
      return;
    }

    await BangumiApiService.initialize();
    if (!context.mounted) return;
    if (!BangumiApiService.isLoggedIn) {
      BlurSnackBar.show(context, '请先在账号设置中登录 Bangumi');
      return;
    }

    final animeId =
        videoState.animeId ?? videoState.playbackDetailContext?.animeId;
    if (animeId == null || animeId <= 0) {
      BlurSnackBar.show(context, '当前视频尚未匹配番剧，无法评论');
      return;
    }

    try {
      var animeTitle = videoState.animeTitle?.trim() ?? '';
      int? subjectId;
      try {
        final anime =
            BangumiService.instance.getAnimeDetailsFromMemory(animeId) ??
                await BangumiService.instance.getAnimeDetails(animeId);
        subjectId = extractSubjectId(anime.bangumiUrl);
        animeTitle = _firstNonEmpty(
          anime.nameCn,
          animeTitle,
          anime.name,
        );
      } catch (e) {
        debugPrint('[Bangumi评论] 从弹弹play详情解析条目失败: $e');
      }

      subjectId ??= await _findSubjectByTitle(animeTitle);
      if (!context.mounted) return;
      if (subjectId == null) {
        BlurSnackBar.show(context, '未找到对应的 Bangumi 条目');
        return;
      }
      final resolvedSubjectId = subjectId;

      final collection =
          await BangumiApiService.getUserCollection(resolvedSubjectId);
      if (!context.mounted) return;
      final initial = _parseCollection(collection);

      await BangumiCommentDialog.show(
        context: context,
        animeTitle: animeTitle,
        initialRating: initial.rating,
        initialComment: initial.comment,
        collectionType: initial.collectionType,
        onSubmit: (result) => _submitComment(
          context,
          resolvedSubjectId,
          result,
          hasCollection: initial.hasCollection,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        BlurSnackBar.show(context, '打开评论失败：$e');
      }
    }
  }

  static int? extractSubjectId(String? bangumiUrl) {
    if (bangumiUrl == null || bangumiUrl.trim().isEmpty) return null;
    final direct = RegExp(r'/subject/(\d+)').firstMatch(bangumiUrl);
    if (direct != null) return int.tryParse(direct.group(1)!);

    final uri = Uri.tryParse(bangumiUrl);
    final queryId = int.tryParse(uri?.queryParameters['subject_id'] ?? '');
    if (queryId != null) return queryId;
    if (uri != null) {
      for (final segment in uri.pathSegments.reversed) {
        final parsed = int.tryParse(segment);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static Future<int?> _findSubjectByTitle(String title) async {
    if (title.trim().isEmpty) return null;
    final result = await BangumiApiService.searchSubjects(
      title.trim(),
      type: 2,
      limit: 10,
    );
    if (result['success'] != true || result['data'] is! Map) return null;
    final data = result['data'] as Map;
    final items = data['data'];
    if (items is! List || items.isEmpty || items.first is! Map) return null;
    final id = (items.first as Map)['id'];
    return id is int ? id : int.tryParse(id?.toString() ?? '');
  }

  static _CollectionInitialValue _parseCollection(
    Map<String, dynamic> response,
  ) {
    if (response['success'] != true || response['data'] is! Map) {
      return const _CollectionInitialValue(
        hasCollection: false,
        rating: 0,
        comment: null,
        collectionType: 3,
      );
    }

    final data = Map<String, dynamic>.from(response['data'] as Map);
    final ratingData = data['rating'];
    final rating = ratingData is Map && ratingData['score'] is num
        ? (ratingData['score'] as num).round()
        : (data['rate'] is num ? (data['rate'] as num).round() : 0);
    final rawType = data['type'];
    final collectionType =
        rawType is int && rawType >= 1 && rawType <= 5 ? rawType : 3;
    final rawComment = data['comment'];
    final comment = rawComment is String && rawComment.trim().isNotEmpty
        ? rawComment.trim()
        : null;
    return _CollectionInitialValue(
      hasCollection: true,
      rating: rating,
      comment: comment,
      collectionType: collectionType,
    );
  }

  static Future<void> _submitComment(
    BuildContext context,
    int subjectId,
    BangumiCollectionSubmitResult result, {
    required bool hasCollection,
  }) async {
    final collectionType = result.collectionType.clamp(1, 5);
    final response = hasCollection
        ? await BangumiApiService.updateUserCollection(
            subjectId,
            type: collectionType,
            comment: result.comment.trim(),
            rate: result.rating,
          )
        : await BangumiApiService.addUserCollection(
            subjectId,
            collectionType,
            comment: result.comment.trim(),
            rate: result.rating,
          );
    if (response['success'] != true) {
      final message = response['message']?.toString() ?? '未知错误';
      if (context.mounted) BlurSnackBar.show(context, '评论提交失败：$message');
      throw StateError(message);
    }
    if (context.mounted) BlurSnackBar.show(context, '评论已提交');
  }

  static String _firstNonEmpty(String first, String? second, String third) {
    if (first.trim().isNotEmpty) return first.trim();
    if (second?.trim().isNotEmpty == true) return second!.trim();
    return third.trim().isNotEmpty ? third.trim() : '当前番剧';
  }
}

class _CollectionInitialValue {
  const _CollectionInitialValue({
    required this.hasCollection,
    required this.rating,
    required this.comment,
    required this.collectionType,
  });

  final bool hasCollection;
  final int rating;
  final String? comment;
  final int collectionType;
}
