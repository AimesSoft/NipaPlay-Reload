// ════════════════════════════════════════════════════════════════════
//  V6.0 Phase 1: 精灵图集系统
//  将所有弹幕预光栅化图像打包到一张共享纹理，供 drawRawAtlas 批量提交
// ════════════════════════════════════════════════════════════════════

import 'dart:collection';
import 'dart:ui' as ui;

/// 精灵槽位 — 记录每个弹幕在图集中的位置与逻辑尺寸
class SpriteSlot {
  /// 图集中的源矩形（像素坐标，已含 DPR 缩放）
  final ui.Rect srcRect;

  /// 逻辑宽度（未乘 DPR，用于 canvas 坐标）
  final double logicalW;

  /// 逻辑高度（未乘 DPR，用于 canvas 坐标）
  final double logicalH;

  /// 此槽位对应的缓存键哈希
  final int hashKey;

  /// 关联的预光栅化图像引用（用于 atlas rebuild 时重绘）
  ui.Image rasterImage;

  /// 是否可复用（淘汰后标记为 true）
  bool reusable = false;

  SpriteSlot({
    required this.srcRect,
    required this.logicalW,
    required this.logicalH,
    required this.hashKey,
    required this.rasterImage,
  });
}

/// 全帧 drawRawAtlas 弹幕精灵图集
///
/// 核心思路：
/// - 所有弹幕的预光栅化 ui.Image 被打包到一张 4096×4096 共享纹理中
/// - paint() 用单次 drawRawAtlas 替代 N 次 drawImageRect → GPU draw call 从 N 降至 1
/// - 图集在缓存未命中时增量重建，稳态帧无需任何图集操作
///
/// 生命周期：
/// 1. 新弹幕出现 → 光栅化 Paragraph → 得到 ui.Image → 分配槽位 → 标记 atlas dirty
/// 2. atlas dirty → 重建图集纹理（PictureRecorder + drawImageRect × N + toImageSync）
/// 3. paint() → 直接使用图集纹理 + drawRawAtlas
class DanmakuSpriteAtlas {
  /// 图集纹理 — 所有弹幕共享
  ui.Image? _atlasTexture;

  /// 槽位映射 — int 哈希键 → 槽位
  final HashMap<int, SpriteSlot> _slots = HashMap<int, SpriteSlot>();

  /// 槽位插入顺序 — 用于 FIFO 淘汰
  final List<int> _slotOrder = <int>[];

  /// 最大槽位数（与光栅化缓存上限一致）
  static const int _maxSlots = 2000;

  // ── Shelf-pack 游标 ──

  double _cursorX = 0.0;
  double _cursorY = 0.0;
  double _rowHeight = 0.0;

  /// 图集宽度（像素）
  final double atlasWidth;

  /// 图集高度（像素）
  final double atlasHeight;

  /// 图集是否需要重建
  bool _dirty = true;

  /// 设备像素比 — 用于逻辑→像素坐标转换
  final double devicePixelRatio;

  /// 槽位间距（像素）— 防止纹理采样溢出（Impeller 需要更大间距）
  static const double _slotPadding = 4.0;

  DanmakuSpriteAtlas({
    this.atlasWidth = 4096.0,
    this.atlasHeight = 4096.0,
    required this.devicePixelRatio,
  });

  /// 当前图集纹理（可能为 null，需要调用 ensureAtlas）
  ui.Image? get atlasTexture => _atlasTexture;

  /// 图集是否需要重建
  bool get isDirty => _dirty;

  /// 当前槽位数量
  int get slotCount => _slots.length;

  /// 获取已有槽位 — 返回 null 表示未命中
  SpriteSlot? getSlot(int hashKey) {
    final slot = _slots[hashKey];
    if (slot != null && !slot.reusable) {
      return slot;
    }
    return null;
  }

  /// 添加精灵到图集 — 分配槽位并标记 dirty
  ///
  /// [hashKey] 整数哈希缓存键
  /// [rasterImage] 预光栅化图像
  /// [logicalW] 逻辑宽度
  /// [logicalH] 逻辑高度
  ///
  /// 返回分配的槽位；若图集空间不足返回 null
  SpriteSlot? addSprite({
    required int hashKey,
    required ui.Image rasterImage,
    required double logicalW,
    required double logicalH,
  }) {
    // 若已存在（可复用槽位），先释放旧槽位
    final existing = _slots[hashKey];
    if (existing != null && existing.reusable) {
      // 复用槽位位置，更新图像引用
      existing.rasterImage = rasterImage;
      existing.reusable = false;
      _dirty = true;
      return existing;
    }

    // FIFO 淘汰：槽位满时淘汰最旧的
    if (_slots.length >= _maxSlots && _slotOrder.isNotEmpty) {
      _evictOldest();
    }

    // 计算像素尺寸（含间距）
    final pixelW = (logicalW * devicePixelRatio).ceil() + _slotPadding * 2;
    final pixelH = (logicalH * devicePixelRatio).ceil() + _slotPadding * 2;

    // Shelf-pack 分配
    final slotRect = _allocateSlot(pixelW, pixelH);
    if (slotRect == null) {
      // 图集空间不足 — 尝试紧凑化重建
      _compactAndRebuild();
      final retryRect = _allocateSlot(pixelW, pixelH);
      if (retryRect == null) {
        return null; // 仍然不够，放弃此精灵
      }
    }

    final slot = SpriteSlot(
      // srcRect 包含 padding 偏移
      srcRect: ui.Rect.fromLTWH(
        slotRect!.left + _slotPadding,
        slotRect.top + _slotPadding,
        (logicalW * devicePixelRatio).ceil().toDouble(),
        (logicalH * devicePixelRatio).ceil().toDouble(),
      ),
      logicalW: logicalW,
      logicalH: logicalH,
      hashKey: hashKey,
      rasterImage: rasterImage,
    );

    _slots[hashKey] = slot;
    _slotOrder.add(hashKey);
    _dirty = true;
    return slot;
  }

  /// 标记槽位为可复用（弹幕离开视口时调用）
  void markReusable(int hashKey) {
    final slot = _slots[hashKey];
    if (slot != null) {
      slot.reusable = true;
      // 不立即标记 dirty — 可复用槽位仍保留在图集中，
      // 新弹幕可复用其位置，只有真正淘汰时才需重建
    }
  }

  /// 确保图集纹理可用 — 若 dirty 则重建
  ///
  /// 返回可用的图集纹理，或 null（重建失败时）
  ui.Image? ensureAtlas() {
    if (!_dirty && _atlasTexture != null) {
      return _atlasTexture;
    }
    _rebuildAtlas();
    return _atlasTexture;
  }

  /// 释放所有资源
  void dispose() {
    _atlasTexture?.dispose();
    _atlasTexture = null;
    _slots.clear();
    _slotOrder.clear();
    _dirty = true;
  }

  /// DPR 变更时清除所有缓存
  void invalidate() {
    _atlasTexture?.dispose();
    _atlasTexture = null;
    _slots.clear();
    _slotOrder.clear();
    _cursorX = 0.0;
    _cursorY = 0.0;
    _rowHeight = 0.0;
    _dirty = true;
  }

  // ════════════════════════════════════════════════════════════════
  //  内部方法
  // ════════════════════════════════════════════════════════════════

  /// Shelf-pack 槽位分配
  ///
  /// 行优先打包：从左到右填充当前行，不够时换行。
  /// 简单但高效，对弹幕场景（宽度相近、高度统一）接近最优。
  ui.Rect? _allocateSlot(double pixelW, double pixelH) {
    // 当前行能放下？
    if (_cursorX + pixelW <= atlasWidth) {
      final rect = ui.Rect.fromLTWH(_cursorX, _cursorY, pixelW, pixelH);
      _cursorX += pixelW;
      if (pixelH > _rowHeight) {
        _rowHeight = pixelH;
      }
      return rect;
    }

    // 换行
    final newY = _cursorY + _rowHeight;
    if (newY + pixelH > atlasHeight) {
      return null; // 图集空间不足
    }

    _cursorY = newY;
    _cursorX = 0.0;
    _rowHeight = pixelH;

    final rect = ui.Rect.fromLTWH(_cursorX, _cursorY, pixelW, pixelH);
    _cursorX += pixelW;
    return rect;
  }

  /// FIFO 淘汰最旧槽位
  void _evictOldest() {
    while (_slotOrder.isNotEmpty && _slots.length >= _maxSlots) {
      final oldestKey = _slotOrder.removeAt(0);
      _slots.remove(oldestKey);
      // 旧槽位的 rasterImage 不在此 dispose — 由外部 _rasterCache 管理
      // 标记 dirty 因为图集内容变化
      _dirty = true;
      break; // 一次淘汰一个，调用方循环即可
    }
  }

  /// 紧凑化重建 — 重置游标后重新排列所有活跃槽位
  void _compactAndRebuild() {
    // 收集所有活跃槽位
    final activeSlots = _slots.values.where((s) => !s.reusable).toList();

    // 重置游标
    _cursorX = 0.0;
    _cursorY = 0.0;
    _rowHeight = 0.0;

    // 清除可复用槽位
    _slots.removeWhere((_, s) => s.reusable);
    _slotOrder.removeWhere((key) => !_slots.containsKey(key));

    // 重新分配位置
    for (final slot in activeSlots) {
      final pixelW = slot.srcRect.width + _slotPadding * 2;
      final pixelH = slot.srcRect.height + _slotPadding * 2;
      final newRect = _allocateSlot(pixelW, pixelH);
      if (newRect != null) {
        // 更新 srcRect
        final newSlot = SpriteSlot(
          srcRect: ui.Rect.fromLTWH(
            newRect.left + _slotPadding,
            newRect.top + _slotPadding,
            slot.srcRect.width,
            slot.srcRect.height,
          ),
          logicalW: slot.logicalW,
          logicalH: slot.logicalH,
          hashKey: slot.hashKey,
          rasterImage: slot.rasterImage,
        );
        _slots[slot.hashKey] = newSlot;
      }
    }
    _dirty = true;
  }

  /// 重建图集纹理 — 将所有活跃槽位的 rasterImage 绘制到一张共享纹理
  void _rebuildAtlas() {
    if (_slots.isEmpty) {
      _dirty = false;
      return;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // 显式清除整个画布为透明 — 防止 Impeller toImageSync
    // 未初始化 GPU 纹理内存导致白色/脏数据残留
    // ⚠️ [ATLAS-DIAG-BUG1] 改用 BlendMode.clear 替代 BlendMode.src + transparent:
    // Impeller 可能将 "写入 alpha=0 像素" 优化为 no-op，BlendMode.clear 语义为
    // "丢弃目标，写入全透明"，对应 GPU 的 glClear/vkClearAttachment，不会被优化掉
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, atlasWidth, atlasHeight),
      ui.Paint()..blendMode = ui.BlendMode.clear,
    );

    // 绘制所有活跃槽位的图像到图集
    for (final slot in _slots.values) {
      if (slot.reusable) continue;

      // 将预光栅化图像绘制到槽位区域（含 padding 偏移）
      final dstRect = ui.Rect.fromLTWH(
        slot.srcRect.left,
        slot.srcRect.top,
        slot.srcRect.width,
        slot.srcRect.height,
      );
      canvas.drawImageRect(
        slot.rasterImage,
        ui.Rect.fromLTWH(
          0,
          0,
          slot.rasterImage.width.toDouble(),
          slot.rasterImage.height.toDouble(),
        ),
        dstRect,
        ui.Paint()..filterQuality = ui.FilterQuality.none,
      );
    }

    final picture = recorder.endRecording();

    // 释放旧图集纹理
    _atlasTexture?.dispose();

    // 生成新图集纹理
    _atlasTexture = picture.toImageSync(
      atlasWidth.toInt(),
      atlasHeight.toInt(),
    );

    _dirty = false;
  }
}
