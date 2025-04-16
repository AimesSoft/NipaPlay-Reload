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

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedNetworkImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      if (_currentUrl != null && widget.shouldRelease) {
        ImageCacheManager.instance.releaseImage(_currentUrl!);
      }
      setState(() {
        _isImageLoaded = false;
      });
      _loadImage();
    }
  }

  @override
  void dispose() {
    if (_currentUrl != null && widget.shouldRelease) {
      ImageCacheManager.instance.releaseImage(_currentUrl!);
    }
    super.dispose();
  }

  void _loadImage() {
    if (_currentUrl == widget.imageUrl) return;
    _currentUrl = widget.imageUrl;
    _imageFuture = ImageCacheManager.instance.loadImage(widget.imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          ////debugPrint('图片加载错误: ${snapshot.error}');
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
          if (!_isImageLoaded) {
            Future.microtask(() {
              if (mounted) {
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
              child: RawImage(
                image: snapshot.data,
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