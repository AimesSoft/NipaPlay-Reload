import 'dart:io'; // Required for File
import 'dart:ui';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:nipaplay/widgets/nipaplay_theme/cached_network_image_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FluentAnimeCard extends StatefulWidget {
  final String name;
  final String imageUrl; // Can be a network URL or a local file path
  final VoidCallback onTap;
  final bool isOnAir;
  final String? source; // 来源信息（本地/Emby/Jellyfin）
  final double? rating; // 评分信息
  final Map<String, dynamic>? ratingDetails; // 详细评分信息
  final String? description; // 简介
  final int? year; // 年份

  const FluentAnimeCard({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
    this.isOnAir = false,
    this.source,
    this.rating,
    this.ratingDetails,
    this.description,
    this.year,
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
  State<FluentAnimeCard> createState() => _FluentAnimeCardState();
}

class _FluentAnimeCardState extends State<FluentAnimeCard> with TickerProviderStateMixin {
  bool _isHovering = false;
  late String _displayImageUrl;
  late AnimationController _scaleController;
  late AnimationController _elevationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  @override
  void initState() {
    super.initState();
    if (kIsWeb && widget.imageUrl.startsWith('http')) {
      _displayImageUrl = '/api/image_proxy?url=${Uri.encodeComponent(widget.imageUrl)}';
    } else {
      _displayImageUrl = widget.imageUrl;
    }

    // 创建动画控制器
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _elevationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // 创建动画
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOut,
    ));

    _elevationAnimation = Tween<double>(
      begin: 0.0,
      end: 8.0,
    ).animate(CurvedAnimation(
      parent: _elevationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _elevationController.dispose();
    super.dispose();
  }

  // 格式化评分信息用于显示
  String _formatRatingInfo() {
    List<String> ratingInfo = [];
    
    // 添加年份信息
    if (widget.year != null) {
      ratingInfo.add('${widget.year}');
    }
    
    // 添加Bangumi评分（优先显示）
    if (widget.ratingDetails != null && widget.ratingDetails!.containsKey('Bangumi评分')) {
      final bangumiRating = widget.ratingDetails!['Bangumi评分'];
      if (bangumiRating is num && bangumiRating > 0) {
        ratingInfo.add('${bangumiRating.toStringAsFixed(1)}分');
      }
    }
    // 如果没有Bangumi评分，使用通用评分
    else if (widget.rating != null && widget.rating! > 0) {
      ratingInfo.add('${widget.rating!.toStringAsFixed(1)}分');
    }
    
    return ratingInfo.isNotEmpty ? ratingInfo.join(' • ') : '';
  }

  // Fluent风格的占位图组件
  Widget _buildPlaceholder(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.resources.controlStrokeColorSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Icon(
          FluentIcons.photo2,
          color: theme.inactiveColor,
          size: 32,
        ),
      ),
    );
  }

  // 构建图片组件
  Widget _buildImage(BuildContext context) {
    if (_displayImageUrl.isEmpty) {
      return _buildPlaceholder(context);
    }

    Widget imageWidget;
    
    // 本地文件路径
    if (!_displayImageUrl.startsWith('http') && !kIsWeb) {
      imageWidget = material.Image.file(
        File(_displayImageUrl),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
      );
    } else {
      // 网络图片
      imageWidget = CachedNetworkImageWidget(
        imageUrl: _displayImageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error) => _buildPlaceholder(context),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      child: imageWidget,
    );
  }

  void _onPointerEnter() {
    if (!_isHovering) {
      setState(() => _isHovering = true);
      _scaleController.forward();
      _elevationController.forward();
    }
  }

  void _onPointerExit() {
    if (_isHovering) {
      setState(() => _isHovering = false);
      _scaleController.reverse();
      _elevationController.reverse();
    }
  }



  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    
    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => _onPointerEnter(),
        onExit: (_) => _onPointerExit(),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: Listenable.merge([_scaleAnimation, _elevationAnimation]),
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: 180,
                  height: 270,
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      // Fluent UI 风格的阴影
                      BoxShadow(
                        color: theme.shadowColor.withOpacity(0.14),
                        blurRadius: 4 + _elevationAnimation.value,
                        offset: Offset(0, 2 + _elevationAnimation.value / 2),
                      ),
                      BoxShadow(
                        color: theme.shadowColor.withOpacity(0.12),
                        blurRadius: 8 + _elevationAnimation.value * 2,
                        offset: Offset(0, 4 + _elevationAnimation.value),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: BackdropFilter(
                      // Fluent Design 的 Acrylic 效果
                      filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.micaBackgroundColor.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _isHovering 
                                ? theme.accentColor.withOpacity(0.5)
                                : (theme.brightness == Brightness.dark
                                    ? theme.resources.controlStrokeColorSecondary.withOpacity(0.3)
                                    : theme.resources.controlStrokeColorDefault.withOpacity(0.8)),
                            width: _isHovering ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          children: [
                            // 图片区域 (70% 高度)
                            Expanded(
                              flex: 7,
                              child: Stack(
                                children: [
                                  // 主图片
                                  Positioned.fill(
                                    child: _buildImage(context),
                                  ),
                                  
                                  // 悬停时的覆盖层
                                  if (_isHovering)
                                    Positioned.fill(
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        decoration: BoxDecoration(
                                          color: theme.resources.systemFillColorCritical.withOpacity(0.1),
                                          borderRadius: const BorderRadius.vertical(
                                            top: Radius.circular(4),
                                          ),
                                        ),
                                        child: Center(
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: theme.accentColor,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: theme.accentColor.withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              FluentIcons.play,
                                              color: material.Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  
                                  // 连载状态标签
                                  if (widget.isOnAir)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF107C10), // Fluent UI 的绿色
                                          borderRadius: BorderRadius.circular(2),
                                          boxShadow: [
                                            BoxShadow(
                                              color: material.Colors.black.withOpacity(0.2),
                                              blurRadius: 2,
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          '连载中',
                                          style: theme.typography.caption?.copyWith(
                                            color: material.Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  
                                  // 来源标签
                                  if (widget.source != null)
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.accentColor.withOpacity(0.9),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                        child: Text(
                                          widget.source!,
                                          style: theme.typography.caption?.copyWith(
                                            color: material.Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            
                            // 信息区域 (30% 高度)
                            Expanded(
                              flex: 3,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  // 自适应背景颜色，夜间模式友好
                                  color: theme.brightness == Brightness.dark 
                                      ? theme.resources.solidBackgroundFillColorSecondary.withOpacity(0.9)
                                      : theme.cardColor.withOpacity(0.8),
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(4),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // 标题
                                    Expanded(
                                      child: Text(
                                        widget.name,
                                        style: theme.typography.body?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    
                                    // 评分信息
                                    if (_formatRatingInfo().isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatRatingInfo(),
                                        style: theme.typography.caption?.copyWith(
                                          color: theme.inactiveColor,
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}