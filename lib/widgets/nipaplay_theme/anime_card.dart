import 'dart:io'; // Required for File
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/nipaplay_theme/cached_network_image_widget.dart';
import 'package:nipaplay/widgets/nipaplay_theme/hover_tooltip_bubble.dart';
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
  late final String _displayImageUrl;

  @override
  void initState() {
    super.initState();
    if (kIsWeb && widget.imageUrl.startsWith('http')) {
      _displayImageUrl = '/api/image_proxy?url=${Uri.encodeComponent(widget.imageUrl)}';
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
      color: Colors.grey[800]?.withOpacity(0.5),
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
        delayLoad: widget.delayLoad, // 使用延迟加载参数
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
    final Widget card = RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // 底层：模糊的封面图背景
              Positioned.fill(
                child: Transform.rotate(
                  angle: 3.14159, // 180度（π弧度）
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 20 : 0,
                      sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 20 : 0,
                    ),
                    child: _buildImage(context, true),
                  ),
                ),
              ),
              
              // 中间层：半透明遮罩，提高可读性
              Positioned.fill(
                child: Container(
                  color: const Color.fromARGB(255, 252, 252, 252).withOpacity(0.1),
                ),
              ),
              
              // 顶层：内容
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 图片部分
                  Expanded(
                    flex: 8,
                    child: _buildImage(context, false),
                  ),
                  // 标题部分
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.1),
                            Colors.black.withOpacity(0.3),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(6.0),
                      child: Center(
                        child: Text(
                          widget.name,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontSize: 12,
                                height: 1.2,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  // 状态图标
                  if (widget.isOnAir)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0, right: 4.0),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Icon(Ionicons.time_outline, color: Colors.greenAccent.withOpacity(0.8), size: 12),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
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