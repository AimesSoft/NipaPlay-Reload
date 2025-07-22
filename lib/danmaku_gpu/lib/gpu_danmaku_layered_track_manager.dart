import 'package:flutter/material.dart';
import 'gpu_danmaku_item.dart';
import 'gpu_danmaku_config.dart';

/// GPU弹幕分层轨道管理器
/// 
/// 负责管理多层轨道分配，当第一层满了时自动创建第二层
class GPUDanmakuLayeredTrackManager {
  final GPUDanmakuConfig config;
  
  /// 轨道项目映射 Map<轨道ID, 弹幕项目列表>
  final Map<int, List<GPUDanmakuItem>> _trackItems = {};
  
  /// 轨道可用状态
  List<bool> _availableTracks = [];
  
  /// 最大轨道数（单层）
  int _maxTracksPerLayer = 0;
  
  /// 当前层数
  int _currentLayerCount = 1;
  
  /// 轨道类型（顶部或底部）
  final DanmakuTrackType trackType;
  
  /// 记录上次的屏幕尺寸，用于检测窗口大小变化
  Size _lastScreenSize = Size.zero;
  
  /// 轨道使用率阈值（超过此值创建新层）
  static const double _usageThreshold = 1.0; // 100%
  
  GPUDanmakuLayeredTrackManager({
    required this.config,
    required this.trackType,
  });

  /// 更新轨道布局
  /// 
  /// 参数:
  /// - size: 屏幕尺寸
  void updateLayout(Size size) {
    // 检测窗口大小变化
    final sizeChanged = _lastScreenSize != size;
    _lastScreenSize = size;
    
    final newMaxTracksPerLayer = _calculateMaxTracksPerLayer(size);
    if (newMaxTracksPerLayer != _maxTracksPerLayer || sizeChanged) {
      final oldMaxTracksPerLayer = _maxTracksPerLayer;
      _maxTracksPerLayer = newMaxTracksPerLayer;
      _availableTracks = List<bool>.filled(_maxTracksPerLayer, true);
      
      // 窗口大小变化时，调整超出新轨道范围的弹幕
      if (sizeChanged) {
        _adjustTracksForSizeChange(oldMaxTracksPerLayer);
      } else {
        _resetInvalidTracks();
      }
    }
  }

  /// 计算单层最大轨道数
  int _calculateMaxTracksPerLayer(Size size) {
    if (size.height <= 0) return 0;
    return (size.height * config.screenUsageRatio / config.trackHeight).floor();
  }

  /// 重置无效轨道（当屏幕尺寸变化时）
  void _resetInvalidTracks() {
    final invalidItems = <GPUDanmakuItem>[];
    _trackItems.removeWhere((trackId, items) {
      if (trackId >= _maxTracksPerLayer) {
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
    if (_maxTracksPerLayer <= 0) return false;
    
    // 如果弹幕已经有轨道，直接返回成功
    if (item.trackId >= 0 && item.trackId < _maxTracksPerLayer * _currentLayerCount) {
      return true;
    }
    
    // 从第一层开始尝试分配轨道
    for (int layerIndex = 0; layerIndex < _currentLayerCount; layerIndex++) {
      final assigned = _tryAssignTrackInLayer(item, layerIndex);
      if (assigned) {
        return true;
      }
    }
    
    // 如果所有现有层都满了，创建新层
    _createNewLayer();
    return _tryAssignTrackInLayer(item, _currentLayerCount - 1);
  }

  /// 在指定层尝试分配轨道
  bool _tryAssignTrackInLayer(GPUDanmakuItem item, int layerIndex) {
    // 重置轨道可用状态
    _availableTracks.fillRange(0, _maxTracksPerLayer, true);
    
    // 标记已占用的轨道（只考虑当前层）
    final layerStartTrack = layerIndex * _maxTracksPerLayer;
    final layerEndTrack = (layerIndex + 1) * _maxTracksPerLayer;
    
    _trackItems.forEach((trackId, items) {
      if (trackId >= layerStartTrack && trackId < layerEndTrack) {
        final localTrackId = trackId - layerStartTrack;
        if (localTrackId < _maxTracksPerLayer) {
          _availableTracks[localTrackId] = false;
        }
      }
    });
    
    // 在当前层寻找可用轨道
    for (int i = 0; i < _maxTracksPerLayer; i++) {
      if (_availableTracks[i]) {
        final globalTrackId = layerStartTrack + i;
        item.trackId = globalTrackId;
        _trackItems.putIfAbsent(globalTrackId, () => []).add(item);
        debugPrint('GPUDanmakuLayeredTrackManager: 弹幕分配到轨道 $globalTrackId (层 ${layerIndex + 1}, 本地轨道 ${i + 1})');
        return true;
      }
    }
    
    return false;
  }

  /// 检查是否应该创建新层（已废弃，现在直接创建新层）
  @deprecated
  bool _shouldCreateNewLayer() {
    return false;
  }

  /// 创建新层
  void _createNewLayer() {
    _currentLayerCount++;
    debugPrint('GPUDanmakuLayeredTrackManager: 创建新层，当前层数: $_currentLayerCount');
  }

  /// 移除弹幕项目
  /// 
  /// 参数:
  /// - item: 弹幕项目
  void removeItem(GPUDanmakuItem item) {
    if (item.trackId >= 0) {
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
    _currentLayerCount = 1;
    if (_availableTracks.isNotEmpty) {
      _availableTracks.fillRange(0, _maxTracksPerLayer, true);
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
    final layerIndex = trackId ~/ _maxTracksPerLayer;
    final localTrackId = trackId % _maxTracksPerLayer;
    
    switch (trackType) {
      case DanmakuTrackType.top:
        // 顶部弹幕从屏幕顶部开始，每层独立排列
        final y = localTrackId * (config.fontSize + config.danmakuBottomMargin);
        // 确保弹幕不会超出屏幕顶部边界
        return y.clamp(0.0, screenHeight - config.fontSize);
      case DanmakuTrackType.bottom:
        // 底部弹幕从屏幕底部开始，向上排列
        final totalHeight = _maxTracksPerLayer * (config.fontSize + config.danmakuBottomMargin);
        final y = screenHeight - totalHeight + localTrackId * (config.fontSize + config.danmakuBottomMargin);
        // 确保弹幕不会超出屏幕底部边界
        return y.clamp(0.0, screenHeight - config.fontSize);
    }
  }

  /// 获取轨道所属的层数
  /// 
  /// 参数:
  /// - trackId: 轨道ID
  /// 
  /// 返回: 层数（从1开始）
  int getTrackLayer(int trackId) {
    return (trackId ~/ _maxTracksPerLayer) + 1;
  }

  /// 获取轨道在层内的本地ID
  /// 
  /// 参数:
  /// - trackId: 轨道ID
  /// 
  /// 返回: 层内轨道ID（从0开始）
  int getLocalTrackId(int trackId) {
    return trackId % _maxTracksPerLayer;
  }

  /// 获取最大轨道数（单层）
  int get maxTracksPerLayer => _maxTracksPerLayer;

  /// 获取当前层数
  int get currentLayerCount => _currentLayerCount;

  /// 获取当前使用的轨道数
  int get usedTracks => _trackItems.length;

  /// 检查轨道是否可用
  bool isTrackAvailable(int trackId) {
    final layerIndex = trackId ~/ _maxTracksPerLayer;
    final localTrackId = trackId % _maxTracksPerLayer;
    
    return localTrackId < _maxTracksPerLayer && 
           localTrackId >= 0 && 
           layerIndex < _currentLayerCount &&
           !_trackItems.containsKey(trackId);
  }

  /// 调试信息
  Map<String, dynamic> getDebugInfo() {
    return {
      'maxTracksPerLayer': _maxTracksPerLayer,
      'currentLayerCount': _currentLayerCount,
      'usedTracks': usedTracks,
      'trackType': trackType.toString(),
      'trackItems': _trackItems.map((key, value) => MapEntry(key.toString(), value.length)),
    };
  }

  /// 窗口大小变化时调整轨道
  void _adjustTracksForSizeChange(int oldMaxTracksPerLayer) {
    // 只处理超出新轨道范围的弹幕
    final invalidItems = <GPUDanmakuItem>[];
    _trackItems.removeWhere((trackId, items) {
      if (trackId >= _maxTracksPerLayer) {
        // 收集需要重新分配的项目
        for (final item in items) {
          item.resetTrack();
          invalidItems.add(item);
        }
        return true;
      }
      return false;
    });
    
    // 重新分配超出范围的弹幕
    for (final item in invalidItems) {
      assignTrack(item);
    }
  }
}

/// 弹幕轨道类型
enum DanmakuTrackType {
  /// 顶部弹幕
  top,
  /// 底部弹幕
  bottom,
} 