import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

/// Cupertino风格的番剧卡片控件
/// 专门用于显示共享媒体库中的番剧信息
class CupertinoAnimeCard extends StatelessWidget {
  /// 番剧标题
  final String title;

  /// 封面图片URL
  final String? imageUrl;

  /// 剧集标签（例如："共12集"）
  final String episodeLabel;

  /// 最后观看时间
  final DateTime? lastWatchTime;

  /// 点击回调
  final VoidCallback onTap;

  /// 是否显示加载指示器
  final bool isLoading;

  /// 来源标签（例如："共享媒体库"）
  final String? sourceLabel;

  /// 评分（0-10）
  final double? rating;

  const CupertinoAnimeCard({
    super.key,
    required this.title,
    this.imageUrl,
    required this.episodeLabel,
    this.lastWatchTime,
    required this.onTap,
    this.isLoading = false,
    this.sourceLabel,
    this.rating,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedCardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final secondaryLabelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: resolvedCardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧：封面图片
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 120,
                height: 168,
                child: _buildPosterImage(context),
              ),
            ),
            const SizedBox(width: 12),
            // 右侧：文字信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 上部分：标题和来源/评分
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 来源和评分
                      Row(
                        children: [
                          if (sourceLabel != null) ...[
                            Text(
                              '来源：$sourceLabel',
                              style: TextStyle(
                                fontSize: 13,
                                color: secondaryLabelColor,
                              ),
                            ),
                            if (rating != null && rating! > 0) const SizedBox(width: 12),
                          ],
                          if (rating != null && rating! > 0) ...[
                            Icon(
                              CupertinoIcons.star_fill,
                              size: 13,
                              color: CupertinoDynamicColor.resolve(
                                CupertinoColors.systemYellow,
                                context,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rating!.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: labelColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  // 下部分：剧集信息和观看时间
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 剧集信息
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.play_rectangle,
                            size: 14,
                            color: secondaryLabelColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            episodeLabel,
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryLabelColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 最后观看时间
                      if (lastWatchTime != null)
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.time,
                              size: 14,
                              color: secondaryLabelColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _formatDateTime(lastWatchTime!),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: secondaryLabelColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建封面图片
  Widget _buildPosterImage(BuildContext context) {
    final placeholderColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemFill,
      context,
    );

    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        color: placeholderColor,
        child: const Center(
          child: Icon(
            CupertinoIcons.photo_on_rectangle,
            size: 26,
            color: CupertinoColors.inactiveGray,
          ),
        ),
      );
    }

    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: placeholderColor,
          child: const Center(
            child: Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: CupertinoColors.systemOrange,
              size: 24,
            ),
          ),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return Container(
          color: placeholderColor,
          child: Center(
            child: CupertinoActivityIndicator(
              radius: 12,
              color: CupertinoColors.inactiveGray,
            ),
          ),
        );
      },
      // 使用低质量过滤以提高性能
      filterQuality: FilterQuality.low,
    );
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      final formatter = DateFormat('MM-dd HH:mm');
      return formatter.format(time.toLocal());
    }
  }
}
