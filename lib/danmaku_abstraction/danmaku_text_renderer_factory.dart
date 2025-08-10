import 'package:nipaplay/danmaku_abstraction/danmaku_text_renderer.dart';
import 'package:nipaplay/danmaku_gpu/lib/dynamic_font_atlas.dart';
import 'package:nipaplay/danmaku_gpu/lib/gpu_danmaku_config.dart';
import 'package:nipaplay/danmaku_gpu/lib/gpu_danmaku_text_renderer.dart';
import 'danmaku_kernel_factory.dart';

class DanmakuTextRendererFactory {
  static Future<DanmakuTextRenderer> create() async {
  // Use centralized kernel factory which already caches & defaults to GPU
  final engine = DanmakuKernelFactory.getKernelType();

    if (engine == DanmakuRenderEngine.gpu) {
      // For GPU, we need to create its dependencies
      final fontAtlas = DynamicFontAtlas(
        fontSize: 25, // Default font size for atlas
      );
      final config = GPUDanmakuConfig(); // Default config
      
      return GpuDanmakuTextRenderer(fontAtlas: fontAtlas, config: config);
  }
  // Default to CPU renderer
  return const CpuDanmakuTextRenderer();
  }
} 