import 'package:flutter/widgets.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';

/// 在系统内存压力与退到后台时释放图片缓存。
///
/// 解码后的 `ui.Image` 像素属于 native/external 内存，不受 Dart GC 管理。
/// 在 32 位低端电视盒子上，这部分内存耗尽会直接导致 OOM 终止进程，
/// 而 Dart 侧的 GC 永远不会主动归还它。
///
/// [ImageCacheManager] 自身已有字节预算兜底，这里额外挂上系统的
/// `didHaveMemoryPressure` 回调，让"有人比我们更清楚该省内存"的时刻
/// 也能立刻生效。
class ImageCacheMemoryPressureHandler extends StatefulWidget {
  const ImageCacheMemoryPressureHandler({super.key, required this.child});

  final Widget child;

  @override
  State<ImageCacheMemoryPressureHandler> createState() =>
      _ImageCacheMemoryPressureHandlerState();
}

class _ImageCacheMemoryPressureHandlerState
    extends State<ImageCacheMemoryPressureHandler> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    ImageCacheManager.instance.handleMemoryPressure();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 退到后台时释放非活跃图片；回到前台会按需重新解码（有磁盘缓存兜底）。
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ImageCacheManager.instance.handleMemoryPressure();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
