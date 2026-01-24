import 'dart:io'; // Required for File
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_tooltip_bubble.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

class AnimeCard extends StatefulWidget {
  final String name;
  final String imageUrl; // Can be a network URL or a local file path
  final VoidCallback onTap;
  final bool isOnAir;
  final String? source; // 新增：来源信息（本地/Emby/Jellyfin）
  final double? rating; // 新增：评分信息
  final Map<String, dynamic>? ratingDetails; // 新增：详细评分信息
  final bool delayLoad; // 新增：延迟加载参数
  final bool useLegacyImageLoadMode; // 新增：是否启用旧版图片加载模式
  final bool enableBackgroundBlur; // 新增：是否启用卡片背景模糊
  final bool enableShadow; // 新增：是否启用阴影
  final double backgroundBlurSigma; // 新增：背景模糊强度（sigma）
  final bool enableBackdropImage; // 新增：是否启用背景图层

  const AnimeCard({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
    this.isOnAir = false,
    this.source, // 新增：来源信息
    this.rating, // 新增：评分信息
    this.ratingDetails, // 新增：详细评分信息
    this.delayLoad = false, // 默认不延迟
    this.useLegacyImageLoadMode = false, // 默认关闭
    this.enableBackgroundBlur = true,
    this.enableShadow = true,
    this.backgroundBlurSigma = 20.0,
    this.enableBackdropImage = true,
  });

  // 根据filePath获取来源信息
  static String getSourceFromFilePath(String filePath) {
    if (filePath.contains('/Emby/')) {
      return 'Emby';
    } else if (filePath.contains('/Jellyfin/')) {
      return 'Jellyfin';
    } else {
      return '本地文件';
    }
  }

  @override
  State<AnimeCard> createState() => _AnimeCardState();
}

class _AnimeCardState extends State<AnimeCard> {
  late String _displayImageUrl;

  @override
  void initState() {
    super.initState();
    _updateDisplayImageUrl();
  }

  @override
  void didUpdateWidget(covariant AnimeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _updateDisplayImageUrl();
    }
  }

  void _updateDisplayImageUrl() {
    if (kIsWeb && widget.imageUrl.startsWith('http')) {
      _displayImageUrl =
          '/api/image_proxy?url=${Uri.encodeComponent(widget.imageUrl)}';
    } else {
      _displayImageUrl = widget.imageUrl;
    }
  }

  // 格式化评分信息用于显示
  String _formatRatingInfo() {
    List<String> ratingInfo = [];
    
    // 添加来源信息
    if (widget.source != null) {
      ratingInfo.add('来源：${widget.source}');
    }
    
    // 添加Bangumi评分（优先显示）
    if (widget.ratingDetails != null && widget.ratingDetails!.containsKey('Bangumi评分')) {
      final bangumiRating = widget.ratingDetails!['Bangumi评分'];
      if (bangumiRating is num && bangumiRating > 0) {
        ratingInfo.add('Bangumi评分：${bangumiRating.toStringAsFixed(1)}');
      }
    }
    // 如果没有Bangumi评分，使用通用评分
    else if (widget.rating != null && widget.rating! > 0) {
      ratingInfo.add('评分：${widget.rating!.toStringAsFixed(1)}');
    }
    
    // 添加其他平台评分（排除Bangumi评分）
    if (widget.ratingDetails != null) {
      final otherRatings = widget.ratingDetails!.entries
          .where((entry) => entry.key != 'Bangumi评分' && entry.value is num && (entry.value as num) > 0)
          .take(2) // 最多显示2个其他平台评分
          .map((entry) {
            String siteName = entry.key;
            if (siteName.endsWith('评分')) {
              siteName = siteName.substring(0, siteName.length - 2);
            }
            return '$siteName：${(entry.value as num).toStringAsFixed(1)}';
          });
      ratingInfo.addAll(otherRatings);
    }
    
    return ratingInfo.isNotEmpty ? ratingInfo.join('\n') : '';
  }

  // 占位图组件
  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Colors.grey[800]?.withValues(alpha: 0.5),
      child: const Center(
        child: Icon(
          Ionicons.image_outline,
          color: Colors.white30,
          size: 40,
        ),
      ),
    );
  }
  
  // 创建图片组件（网络图片或本地文件）
  Widget _buildImage(BuildContext context, bool isBackground) {
    if (widget.imageUrl.isEmpty) {
      // 没有图片URL，使用占位符
      return _buildPlaceholder(context);
    } else if (widget.imageUrl.startsWith('http')) {
      // 网络图片，使用缓存组件，为背景图和主图使用不同的key
      return CachedNetworkImageWidget(
        key: ValueKey('${widget.imageUrl}_${isBackground ? 'bg' : 'main'}'),
        imageUrl: _displayImageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // 网格场景禁用淡入动画，减少saveLayer
        fadeDuration: Duration.zero,
        delayLoad: widget.delayLoad, // 使用延迟加载参数
        loadMode: CachedImageLoadMode.legacy, // 番剧卡片统一使用legacy模式，避免海报突然切换
        errorBuilder: (context, error) {
          return _buildPlaceholder(context);
        },
      );
    } else {
      // 本地文件 - 为每个实例创建独立的key
      return Image.file(
        File(widget.imageUrl),
        key: ValueKey('${widget.imageUrl}_${isBackground ? 'bg' : 'main'}'),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: isBackground ? 150 : 300, // 背景图可以更小以节省内存
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder(context);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppearanceSettingsProvider>();
    final bool enableBlur = settings.enableWidgetBlurEffect;

    final Widget imageCard = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // 加大圆角
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1), // 减淡边框
          width: 0.5,
        ),
        boxShadow: widget.enableShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 底层：模糊的封面图背景
          if (widget.enableBackdropImage)
            Positioned.fill(
              child: Transform.rotate(
                angle: 3.14159, // 180度（π弧度）
                child: (enableBlur && widget.enableBackgroundBlur)
                    ? ImageFiltered(
                        imageFilter: ImageFilter.blur(
                            sigmaX: widget.backgroundBlurSigma,
                            sigmaY: widget.backgroundBlurSigma),
                        child: _buildImage(context, true),
                      )
                    : _buildImage(context, true),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
              ),
            ),

          // 中间层：半透明遮罩
          Positioned.fill(
            child: Container(
              color: const Color.fromARGB(255, 252, 252, 252)
                  .withValues(alpha: 0.05), // 更淡的遮罩
            ),
          ),

          // 顶层：图片
          _buildImage(context, false),

          // 状态图标 (移至右上角)
          if (widget.isOnAir)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  Ionicons.time_outline,
                  color: Colors.greenAccent,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    );

    final Widget card = GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 图片部分 (占据大部分高度)
          Expanded(
            child: imageCard,
          ),
          
          const SizedBox(height: 8),
          
          // 标题部分
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Text(
              widget.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    height: 1.3,
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );

    // 如果有来源或评分信息，则用HoverTooltipBubble包装
    final tooltipText = _formatRatingInfo();
    if (tooltipText.isNotEmpty) {
      return HoverTooltipBubble(
        text: tooltipText,
        showDelay: const Duration(milliseconds: 400),
        hideDelay: const Duration(milliseconds: 100),
        child: card,
      );
    } else {
      return card;
    }
  }
} 
