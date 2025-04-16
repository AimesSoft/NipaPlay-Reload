import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/image_cache_manager.dart';

class CachedNetworkImageWidget extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget Function(BuildContext, Object)? errorBuilder;
  final double? width;
  final double? height;
  final bool shouldRelease;

  const CachedNetworkImageWidget({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.width,
    this.height,
    this.shouldRelease = true,
  });

  @override
  State<CachedNetworkImageWidget> createState() => _CachedNetworkImageWidgetState();
}

class _CachedNetworkImageWidgetState extends State<CachedNetworkImageWidget> {
  Future<ui.Image>? _imageFuture;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.imageUrl;
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedNetworkImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      if (_currentUrl != null && widget.shouldRelease) {
        ImageCacheManager.instance.releaseImage(_currentUrl!);
      }
      _currentUrl = widget.imageUrl;
      _loadImage();
    }
  }

  void _loadImage() {
    if (_currentUrl == null) return;
    _imageFuture = ImageCacheManager.instance.loadImage(_currentUrl!);
  }

  void _retryLoad() {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      _loadImage();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          ////print('图片加载错误: ${snapshot.error}');
          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(context, snapshot.error!);
          }
          return GestureDetector(
            onTap: _retryLoad,
            child: Container(
              width: widget.width,
              height: widget.height,
              color: Colors.grey[800],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white54),
                  const SizedBox(height: 8),
                  Text(
                    '加载失败，点击重试 (${_retryCount + 1}/$_maxRetries)',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasData) {
          return SizedBox(
            width: widget.width ?? 300,
            height: widget.height ?? 300 * 10 / 7,
            child: RawImage(
              image: snapshot.data,
              fit: widget.fit,
            ),
          );
        }

        return Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    if (_currentUrl != null && widget.shouldRelease) {
      ImageCacheManager.instance.releaseImage(_currentUrl!);
    }
    super.dispose();
  }
} 