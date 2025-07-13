import 'package:flutter/material.dart';
import 'gpu_danmaku_item.dart';
import 'gpu_danmaku_config.dart';

/// GPU弹幕轨道管理器
/// 
/// 负责管理顶部和底部弹幕的轨道分配
class GPUDanmakuTrackManager {
  final GPUDanmakuConfig config;
  
  /// 轨道项目映射 Map<轨道ID, 弹幕项目列表>
  final Map<int, List<GPUDanmakuItem>> _trackItems = {};
  
  /// 轨道可用状态
  List<bool> _availableTracks = [];
  
  /// 最大轨道数
  int _maxTracks = 0;
  
  /// 轨道类型（顶部或底部）
  final DanmakuTrackType trackType;
  
  GPUDanmakuTrackManager({
    required this.config,
    required this.trackType,
  });

  /// 更新轨道布局
  /// 
  /// 参数:
  /// - size: 屏幕尺寸
  void updateLayout(Size size) {
    final newMaxTracks = _calculateMaxTracks(size);
    if (newMaxTracks != _maxTracks) {
      _maxTracks = newMaxTracks;
      _availableTracks = List<bool>.filled(_maxTracks, true);
      _resetInvalidTracks();
    }
  }

  /// 计算最大轨道数
  int _calculateMaxTracks(Size size) {
    if (size.height <= 0) return 0;
    return (size.height * config.screenUsageRatio / config.trackHeight).floor();
  }

  /// 重置无效轨道（当屏幕尺寸变化时）
  void _resetInvalidTracks() {
    final invalidItems = <GPUDanmakuItem>[];
    _trackItems.removeWhere((trackId, items) {
      if (trackId >= _maxTracks) {
        // 收集需要重新分配的项目
        for (final item in items) {
          item.resetTrack();
          invalidItems.add(item);
        }
        return true;
      }
      return false;
    });
    
    // 重新分配无效项目
    for (final item in invalidItems) {
      assignTrack(item);
    }
  }

  /// 分配轨道给弹幕项目
  /// 
  /// 参数:
  /// - item: 弹幕项目
  /// 
  /// 返回: 是否成功分配轨道
  bool assignTrack(GPUDanmakuItem item) {
    if (_maxTracks <= 0) return false;
    
    // 优化：如果弹幕已经有轨道，直接返回成功
    if (item.trackId >= 0 && item.trackId < _maxTracks) {
      return true;
    }
    
    // 重置轨道可用状态
    _availableTracks.fillRange(0, _maxTracks, true);
    
    // 标记已占用的轨道
    _trackItems.forEach((trackId, items) {
      if (trackId < _maxTracks) {
        _availableTracks[trackId] = false;
      }
    });
    
    // 寻找可用轨道
    for (int i = 0; i < _maxTracks; i++) {
      if (_availableTracks[i]) {
        item.trackId = i;
        _trackItems.putIfAbsent(i, () => []).add(item);
        return true;
      }
    }
    
    return false; // 没有可用轨道
  }

  /// 移除弹幕项目
  /// 
  /// 参数:
  /// - item: 弹幕项目
  void removeItem(GPUDanmakuItem item) {
    if (item.trackId >= 0 && item.trackId < _maxTracks) {
      final trackItems = _trackItems[item.trackId];
      if (trackItems != null) {
        trackItems.remove(item);
        if (trackItems.isEmpty) {
          _trackItems.remove(item.trackId);
        }
      }
    }
  }

  /// 清空所有轨道
  void clear() {
    _trackItems.clear();
    if (_availableTracks.isNotEmpty) {
      _availableTracks.fillRange(0, _maxTracks, true);
    }
  }

  /// 获取指定轨道的弹幕项目
  /// 
  /// 参数:
  /// - trackId: 轨道ID
  /// 
  /// 返回: 弹幕项目列表
  List<GPUDanmakuItem> getTrackItems(int trackId) {
    return _trackItems[trackId] ?? [];
  }

  /// 获取所有轨道的弹幕项目
  /// 
  /// 返回: Map<轨道ID, 弹幕项目列表>
  Map<int, List<GPUDanmakuItem>> getAllTrackItems() {
    return Map.unmodifiable(_trackItems);
  }

  /// 计算轨道的Y坐标
  /// 
  /// 参数:
  /// - trackId: 轨道ID
  /// - screenHeight: 屏幕高度
  /// 
  /// 返回: Y坐标
  double calculateTrackY(int trackId, double screenHeight) {
    switch (trackType) {
      case DanmakuTrackType.top:
        // 顶部弹幕从屏幕顶部开始
        return trackId * (config.fontSize + config.danmakuBottomMargin);
      case DanmakuTrackType.bottom:
        // 底部弹幕从屏幕底部开始，向上排列
        final totalHeight = _maxTracks * (config.fontSize + config.danmakuBottomMargin);
        return screenHeight - totalHeight + trackId * (config.fontSize + config.danmakuBottomMargin);
    }
  }

  /// 获取最大轨道数
  int get maxTracks => _maxTracks;

  /// 获取当前使用的轨道数
  int get usedTracks => _trackItems.length;

  /// 检查轨道是否可用
  bool isTrackAvailable(int trackId) {
    return trackId < _maxTracks && 
           trackId >= 0 && 
           !_trackItems.containsKey(trackId);
  }

  /// 调试信息
  Map<String, dynamic> getDebugInfo() {
    return {
      'maxTracks': _maxTracks,
      'usedTracks': usedTracks,
      'trackType': trackType.toString(),
      'trackItems': _trackItems.map((key, value) => MapEntry(key.toString(), value.length)),
    };
  }
}

/// 弹幕轨道类型
enum DanmakuTrackType {
  /// 顶部弹幕
  top,
  /// 底部弹幕
  bottom,
} 