part of dashboard_home_page;

// 推荐内容数据模型
class RecommendedItem {
  final String id;
  final String title;
  final String subtitle;
  final String? backgroundImageUrl;
  final String? logoImageUrl;
  final RecommendedItemSource source;
  final double? rating;
  final bool isLowRes; // 新增：标记是否为低分辨率封面

  RecommendedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.backgroundImageUrl,
    this.logoImageUrl,
    required this.source,
    this.rating,
    this.isLowRes = false,
  });

  // 用于更新图片质量的方法
  RecommendedItem copyWith({
    String? subtitle,
    String? backgroundImageUrl,
    String? logoImageUrl,
    bool? isLowRes,
  }) {
    return RecommendedItem(
      id: id,
      title: title,
      subtitle: subtitle ?? this.subtitle,
      backgroundImageUrl: backgroundImageUrl ?? this.backgroundImageUrl,
      logoImageUrl: logoImageUrl ?? this.logoImageUrl,
      source: source,
      rating: rating,
      isLowRes: isLowRes ?? this.isLowRes,
    );
  }
}

enum RecommendedItemSource {
  jellyfin,
  emby,
  local,
  dandanplay,
  placeholder,
}

// 本地动画项目数据模型
class LocalAnimeItem {
  final int animeId;
  final String animeName;
  final String? imageUrl;
  final String? backdropImageUrl;
  final DateTime addedTime; // 改为添加时间
  final WatchHistoryItem latestEpisode;

  LocalAnimeItem({
    required this.animeId,
    required this.animeName,
    this.imageUrl,
    this.backdropImageUrl,
    required this.addedTime, // 改为添加时间
    required this.latestEpisode,
  });
}

// 内部辅助类处理悬浮放大
class _HoverScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  const _HoverScaleButton({
    required this.child,
    this.onTap,
    this.enabled = true,
  });

  @override
  State<_HoverScaleButton> createState() => _HoverScaleButtonState();
}

class _HoverScaleButtonState extends State<_HoverScaleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFFFF2E55);
    final isEnabled = widget.enabled;
    final baseIconTheme = Theme.of(context).iconTheme;
    final Color? iconColor =
        _isHovered && isEnabled ? activeColor : baseIconTheme.color;

    return MouseRegion(
      onEnter: (_) => isEnabled ? setState(() => _isHovered = true) : null,
      onExit: (_) => isEnabled ? setState(() => _isHovered = false) : null,
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _isHovered && isEnabled ? 1.3 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: IconTheme(
            data: baseIconTheme.copyWith(color: iconColor),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
