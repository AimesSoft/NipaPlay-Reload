import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';

import 'danmaku_next_log.dart';
import 'msdf_font_atlas.dart';
import 'msdf_text_renderer.dart';

class MsdfDanmakuPainter extends CustomPainter {
  final List<PositionedDanmakuItem> items;
  final MsdfFontAtlas atlas;
  final MsdfTextRenderer renderer;
  final double opacity;

  MsdfDanmakuPainter({
    required this.items,
    required this.atlas,
    required this.renderer,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!renderer.isReady || atlas.atlasTexture == null) {
      DanmakuNextLog.d(
        'Painter',
        'skip paint: rendererReady=${renderer.isReady} atlasReady=${atlas.atlasTexture != null}',
        throttle: const Duration(seconds: 2),
      );
      return;
    }

    int drawn = 0;
    int pending = 0;
    for (final item in items) {
      atlas.addText(item.content.text);
      if (!atlas.isTextReady(item.content.text)) {
        pending++;
        continue;
      }
      renderer.renderDanmaku(canvas, atlas, item, opacity);
      drawn++;
    }

    DanmakuNextLog.d(
      'Painter',
      'paint items=${items.length} drawn=$drawn pending=$pending',
      throttle: const Duration(seconds: 1),
    );
  }

  @override
  bool shouldRepaint(covariant MsdfDanmakuPainter oldDelegate) {
    return true;
  }
}
