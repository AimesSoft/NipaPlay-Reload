import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/models/bangumi_comment_model.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nipaplay/services/web_remote_access_service.dart';

class BangumiMyCommentData {
  final String nickname;
  final String avatarUrl;
  final int rate;
  final String comment;
  final int updatedAt;

  const BangumiMyCommentData({
    required this.nickname,
    required this.avatarUrl,
    this.rate = 0,
    this.comment = '',
    required this.updatedAt,
  });
}

class BangumiCommentsWidget extends StatefulWidget {
  final int? subjectId;
  final VoidCallback? onEditRating;
  final BangumiMyCommentData? myComment;
  final int currentUserId;
  final int commentsVersion;
  final ValueChanged<int>? onMyCommentTimestamp;

  const BangumiCommentsWidget({
    super.key,
    required this.subjectId,
    this.onEditRating,
    this.myComment,
    this.currentUserId = 0,
    this.commentsVersion = 0,
    this.onMyCommentTimestamp,
  });

  @override
  State<BangumiCommentsWidget> createState() => _BangumiCommentsWidgetState();
}

class _BangumiCommentsWidgetState extends State<BangumiCommentsWidget> {
  final List<BangumiComment> _comments = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.subjectId != null) {
      _loadComments();
    }
  }

  @override
  void didUpdateWidget(BangumiCommentsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId ||
        oldWidget.commentsVersion != widget.commentsVersion) {
      _isLoading = false;
      _comments.clear();
      _currentOffset = 0;
      _hasMore = true;
      _error = null;
      if (widget.subjectId != null) {
        _loadComments();
      }
    }
  }

  Future<void> _loadComments() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (widget.subjectId == null) {
        debugPrint('[Bangumi Comments Widget] subjectId为null，跳过加载');
        return;
      }
      final int requestedSubjectId = widget.subjectId!;
      debugPrint(
          '[Bangumi Comments Widget] 开始加载 subjectId=$requestedSubjectId, offset=$_currentOffset');
      final result = await BangumiApiService.getSubjectComments(
        requestedSubjectId,
        offset: _currentOffset,
      );
      debugPrint(
          '[Bangumi Comments Widget] API返回 success=${result['success']}, message=${result['message']}');

      if (!mounted) return;
      if (widget.subjectId != requestedSubjectId) return;

      if (result['success'] == true) {
        final data = result['data'];
        debugPrint('[Bangumi Comments Widget] data类型: ${data.runtimeType}');
        final list = (data['data'] as List?) ?? (data['list'] as List?) ?? [];
        final total = data['total'] as int? ?? 0;
        debugPrint(
            '[Bangumi Comments Widget] 解析到 ${list.length} 条, total=$total');
        var newComments = list.map((e) => BangumiComment.fromJson(e)).toList();
        if (widget.currentUserId > 0) {
          final myComment = newComments.cast<BangumiComment?>().firstWhere(
                (c) => c!.userId == widget.currentUserId,
                orElse: () => null,
              );
          if (myComment != null && myComment.updatedAt > 0) {
            widget.onMyCommentTimestamp?.call(myComment.updatedAt);
          }
          newComments = newComments
              .where((c) => c.userId != widget.currentUserId)
              .toList();
        }
        debugPrint(
            '[Bangumi Comments Widget] 转换后 ${newComments.length} 条 BangumiComment');

        setState(() {
          _comments.addAll(newComments);
          _currentOffset += list.length;
          _hasMore = _currentOffset < total;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = result['message'] as String? ?? '加载失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  void loadMore() {
    if (!_hasMore || _isLoading) return;
    _loadComments();
  }

  String _formatRelativeTime(int timestamp) {
    final now = DateTime.now();
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final diff = now.difference(time);
    if (diff.inSeconds <= 60) return '刚刚';
    if (diff.inMinutes <= 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours <= 12) return '${diff.inHours}小时前';
    if (diff.inDays <= 30) return '${diff.inDays}天前';
    if (diff.inDays <= 365) return '${diff.inDays ~/ 30}个月前';
    return '${diff.inDays ~/ 365}年前';
  }

  String _proxiedImageUrl(String url) {
    if (url.isEmpty) return url;
    if (kIsWeb) {
      return WebRemoteAccessService.imageProxyUrl(url) ?? url;
    }
    return url;
  }

  Widget _buildMiniStars(int rate, Color accentColor, Color mutedColor) {
    if (rate <= 0) return const SizedBox.shrink();
    final double starRating = rate / 2;
    final int fullStars = starRating.floor();
    final bool hasHalf = (starRating - fullStars) >= 0.5;
    final List<Widget> stars = [];
    for (int i = 0; i < 5; i++) {
      if (i < fullStars) {
        stars.add(Icon(Ionicons.star, size: 14, color: accentColor));
      } else if (i == fullStars && hasHalf) {
        stars.add(Icon(Ionicons.star_half, size: 14, color: accentColor));
      } else {
        stars.add(Icon(Ionicons.star_outline, size: 14, color: mutedColor));
      }
      if (i < 4) stars.add(const SizedBox(width: 1));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: stars);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.subjectId == null) {
      final bool isDark = Theme.of(context).brightness == Brightness.dark;
      final Color secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('当前番剧未关联Bangumi条目，无法加载评论',
              style: TextStyle(color: secondaryTextColor, fontSize: 13)),
        ),
      );
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final Color accentColor = AppAccentColors.current;
    final Color mutedColor = accentColor.withOpacity(isDark ? 0.4 : 0.3);

    final bool hasMyComment = widget.myComment != null &&
        (widget.myComment!.rate > 0 ||
            widget.myComment!.comment.trim().isNotEmpty);

    // Initial loading
    if (_comments.isEmpty && _isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(accentColor),
          ),
        ),
      );
    }

    // Error on first load
    if (_comments.isEmpty && _error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Ionicons.alert_circle_outline,
                  color: secondaryTextColor, size: 32),
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: secondaryTextColor, fontSize: 13)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadComments,
                child: Text('重试', style: TextStyle(color: accentColor)),
              ),
            ],
          ),
        ),
      );
    }

    // Empty (no comments from API and no personal comment)
    if (_comments.isEmpty && !hasMyComment) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('暂无短评',
              style: TextStyle(color: secondaryTextColor, fontSize: 13)),
        ),
      );
    }

    final valueStyle = TextStyle(
        color: textColor.withOpacity(0.85), fontSize: 13, height: 1.5);

    final int totalItemCount = _comments.length + (hasMyComment ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('全部短评',
                style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.5)),
            if (widget.onEditRating != null)
              HoverScaleTextButton(
                onPressed: widget.onEditRating,
                idleColor: textColor.withOpacity(0.72),
                hoverColor: accentColor,
                hoverScale: 1.08,
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Ionicons.chatbubble_outline, size: 15),
                    const SizedBox(width: 4),
                    const Text(
                      '评论',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          key: ValueKey('${widget.subjectId}_${widget.commentsVersion}'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: totalItemCount,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            // "我的评论" as first item
            if (hasMyComment && index == 0) {
              final my = widget.myComment!;
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: accentColor.withOpacity(0.25), width: 0.8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: textColor.withOpacity(0.1),
                      backgroundImage: my.avatarUrl.isNotEmpty
                          ? NetworkImage(_proxiedImageUrl(my.avatarUrl))
                          : null,
                      child: my.avatarUrl.isEmpty
                          ? Icon(Ionicons.person,
                              size: 18, color: secondaryTextColor)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  my.nickname.isNotEmpty ? my.nickname : '我',
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                _formatRelativeTime(my.updatedAt),
                                style: TextStyle(
                                    color: secondaryTextColor, fontSize: 11),
                              ),
                            ],
                          ),
                          if (my.rate > 0) ...[
                            const SizedBox(height: 3),
                            _buildMiniStars(my.rate, accentColor, mutedColor),
                          ],
                          if (my.comment.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(my.comment, style: valueStyle),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            final int commentIndex = hasMyComment ? index - 1 : index;
            final comment = _comments[commentIndex];

            final card = Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: textColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: textColor.withOpacity(0.12), width: 0.8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: textColor.withOpacity(0.1),
                    backgroundImage: comment.avatarUrl.isNotEmpty
                        ? NetworkImage(_proxiedImageUrl(comment.avatarUrl))
                        : null,
                    child: comment.avatarUrl.isEmpty
                        ? Icon(Ionicons.person,
                            size: 18, color: secondaryTextColor)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                comment.nickname.isNotEmpty
                                    ? comment.nickname
                                    : comment.username,
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _formatRelativeTime(comment.updatedAt),
                              style: TextStyle(
                                  color: secondaryTextColor, fontSize: 11),
                            ),
                          ],
                        ),
                        if (comment.rate > 0) ...[
                          const SizedBox(height: 3),
                          _buildMiniStars(
                              comment.rate, accentColor, mutedColor),
                        ],
                        if (comment.comment.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(comment.comment, style: valueStyle),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );

            return card;
          },
        ),
        // Loading more indicator
        if (_isLoading && _comments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
            ),
          ),
        // Error loading more
        if (_error != null && _comments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: TextButton(
                onPressed: _loadComments,
                child: Text('加载失败，点击重试',
                    style: TextStyle(color: accentColor, fontSize: 12)),
              ),
            ),
          ),
      ],
    );
  }
}
