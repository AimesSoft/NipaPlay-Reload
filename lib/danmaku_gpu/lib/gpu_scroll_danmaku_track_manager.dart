import 'package:flutter/material.dart';
import 'gpu_danmaku_item.dart';
import 'gpu_danmaku_config.dart';

/// GPU滚动弹幕轨道管理器
///
/// 实现了不允许弹幕重叠的轨道分配算法。
/// 核心思想：
/// 1. 将所有滚动弹幕按出现时间排序。
/// 2. 遍历弹幕，为每条弹幕寻找一个不会发生碰撞的轨道。
/// 3. 从上到下检查轨道，如果轨道的最后一条弹幕的尾部已经滚出屏幕，
///    或者与新弹幕的头部没有重叠，则可以将新弹幕放入该轨道。
class GPUScrollDanmakuTrackManager {
  final GPUDanmakuConfig config;
  final Map<int, List<GPUDanmakuItem>> _trackItems = {};
  int _maxTracks = 0;
  Size _lastScreenSize = Size.zero;

  GPUScrollDanmakuTrackManager({required this.config});

  void updateLayout(Size size) {
    if (_lastScreenSize != size) {
      _lastScreenSize = size;
      _maxTracks = (size.height * config.screenUsageRatio / config.trackHeight).floor();
      _trackItems.clear(); // 尺寸变化时清空轨道，重新计算
    }
  }

  /// 为滚动弹幕分配一个不重叠的轨道
  /// 返回分配的轨道ID，如果无法分配则返回-1
  int assignTrack(GPUDanmakuItem item, double screenWidth) {
    if (_maxTracks <= 0) return -1;

    // 尝试在现有轨道中寻找位置
    for (int i = 0; i < _maxTracks; i++) {
      final track = _trackItems[i];
      if (track == null || track.isEmpty) {
        _trackItems.putIfAbsent(i, () => []).add(item);
        item.trackId = i;
        return i;
      }

      final lastItem = track.last;
      final lastItemTextWidth = lastItem.getTextWidth(config.fontSize * lastItem.fontSizeMultiplier);
      final itemTextWidth = item.getTextWidth(config.fontSize * item.fontSizeMultiplier);

      // 计算lastItem完全离开屏幕的时间点
      final lastItemDisappearTime = lastItem.timeOffset + ((lastItem.scrollOriginalX! + lastItemTextWidth) / (config.scrollScreensPerSecond * screenWidth)) * 1000;
      // 当前item出现时，lastItem是否已经完全消失
      if (item.timeOffset >= lastItemDisappearTime) {
         _trackItems[i]!.add(item);
         item.trackId = i;
         return i;
      }

      // lastItem的尾部是否在新item的头部之前 (不会追尾)
      final lastItemTailX = lastItem.scrollOriginalX! + lastItemTextWidth;
      final itemHeadX = item.scrollOriginalX!;
      if(lastItemTailX <= itemHeadX) {
        _trackItems[i]!.add(item);
        item.trackId = i;
        return i;
      }
    }

    // 所有轨道都无法放入
    return -1;
  }

  void removeItem(GPUDanmakuItem item) {
    if (item.trackId != -1) {
      _trackItems[item.trackId]?.remove(item);
    }
  }

  void clear() {
    _trackItems.clear();
  }

  List<GPUDanmakuItem> getTrackItems(int trackId) {
    return _trackItems[trackId] ?? [];
  }

  Map<int, List<GPUDanmakuItem>> getAllTrackItems() {
    return Map.unmodifiable(_trackItems);
  }

  /// 计算滚动轨道的Y坐标
  double calculateTrackY(int trackId) {
    return trackId * config.trackHeight;
  }
} 