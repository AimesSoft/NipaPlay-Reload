import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/image_cache_manager.dart';

class CachedNetworkImageWidget extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget Function(BuildContext, Object)? errorBuilder;

  const CachedNetworkImageWidget({
    Key? key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  }) : super(key: key);

  @override
  State<CachedNetworkImageWidget> createState() => _CachedNetworkImageWidgetState();
}

class _CachedNetworkImageWidgetState extends State<CachedNetworkImageWidget> {
  late Future<ui.Image> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = ImageCacheManager.instance.loadImage(widget.imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError && widget.errorBuilder != null) {
          return widget.errorBuilder!(context, snapshot.error!);
        }

        if (snapshot.hasData) {
          return SizedBox(
            width: 300,
            height: 300 * 10 / 7,
            child: RawImage(
              image: snapshot.data,
              fit: widget.fit,
            ),
          );
        }

        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          ),
        );
      },
    );
  }
} 