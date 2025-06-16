import 'dart:io'; // Required for File
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/cached_network_image_widget.dart';

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
  
  // 创建图片组件（网络图片或本地文件）
  Widget _buildImage(BuildContext context, bool isBackground) {
    if (imageUrl.isEmpty) {
      // 没有图片URL，使用占位符
      return _buildPlaceholder(context);
    } else if (imageUrl.startsWith('http')) {
      // 网络图片，使用缓存组件，为背景图和主图使用不同的key
      return CachedNetworkImageWidget(
        key: ValueKey('${imageUrl}_${isBackground ? 'bg' : 'main'}'),
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error) {
          return _buildPlaceholder(context);
        },
      );
    } else {
      // 本地文件 - 为每个实例创建独立的key
      return Image.file(
        File(imageUrl),
        key: ValueKey('${imageUrl}_${isBackground ? 'bg' : 'main'}'),
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
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // 底层：模糊的封面图背景
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 20,
                    sigmaY: 20,
                  ),
                  child: _buildImage(context, true),
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
                    flex: 7,
                    child: _buildImage(context, false),
                  ),
                  // 标题部分
                  Expanded(
                    flex: 3,
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
                  // 状态图标
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
            ],
          ),
        ),
      ),
    );
  }
} 