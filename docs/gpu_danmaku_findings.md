# GPU 弹幕系统问题记录

## 1. 时间轴混乱
- `GPUDanmakuItem.timeOffset` 被封装成 `PositionedDanmakuItem.time * 1000`，但 `GPUDanmakuBaseRenderer` 又把 `createdAt` 设置为 `DateTime.now()`，可见判断使用 `currentTime * 1000 - timeOffset`（top/bottom renderer）。
- Seek、暂停恢复时 GPU 层的时间轴与 `DanmakuContainer` 计算出的轨迹不同步，导致弹幕提前/延后出现。
- 建议：保留真实播放时间（相对视频开头），渲染端依据播放器当前 `currentTime` 计算可见性与滚动位置，彻底去掉 `DateTime.now()`。

## 2. 滚动轨迹与碰撞逻辑不正确
- `GPUScrollDanmakuTrackManager` 依赖 `scrollOriginalX` 和 `timeOffset` 推算追尾，但这些值是在布局时算的。当用户 seek 到未来时间或更改速度时，该值不再代表“屏幕外起点”，导致轨道复用判断失效。
- 建议：轨道管理只分配 `trackId`，实际 X 坐标在 GPU 渲染时用 `startTime` + 滚动速度计算，或在布局端每次 seek 后重新计算 `scrollOriginalX`。

## 3. 字体图集在字号切换后不重建
- `updateOptions` 里 `_fontAtlas` 按旧字号生成，用户修改弹幕字号时只替换 `GpuDanmakuTextRenderer` 的 config，导致图集尺寸错误或模糊。
- 建议：字号变化时调用 `FontAtlasManager.disposeInstance` 并重新 `generate`，或为不同字号分别缓存。

## 4. `FontAtlasManager` 预构建流程易空指针
- `preInitialize`/`prebuildFromTexts` 默认 `_initialized[key]!` 已存在；如果未先 `getInstance`，直接调用会触发 NPE。
- 建议：检查 key，不存在时先创建 `DynamicFontAtlas` 实例并初始化 `_initialized[key] = false`。

## 5. 字体图集无限增长
- `_regenerateAtlas` 每次重绘整张 2048px 宽纹理，`_allChars` 不清理，长时间播放字符数增多后重建成本和内存不断增加，移动端易爆显存。
- 建议：实现分页或 LRU 驱逐策略，限制字符数，或按语言/常用字频分多个 atlas。

## 6. GPU 渲染每帧全量重建
- `GPUDanmakuRenderer.setDanmaku` 每次 `DanmakuContainer` 重算后都会清空并重新 push 所有弹幕，`shouldRepaint` 恒 true，`CustomPaint` 每帧重绘所有条目。
- 缺少时间窗口剔除或对象池，弹幕数量大时 CPU/GPU 同时飙升。
- 建议：维护滑动窗口，仅更新当前时间附近的弹幕；复用 `GPUDanmakuItem`；在 `shouldRepaint` 利用 `Listenable` 减少不必要重绘。

## 7. 滚动轨道在窗口大小变化时被清空
- `GPUScrollDanmakuTrackManager.updateLayout` 直接 `clear()`，导致窗口 resize/旋转时弹幕瞬间消失。
- 建议：参考顶部/底部轨道管理器，只搬迁超出新轨道范围的弹幕，保留其余轨道。

## 8. 透明度重复叠加
- 外层 `GPUDanmakuOverlay` 用 `Opacity` 控制透明度，`GpuDanmakuTextRenderer.renderItem` 仍把 `opacity` 传入 `drawAtlas`（`BlendMode.modulate`），导致亮度降低。
- 建议：统一透明度控制（只在绘制或容器层应用一次）。

## 9. 调试选项更新频繁
- `GPUDanmakuOverlay.didUpdateWidget` 每次 rebuild 都 `context.read<DeveloperOptionsProvider>()` 并更新调试选项，即使值没变化也调用。
- 建议：监听 Provider 的 `Listenable` 或缓存旧值，仅在变化时调用 `updateDebugOptions`。

## 10. 缺少多分辨率适配
- `FontAtlasManager` 的 key 仅包含 `(fontSize, color)`，没有考虑设备像素比；`GpuDanmakuTextRenderer` 固定 `scale=0.5` 假设 atlas 用 2x 渲染。当用户放大字号或在高 DPI 设备上使用时会模糊。
- 建议：将 devicePixelRatio 纳入 key，根据配置动态调整 atlas 渲染倍率和 `scale`。

## 11. 滚动轨道速率计算
- 轨迹速度 `config.scrollScreensPerSecond` 通过 `1/durationSeconds` 推导，但 `GPUDanmakuRenderer` 依靠 `currentX`（来自 CPU 布局）而不是 runtime 计算 `x = startX - speed * elapsed`，导致不同播放速率或 seek 后位置不准确。
- 建议：GPU 端直接根据 `elapsed` 计算位置，CPU 提供 `startTime`/`trackId` 即可。

## 12. 对象创建与 GC 压力
- 每条弹幕每帧都会创建多组 `RSTransform`、`Rect`、`Color`（描边+填充共 12 个结构），且 `renderItem` 完全基于可变 `List` 临时拼装。
- 建议：预分配 buffer 或复用 `Float32List` + 自定义 shader 来减少 GC；同类型弹幕可批量 `drawAtlas` 一次绘制。

