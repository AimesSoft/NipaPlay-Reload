import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:nipaplay/services/media_server_image_loader.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tv_safe_blur.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
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

  /// 本次 URL 已经自动重试过几次。
  int _autoRetryCount = 0;

  /// 一次性加载失败后最多自动重试几次。
  ///
  /// 图床同时收到几十个海报请求时会丢掉其中一部分，而加载失败一次就永久留白
  /// 正是 iOS 上"刷不出全部图片"的直接来源。
  static const int _maxAutoRetries = 2;

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
    ImageCacheManager.instance.lifecycleGeneration
        .addListener(_onCacheReleased);
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
    ImageCacheManager.instance.lifecycleGeneration
        .removeListener(_onCacheReleased);
    _isDisposed = true;
    // 句柄的释放统一交给缓存管理器按字节预算与内存压力决定，
    // 组件这边只负责在收到通知时放下引用。
    super.dispose();
  }

  /// 缓存管理器主动释放了句柄（退到后台），或者 App 回到了前台。
  ///
  /// 释放时必须放下自己手里的引用：那些 [ui.Image] 已经被 dispose，
  /// 继续交给 RawImage 绘制只会画出一块空白。回前台则重新加载一次，
  /// 走磁盘缓存解码，不产生网络请求。
  void _onCacheReleased() {
    if (!mounted || _isDisposed) return;
    final isResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (isResumed) {
      setState(() {
        _isImageLoaded = false;
      });
      _loadImage(force: true);
      return;
    }
    setState(() {
      _basicImage = null;
      _imageFuture = null;
      _isImageLoaded = false;
    });
    // 允许回前台时重新走一遍加载。
    _currentUrl = null;
  }

  void _loadImage({bool force = false}) {
    if (_isDisposed) return;
    if (!force && _currentUrl == widget.imageUrl) return;
    if (_currentUrl != widget.imageUrl) {
      // 换了 URL：重试次数从头开始，否则上一张图的失败次数会传染给下一张。
      _autoRetryCount = 0;
    }
    _currentUrl = widget.imageUrl;
    _hasRetriedLowRes = false;

    final target = _resolveDecodeTarget();
    _decodeTarget = target;
    final int? targetWidth = target?.$1;
    final int? targetHeight = target?.$2;

    // 旧版：仅使用缓存管理器单通道加载
    if (widget.loadMode == CachedImageLoadMode.legacy) {
      _imageFuture = ImageCacheManager.instance.loadImage(
        widget.imageUrl,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      return;
    }

    final cachedImage = ImageCacheManager.instance.getCachedImage(
      widget.imageUrl,
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
        widget.imageUrl,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
    } else {
      _imageFuture = _loadOriginalImage(widget.imageUrl);
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

  /// 一次性加载失败后安排一次自动重试。
  ///
  /// 早前 `_currentUrl == widget.imageUrl` 的守卫让失败的图片永远不会再试，
  /// 而 iOS 上同时发出的几十个海报请求很容易有个别失败，那些卡片就永久空白。
  /// 这里最多补两次，间隔递增，避免对真正的坏图反复发请求。
  void _scheduleAutoRetry() {
    if (_isDisposed || _autoRetryCount >= _maxAutoRetries) return;
    _autoRetryCount++;
    Future.delayed(Duration(milliseconds: 600 * _autoRetryCount), () {
      if (!mounted || _isDisposed) return;
      _loadImage(force: true);
      setState(() {});
    });
  }

  // 新增方法：立即加载基础图片
  void _loadBasicImage() async {
    // 🔥 根据delayLoad参数决定是否延迟（避免与HEAD验证竞争）
    if (widget.delayLoad) {
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    try {
      final imageBytes = await loadNetworkImageBytes(
        Uri.parse(widget.imageUrl),
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

    // 标记"这张图正在被显示"：LRU 淘汰只看最后访问时间，而静止显示在屏幕上的
    // 图片不会再走缓存命中路径，不标记就会被当成最久未访问的那批淘汰掉。
    ImageCacheManager.instance.touch(
      widget.imageUrl,
      targetWidth: _decodeTarget?.$1,
      targetHeight: _decodeTarget?.$2,
    );

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
                _scheduleAutoRetry();
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
