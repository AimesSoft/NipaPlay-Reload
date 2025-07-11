import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/image_cache_manager.dart';
import 'loading_placeholder.dart';

class CachedNetworkImageWidget extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, Object)? errorBuilder;
  final bool shouldRelease;
  final Duration fadeDuration;

  const CachedNetworkImageWidget({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
    this.shouldRelease = true,
    this.fadeDuration = const Duration(milliseconds: 300),
  });

  @override
  State<CachedNetworkImageWidget> createState() => _CachedNetworkImageWidgetState();
}

class _CachedNetworkImageWidgetState extends State<CachedNetworkImageWidget> {
  Future<ui.Image>? _imageFuture;
  String? _currentUrl;
  bool _isImageLoaded = false;
  bool _isDisposed = false;
  ui.Image? _cachedImage; // 缓存图片引用，避免重复访问

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedNetworkImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      // 不再在这里释放图片，改为由缓存管理器统一管理
      _cachedImage = null; // 清除本地缓存的图片引用
      setState(() {
        _isImageLoaded = false;
      });
      _loadImage();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cachedImage = null; // 清除本地引用，但不dispose图片对象
    // 完全移除图片释放逻辑，改为依赖缓存管理器的定期清理
    super.dispose();
  }

  void _loadImage() {
    if (_currentUrl == widget.imageUrl || _isDisposed) return;
    _currentUrl = widget.imageUrl;
    _imageFuture = ImageCacheManager.instance.loadImage(widget.imageUrl);
  }

  // 安全获取图片，添加多重保护
  ui.Image? _getSafeImage(ui.Image? image) {
    if (_isDisposed || !mounted || image == null) {
      return null;
    }
    
    try {
      // 检查图片是否仍然有效
      final width = image.width;
      final height = image.height;
      if (width <= 0 || height <= 0) {
        return null;
      }
      
      // 缓存图片引用
      _cachedImage = image;
      return image;
    } catch (e) {
      // 图片已被释放或无效
      _cachedImage = null;
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果widget已被disposal，返回空容器
    if (_isDisposed) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
      );
    }

    return FutureBuilder<ui.Image>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(context, snapshot.error!);
          }
          return Image.asset(
            'assets/backempty.png',
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
          );
        }

        if (snapshot.hasData) {
          // 安全获取图片
          final safeImage = _getSafeImage(snapshot.data);
          
          if (safeImage == null) {
            // 图片无效，返回占位符
            return SizedBox(
              width: widget.width,
              height: widget.height,
            );
          }

          if (!_isImageLoaded) {
            // 使用addPostFrameCallback避免在build期间调用setState
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isDisposed) {
                setState(() {
                  _isImageLoaded = true;
                });
              }
            });
          }

          return AnimatedOpacity(
            opacity: _isImageLoaded ? 1.0 : 0.0,
            duration: widget.fadeDuration,
            curve: Curves.easeInOut,
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: SafeRawImage(
                image: safeImage,
                fit: widget.fit,
              ),
            ),
          );
        }

        return LoadingPlaceholder(
          width: widget.width ?? 160,
          height: widget.height ?? 228,
        );
      },
    );
  }
}

// 安全的RawImage包装器
class SafeRawImage extends StatelessWidget {
  final ui.Image? image;
  final BoxFit fit;

  const SafeRawImage({
    super.key,
    required this.image,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return const SizedBox.shrink();
    }

    try {
      // 再次检查图片有效性
      final _ = image!.width;
      
      return RawImage(
        image: image,
        fit: fit,
      );
    } catch (e) {
      // 图片已被释放，返回空容器
      return const SizedBox.shrink();
    }
  }
} 