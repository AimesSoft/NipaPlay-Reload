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

  const CupertinoAnimeCard({
    super.key,
    required this.title,
    this.imageUrl,
    required this.episodeLabel,
    this.lastWatchTime,
    required this.onTap,
    this.isLoading = false,
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
        decoration: BoxDecoration(
          color: resolvedCardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图片区域
            AspectRatio(
              aspectRatio: 7 / 10,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: _buildPosterImage(context),
              ),
            ),
            // 信息区域
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 剧集信息
                    Text(
                      episodeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryLabelColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    // 最后观看时间
                    if (lastWatchTime != null)
                      Text(
                        '最近观看 ${_formatDateTime(lastWatchTime!)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: secondaryLabelColor.withOpacity(0.8),
                        ),
                      ),
                  ],
                ),
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
    final formatter = DateFormat('MM-dd HH:mm');
    return formatter.format(time.toLocal());
  }
}
