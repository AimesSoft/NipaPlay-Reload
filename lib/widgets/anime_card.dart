import 'dart:io'; // Required for File
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/cached_network_image_widget.dart'; // Using package import

class AnimeCard extends StatelessWidget {
  final String name;
  final String imageUrl; // Can be a network URL or a local file path
  final VoidCallback onTap;
  final bool isOnAir;

  const AnimeCard({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
    this.isOnAir = false,
  });

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

  @override
  Widget build(BuildContext context) {
    // 确定图片来源和处理方式
    Widget imageWidget;
    
    if (imageUrl.isEmpty) {
      // 没有图片URL，使用占位符
      imageWidget = _buildPlaceholder(context);
    } else if (imageUrl.startsWith('http')) {
      // 网络图片，使用缓存组件
      imageWidget = CachedNetworkImageWidget(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (context, error) {
          return _buildPlaceholder(context);
        },
      );
    } else {
      // 本地文件，使用异步加载，避免在主线程进行文件检查
      // 直接使用Image.file，如果文件不存在会自动显示错误构建器
      imageWidget = Image.file(
        File(imageUrl),
        fit: BoxFit.cover,
        width: double.infinity,
        cacheWidth: 300, // 优化内存使用和图片加载
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder(context);
        },
      );
    }

    // 使用RepaintBoundary包装整个卡片，减少不必要的重绘
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            // 使用半透明背景
            color: Colors.black.withOpacity(0.5),
            // 添加渐变效果模拟毛玻璃的高级感，但不使用真正的毛玻璃效果
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.05),
                Colors.white.withOpacity(0.02),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            // 添加精细的边框增强立体感
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 7,
                child: imageWidget, // Use the determined image widget
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(6.0),
                  child: Center(
                    child: Text(
                      name,
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
              if (isOnAir)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0, right: 4.0),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Icon(Ionicons.time_outline, color: Colors.greenAccent.withOpacity(0.8), size: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
} 