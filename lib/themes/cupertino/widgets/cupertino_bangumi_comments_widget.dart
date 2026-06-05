import 'package:flutter/foundation.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/models/bangumi_comment_model.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
import 'package:nipaplay/services/server_connectivity_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/bangumi_comments_widget.dart'
    show BangumiMyCommentData;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nipaplay/services/web_remote_access_service.dart';

class CupertinoBangumiCommentsWidget extends StatefulWidget {
  final int? subjectId;
  final int dandanplayId;
  final VoidCallback? onEditRating;
  final BangumiMyCommentData? myComment;
  final int currentUserId;
  final int commentsVersion;
  final ValueChanged<int>? onMyCommentTimestamp;

  const CupertinoBangumiCommentsWidget({
    super.key,
    required this.subjectId,
    this.dandanplayId = 0,
    this.onEditRating,
    this.myComment,
    this.currentUserId = 0,
    this.commentsVersion = 0,
    this.onMyCommentTimestamp,
  });

  @override
  State<CupertinoBangumiCommentsWidget> createState() =>
      CupertinoBangumiCommentsWidgetState();
}

class CupertinoBangumiCommentsWidgetState
    extends State<CupertinoBangumiCommentsWidget> {
  final List<BangumiComment> _comments = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMore = true;
  bool _usingFallback = false;
  int _currentOffset = 0;
  int _currentPage = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.subjectId != null || widget.dandanplayId != 0) {
      _loadComments();
    }
  }

  @override
  void didUpdateWidget(CupertinoBangumiCommentsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId ||
        oldWidget.dandanplayId != widget.dandanplayId ||
        oldWidget.commentsVersion != widget.commentsVersion) {
      _isLoading = false;
      _comments.clear();
      _currentOffset = 0;
      _currentPage = 0;
      _usingFallback = false;
      _hasMore = true;
      _error = null;
      if (widget.subjectId != null || widget.dandanplayId != 0) {
        _loadComments();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll > 0 && currentScroll >= maxScroll - 200) {
      tryLoadMore();
    }
  }

  Future<void> _loadComments() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (widget.subjectId == null && widget.dandanplayId == 0) {
        setState(() => _isLoading = false);
        return;
      }

      final int requestedSubjectId = widget.subjectId ?? 0;
      Map<String, dynamic> result;

      final connectivity = ServerConnectivityService.instance;
      final bangumiUnavailable = connectivity.bangumiAvailable == false;
      final dandanplayAvailable = connectivity.dandanplayAvailable == true;

      if (!_usingFallback && requestedSubjectId != 0 && !(bangumiUnavailable && dandanplayAvailable && widget.dandanplayId != 0)) {
        debugPrint(
            '[Cupertino Comments] 尝试Bangumi主接口, subjectId=$requestedSubjectId, offset=$_currentOffset');
        result = await BangumiApiService.getSubjectComments(
          requestedSubjectId,
          offset: _currentOffset,
        );

        bool shouldFallback = false;
        String fallbackReason = '';

        if (result['success'] != true) {
          shouldFallback = true;
          fallbackReason = result['isTimeout'] == true
              ? 'Bangumi请求超时(4s)'
              : 'Bangumi请求失败: ${result['message']}';
        } else {
          final data = result['data'];
          final list = (data is Map)
              ? (data['data'] as List? ?? data['list'] as List? ?? [])
              : [];
          if (list.isEmpty && _currentOffset == 0) {
            shouldFallback = true;
            fallbackReason = 'Bangumi返回空列表';
          }
        }

        if (shouldFallback && widget.dandanplayId != 0 && dandanplayAvailable != false) {
          debugPrint(
              '[Cupertino Comments] $fallbackReason，回退到Dandanplay, dandanplayId=${widget.dandanplayId}');
          _usingFallback = true;
          _currentPage = 0;
          result = await BangumiApiService.getSubjectCommentsFallback(
            widget.dandanplayId,
            page: _currentPage,
          );
          debugPrint(
              '[Cupertino Comments] Dandanplay回退结果: success=${result['success']}');
        } else if (shouldFallback && widget.dandanplayId != 0 && dandanplayAvailable == false) {
          debugPrint(
              '[Cupertino Comments] $fallbackReason，且Dandanplay不可用，跳过回退');
        } else if (shouldFallback && widget.dandanplayId == 0) {
          debugPrint(
              '[Cupertino Comments] $fallbackReason，但无dandanplayId可用，无法回退');
        }
      } else if (widget.dandanplayId != 0) {
        if (bangumiUnavailable && dandanplayAvailable) {
          debugPrint('[Cupertino Comments] Bangumi不可用但Dandanplay可用，跳过Bangumi直接回退, dandanplayId=${widget.dandanplayId}');
        }
        _usingFallback = true;
        debugPrint(
            '[Cupertino Comments] 使用Dandanplay回退接口, dandanplayId=${widget.dandanplayId}, page=$_currentPage');
        result = await BangumiApiService.getSubjectCommentsFallback(
          widget.dandanplayId,
          page: _currentPage,
        );
      } else {
        debugPrint(
            '[Cupertino Comments] 无可用数据源, subjectId=$requestedSubjectId, dandanplayId=${widget.dandanplayId}');
        setState(() => _isLoading = false);
        return;
      }

      if (!mounted) return;
      if (requestedSubjectId != 0 && widget.subjectId != requestedSubjectId) {
        return;
      }

      if (result['success'] == true) {
        final data = result['data'];
        final list = (data['data'] as List?) ?? (data['list'] as List?) ?? [];
        final total = data['total'] as int? ?? 0;
        final bool isDandanplaySource = result['source'] == 'dandanplay';

        List<BangumiComment> newComments;
        if (isDandanplaySource) {
          newComments = list
              .whereType<Map<String, dynamic>>()
              .map((e) => DandanplayComment.fromJson(e).toBangumiComment())
              .toList();
        } else {
          newComments = list
              .map((e) => BangumiComment.fromJson(e as Map<String, dynamic>))
              .toList();
        }

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

        setState(() {
          _comments.addAll(newComments);
          if (_usingFallback) {
            _currentPage++;
            final bool dandanplayHasMore = data['hasMore'] as bool? ?? true;
            _hasMore =
                isDandanplaySource ? dandanplayHasMore : newComments.isNotEmpty;
          } else {
            _currentOffset += list.length;
            _hasMore = _currentOffset < total;
          }
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

  /// Called by the parent when the user scrolls near the bottom.
  /// Checks state internally to avoid duplicate requests.
  void tryLoadMore() {
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
        stars.add(Icon(CupertinoIcons.star_fill, size: 14, color: accentColor));
      } else if (i == fullStars && hasHalf) {
        stars.add(Icon(CupertinoIcons.star_lefthalf_fill,
            size: 14, color: accentColor));
      } else {
        stars.add(Icon(CupertinoIcons.star, size: 14, color: mutedColor));
      }
      if (i < 4) stars.add(const SizedBox(width: 1));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: stars);
  }

  Widget _buildAvatar(String avatarUrl, Color fallbackColor, Color iconColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 36,
        height: 36,
        child: avatarUrl.isNotEmpty
            ? (avatarUrl.startsWith('assets/')
                ? Image.asset(avatarUrl, fit: BoxFit.cover)
                : Image.network(
                    _proxiedImageUrl(avatarUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: fallbackColor,
                      child: Icon(CupertinoIcons.person_fill,
                          size: 18, color: iconColor),
                    ),
                  ))
            : Container(
                color: fallbackColor,
                child: Icon(CupertinoIcons.person_fill,
                    size: 18, color: iconColor),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemPurple,
      context,
    );
    final textColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryTextColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final mutedColor = accentColor.withOpacity(0.35);
    final systemFillColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemFill, context);

    final bool isDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;

    if (widget.subjectId == null && widget.dandanplayId == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('当前番剧未关联Bangumi条目，无法加载评论',
              style: TextStyle(color: secondaryTextColor, fontSize: 13)),
        ),
      );
    }

    final bool hasMyComment = widget.myComment != null &&
        (widget.myComment!.rate > 0 ||
            widget.myComment!.comment.trim().isNotEmpty);

    if (_comments.isEmpty && _isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }

    if (_comments.isEmpty && _error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.exclamationmark_circle,
                  color: secondaryTextColor, size: 32),
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: secondaryTextColor, fontSize: 13)),
              const SizedBox(height: 12),
              CupertinoButton(
                onPressed: _loadComments,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('重试',
                    style: TextStyle(color: accentColor, fontSize: 14)),
              ),
            ],
          ),
        ),
      );
    }

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

    final int commentItemCount = _comments.length + (hasMyComment ? 1 : 0);

    // 布局索引：
    // 0: 标题行
    // 1: 间距
    // 2 (如果hasMyComment): 我的评论
    // 2+myCommentOffset ~ 2+myCommentOffset+_comments.length-1: 评论列表
    // 最后: 底部加载/错误
    const int headerCount = 2;
    final int myCommentCount = hasMyComment ? 1 : 0;
    final bool hasFooter = _isLoading || (_error != null && _comments.isNotEmpty);
    final int totalItems = headerCount + myCommentCount + _comments.length + (hasFooter ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: totalItems,
      itemBuilder: (context, index) {
        // 标题行
        if (index == 0) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('全部短评',
                  style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.5)),
              if (widget.onEditRating != null)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minSize: 0,
                  onPressed: widget.onEditRating,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.chat_bubble,
                          size: 15, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        '评论',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }

        // 间距
        if (index == 1) {
          return const SizedBox(height: 12);
        }

        // 我的评论
        if (hasMyComment && index == 2) {
          final my = widget.myComment!;
          return Padding(
            padding: EdgeInsets.only(bottom: commentItemCount > 1 ? 8 : 0),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: accentColor.withOpacity(0.3), width: 0.8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAvatar(
                      my.avatarUrl, systemFillColor, secondaryTextColor),
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
                                  fontWeight: FontWeight.w600,
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
            ),
          );
        }

        // 底部加载/错误
        if (index == totalItems - 1 && hasFooter) {
          if (_isLoading) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CupertinoActivityIndicator(radius: 10),
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: CupertinoButton(
                onPressed: _loadComments,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Text('加载失败，点击重试',
                    style: TextStyle(color: accentColor, fontSize: 12)),
              ),
            ),
          );
        }

        // 评论列表项
        final int commentIndex = index - headerCount - myCommentCount;
        final comment = _comments[commentIndex];
        final bool isLast = commentIndex == _comments.length - 1 && !_hasMore && _error == null;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: textColor.withOpacity(isDark ? 0.08 : 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: textColor.withOpacity(0.12), width: 0.8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatar(comment.avatarUrl, systemFillColor,
                    secondaryTextColor),
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
                                fontWeight: FontWeight.w600,
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
          ),
        );
      },
    );
  }
}
