import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:nipaplay/services/media_server_image_loader.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tv_safe_blur.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'loading_placeholder.dart';

// 图片加载模式
enum CachedImageLoadMode {
  // 当前混合模式：先快速加载基础图，再通过缓存/压缩通道加载高清图
  hybrid,
  // 旧版模式（699387b 提交之前）：仅走缓存管理器的单通道加载
  legacy,
}

/// [CachedNetworkImageWidget.fadeDuration] 的默认值哨兵。
///
/// 调用方不传 [fadeDuration] 时会落到这个值；在电视设备上我们把它解析为
/// [Duration.zero]，跳过每个图片一次 300ms 的不透明度过渡
/// （每次过渡都是一层 OpacityLayer，网格里会叠加成明显的合成开销）。
/// 调用方显式给出别的时长时一律尊重。
const Duration _kDefaultImageFadeDuration = Duration(milliseconds: 300);

class CachedNetworkImageWidget extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, Object)? errorBuilder;
  final bool shouldRelease;
  final Duration fadeDuration;
  final bool shouldCompress; // 新增参数，控制是否压缩图片
  final bool delayLoad; // 新增参数，控制是否延迟加载（避免与HEAD验证竞争）
  final CachedImageLoadMode loadMode; // 新增：加载模式（hybrid/legacy）
  final int? memCacheWidth; // 新增：指定内存缓存宽度（用于解码降采样）
  final int? memCacheHeight; // 新增：指定内存缓存高度（用于解码降采样）
  final bool blurIfLowRes; // 新增：低清时模糊
  final bool forceBlur; // 新增：强制模糊（不做分辨率判断）
  final double lowResBlurSigma; // 新增：低清模糊强度
  final double lowResMinScale; // 新增：低清判定阈值

  const CachedNetworkImageWidget({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
    this.shouldRelease = true,
    this.fadeDuration = _kDefaultImageFadeDuration,
    this.shouldCompress = true, // 默认为true，保持原有行为
    this.delayLoad = false, // 默认false，不延迟加载
    this.loadMode = CachedImageLoadMode.hybrid, // 默认使用混合模式
    this.memCacheWidth,
    this.memCacheHeight,
    this.blurIfLowRes = false,
    this.forceBlur = false,
    this.lowResBlurSigma = 40,
    this.lowResMinScale = 0.9,
  });

  @override
  State<CachedNetworkImageWidget> createState() =>
      _CachedNetworkImageWidgetState();
}

class _CachedNetworkImageWidgetState extends State<CachedNetworkImageWidget> {
  Future<ui.Image>? _imageFuture;
  String? _currentUrl;
  bool _isImageLoaded = false;
  bool _isDisposed = false;
  ui.Image? _basicImage; // 基础图片
  bool _hasRetriedLowRes = false;

  /// 本次解码的目标尺寸（物理像素），null 表示无法推导。
  (int?, int?)? _decodeTarget;

  /// 自动推导解码尺寸时的单边上限。
  ///
  /// 正常调用方都会显式传 memCacheWidth/Height；这个上限只用于兜底，
  /// 防止某个遗漏的调用方在低端设备上触发整图解码。
  /// 取 1080 是因为首页 hero 横幅是整屏宽（1080p 电视就是 1080 物理像素），
  /// 再低会明显损失画质；而它已经足以挡住 2000px+ 的原始海报。
  static const int _maxAutoDecodeEdge = 1080;

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
      setState(() {
        _isImageLoaded = false;
        _basicImage = null;
      });
      _loadImage();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    // 完全移除图片释放逻辑，改为依赖缓存管理器的定期清理
    super.dispose();
  }

  void _loadImage() async {
      if (_currentUrl == widget.imageUrl || _isDisposed) return;
      _currentUrl = widget.imageUrl;
      _hasRetriedLowRes = false;

      final resolvedUrl = await _resolveImageUrl(widget.imageUrl);

      final target = _resolveDecodeTarget();
      _decodeTarget = target;
      final int? targetWidth = target?.$1;
      final int? targetHeight = target?.$2;

      // 旧版：仅使用缓存管理器单通道加载
      if (widget.loadMode == CachedImageLoadMode.legacy) {
        _imageFuture = ImageCacheManager.instance.loadImage(
          resolvedUrl,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
        return;
      }

      final cachedImage = ImageCacheManager.instance.getCachedImage(
        resolvedUrl,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );

    if (cachedImage != null) {
      _basicImage = cachedImage;
    } else {
      // 混合模式：立即拉取基础图 + 异步加载高清图
      _loadBasicImage();
    }

    // 异步加载高清图片
    if (widget.shouldCompress) {
      _imageFuture = ImageCacheManager.instance.loadImage(
        resolvedUrl,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
    } else {
      _imageFuture = _loadOriginalImage(resolvedUrl);
    }
  }

  /// 解析本次解码的目标尺寸（物理像素）。
  ///
  /// 低端设备（尤其 32 位安卓电视）上，把一张 1000px+ 的海报原尺寸解码出来
  /// 再缩到 190×286 的格子里，是纯粹的内存与 CPU 浪费：一次整图 RGBA 分配
  /// （可达数 MB）加几十毫秒主 isolate 解码。
  ///
  /// 优先使用调用方显式给出的 [CachedNetworkImageWidget.memCacheWidth] /
  /// [CachedNetworkImageWidget.memCacheHeight]（这些值按约定已经是物理像素）；
  /// 两者都缺失时用组件的布局尺寸 × 设备像素比推导，并受
  /// [_maxAutoDecodeEdge] 上限约束，保证任何调用方都不会意外触发整图解码。
  (int?, int?)? _resolveDecodeTarget() {
    double ratio = 1.0;
    try {
      ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    } catch (_) {
      // 无 MediaQuery（例如被单独挂载）时退回 1.0。
    }

    int? width = widget.memCacheWidth;
    int? height = widget.memCacheHeight;

    if (width == null || height == null) {
      final double? logicalWidth =
          widget.width != null && widget.width!.isFinite ? widget.width : null;
      final double? logicalHeight =
          widget.height != null && widget.height!.isFinite
              ? widget.height
              : null;
      if (logicalWidth != null && logicalHeight != null) {
        width ??= (logicalWidth * ratio).round();
        height ??= (logicalHeight * ratio).round();
      }
    }

    if (width != null && width <= 0) width = null;
    if (height != null && height <= 0) height = null;
    if (width == null && height == null) return null;

    // 安全上限：即便调用方给了离谱的尺寸，也不做无意义的全尺寸解码。
    if (width != null && width > _maxAutoDecodeEdge) {
      width = _maxAutoDecodeEdge;
    }
    if (height != null && height > _maxAutoDecodeEdge) {
      height = _maxAutoDecodeEdge;
    }

    return (width, height);
  }

  /// 应用自定义 Bangumi API 服务器：api.bgm.tv 的图片/请求在部分网络环境
    /// 直连超时（errno 60），用户配置的三合一反代服务器可正常加载。
    Future<String> _resolveImageUrl(String url) async {
      if (!url.startsWith('https://api.bgm.tv') &&
          !url.startsWith('http://api.bgm.tv')) {
        return url;
      }
      try {
        final custom = await NetworkSettings.getBangumiServer();
        if (custom.isNotEmpty &&
            custom != 'https://api.bgm.tv' &&
            custom != 'http://api.bgm.tv') {
          return url
              .replaceFirst('https://api.bgm.tv', custom)
              .replaceFirst('http://api.bgm.tv', custom);
        }
      } catch (_) {}
      return url;
    }

    // 新增方法：立即加载基础图片
    void _loadBasicImage() async {
    // 🔥 根据delayLoad参数决定是否延迟（避免与HEAD验证竞争）
    if (widget.delayLoad) {
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    try {
          final resolvedUrl = await _resolveImageUrl(widget.imageUrl);
          final imageBytes = await loadNetworkImageBytes(
            Uri.parse(resolvedUrl),
          );
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: _decodeTarget?.$1,
        targetHeight: _decodeTarget?.$2,
      );
      final frame = await codec.getNextFrame();

      // 如果组件还在使用，更新基础图片
      if (mounted && !_isDisposed) {
        setState(() {
          _basicImage = frame.image;
        });
      }
    } catch (e) {
      debugPrint('加载基础图片失败: $e');
    }
  }

  // 新增方法：直接加载原始图片，不进行压缩
  Future<ui.Image> _loadOriginalImage(String imageUrl) async {
    final imageBytes = await loadNetworkImageBytes(Uri.parse(imageUrl));
    final codec = await ui.instantiateImageCodec(
      imageBytes,
      targetWidth: _decodeTarget?.$1,
      targetHeight: _decodeTarget?.$2,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
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
      return image;
    } catch (e) {
      // 图片已被释放或无效
      return null;
    }
  }

  Size? _resolveDisplaySize(BoxConstraints constraints) {
    double? width = widget.width;
    if (width != null && !width.isFinite) {
      width = null;
    }
    double? height = widget.height;
    if (height != null && !height.isFinite) {
      height = null;
    }
    if (width == null && constraints.hasBoundedWidth) {
      width = constraints.maxWidth;
    }
    if (height == null && constraints.hasBoundedHeight) {
      height = constraints.maxHeight;
    }
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width, height);
  }

  bool _shouldApplyBlur(
      ui.Image image, Size? displaySize, BuildContext context) {
    if (!widget.blurIfLowRes && !widget.forceBlur) {
      return false;
    }
    if (widget.forceBlur) {
      return true;
    }
    if (displaySize == null) {
      return false;
    }
    final requiredWidth = displaySize.width;
    final requiredHeight = displaySize.height;
    if (requiredWidth <= 0 || requiredHeight <= 0) {
      return false;
    }
    final minScale = widget.lowResMinScale;
    return image.width < requiredWidth * minScale ||
        image.height < requiredHeight * minScale;
  }

  Widget _wrapWithBlurIfNeeded(
    Widget child,
    ui.Image image,
    Size? displaySize,
    BuildContext context,
  ) {
    if (!_shouldApplyBlur(image, displaySize, context)) {
      return child;
    }
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(
        sigmaX: widget.lowResBlurSigma,
        sigmaY: widget.lowResBlurSigma,
      ),
      child: child,
    );
  }

  ui.Image? _chooseBestImage(
    ui.Image? baseImage,
    ui.Image? highResImage,
    Size? displaySize,
    BuildContext context,
  ) {
    if (baseImage == null) return highResImage;
    if (highResImage == null) return baseImage;

    final baseBlur = _shouldApplyBlur(baseImage, displaySize, context);
    final highResBlur = _shouldApplyBlur(highResImage, displaySize, context);
    if (baseBlur != highResBlur) {
      return baseBlur ? highResImage : baseImage;
    }

    final basePixels = baseImage.width * baseImage.height;
    final highResPixels = highResImage.width * highResImage.height;
    if (highResPixels >= basePixels) {
      return highResImage;
    }
    return baseImage;
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

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final displaySize = _resolveDisplaySize(constraints);

          return FutureBuilder<ui.Image>(
            future: _imageFuture,
            builder: (context, snapshot) {
              final baseImage = _getSafeImage(_basicImage);
              final loadedImage = _getSafeImage(snapshot.data);
              final selectedImage = _chooseBestImage(
                baseImage,
                loadedImage,
                displaySize,
                context,
              );

              if (!_hasRetriedLowRes &&
                  widget.blurIfLowRes &&
                  !widget.forceBlur &&
                  selectedImage != null &&
                  snapshot.hasData &&
                  _shouldApplyBlur(selectedImage, displaySize, context)) {
                _hasRetriedLowRes = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_isDisposed) {
                    setState(() {
                      _imageFuture = ImageCacheManager.instance.loadImage(
                        widget.imageUrl,
                        targetWidth: _decodeTarget?.$1,
                        targetHeight: _decodeTarget?.$2,
                        forceRefresh: true,
                      );
                    });
                  }
                });
              }

              if (snapshot.hasError && selectedImage == null) {
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

              if (selectedImage != null) {
                if (!_isImageLoaded && snapshot.hasData) {
                  // 使用addPostFrameCallback避免在build期间调用setState
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_isDisposed) {
                      setState(() {
                        _isImageLoaded = true;
                      });
                    }
                  });
                }

                final effectiveFade =
                    widget.fadeDuration == _kDefaultImageFadeDuration &&
                            shouldSkipTvBackdropBlur
                        ? Duration.zero
                        : widget.fadeDuration;
                final imageWidget =
                    effectiveFade.inMilliseconds == 0 || !snapshot.hasData
                        ? SizedBox(
                            width: widget.width,
                            height: widget.height,
                            child: SafeRawImage(
                              image: selectedImage,
                              fit: widget.fit,
                            ),
                          )
                        : AnimatedOpacity(
                            opacity: _isImageLoaded ? 1.0 : 0.0,
                            duration: effectiveFade,
                            curve: Curves.easeInOut,
                            child: SizedBox(
                              width: widget.width,
                              height: widget.height,
                              child: SafeRawImage(
                                image: selectedImage,
                                fit: widget.fit,
                              ),
                            ),
                          );

                return _wrapWithBlurIfNeeded(
                    imageWidget, selectedImage, displaySize, context);
              }

              return LoadingPlaceholder(
                width: widget.width ?? 160,
                height: widget.height ?? 228,
              );
            },
          );
        },
      ),
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
