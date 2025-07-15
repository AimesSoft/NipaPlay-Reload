import 'package:flutter/material.dart';
import 'danmaku_content_item.dart';
import 'danmaku_item.dart';
import 'utils.dart';
import 'dart:math' as math;

/// 🔥 轨道信息类
class TrackInfo {
  final int trackIndex;
  final double yPosition;
  final List<DanmakuItem> scrollItems;
  final List<DanmakuItem> topItems;
  final List<DanmakuItem> bottomItems;
  final List<DanmakuItem> overflowScrollItems;
  final List<DanmakuItem> overflowTopItems;
  final List<DanmakuItem> overflowBottomItems;
  
  TrackInfo({
    required this.trackIndex,
    required this.yPosition,
  }) : scrollItems = [],
       topItems = [],
       bottomItems = [],
       overflowScrollItems = [],
       overflowTopItems = [],
       overflowBottomItems = [];
  
  /// 获取轨道上的总弹幕数量
  int get totalCount => scrollItems.length + topItems.length + bottomItems.length +
                       overflowScrollItems.length + overflowTopItems.length + overflowBottomItems.length;
  
  /// 检查轨道是否为空
  bool get isEmpty => totalCount == 0;
  
  /// 获取指定类型的弹幕列表
  List<DanmakuItem> getItemsOfType(DanmakuItemType type, {bool overflow = false}) {
    switch (type) {
      case DanmakuItemType.scroll:
        return overflow ? overflowScrollItems : scrollItems;
      case DanmakuItemType.top:
        return overflow ? overflowTopItems : topItems;
      case DanmakuItemType.bottom:
        return overflow ? overflowBottomItems : bottomItems;
    }
  }
  
  /// 添加弹幕到轨道
  void addItem(DanmakuItem item, {bool overflow = false}) {
    final targetList = getItemsOfType(item.content.type, overflow: overflow);
    targetList.add(item);
  }
  
  /// 从轨道移除弹幕
  void removeItem(DanmakuItem item, {bool overflow = false}) {
    final targetList = getItemsOfType(item.content.type, overflow: overflow);
    targetList.remove(item);
  }
  
  /// 清空轨道
  void clear() {
    scrollItems.clear();
    topItems.clear();
    bottomItems.clear();
    overflowScrollItems.clear();
    overflowTopItems.clear();
    overflowBottomItems.clear();
  }
}

/// 🔥 弹幕轨道管理员 - 负责轨道分配、状态跟踪和恢复管理
class DanmakuTrackManager {
  /// 轨道信息列表
  final List<TrackInfo> _tracks = [];
  
  /// 视图宽度
  double _viewWidth = 0;
  
  /// 当前时间tick
  int _currentTick = 0;
  
  /// 弹幕滚动时间
  double _duration = 10.0;
  
  /// 🔥 移除交叉绘制策略变量（不再需要）
  
  /// 初始化轨道
  void initializeTracks(List<double> trackYPositions, double viewWidth, double duration) {
    _viewWidth = viewWidth;
    _duration = duration;
    _tracks.clear();
    
    for (int i = 0; i < trackYPositions.length; i++) {
      _tracks.add(TrackInfo(
        trackIndex: i,
        yPosition: trackYPositions[i],
      ));
    }
    
    // 🔥 移除交叉绘制策略变量的初始化（不再需要）
  }
  
  /// 更新当前时间
  void updateCurrentTick(int tick) {
    _currentTick = tick;
  }
  
  /// 根据Y位置精确获取轨道编号
  int getTrackIndexFromYPosition(double yPosition) {
    for (int i = 0; i < _tracks.length; i++) {
      if ((_tracks[i].yPosition - yPosition).abs() < 1.0) {
        return i;
      }
    }
    return 0;
  }
  
  /// 获取轨道的Y位置
  double getTrackYPosition(int trackIndex) {
    if (trackIndex >= 0 && trackIndex < _tracks.length) {
      return _tracks[trackIndex].yPosition;
    }
    return _tracks.isNotEmpty ? _tracks[0].yPosition : 0.0;
  }
  
  /// 🔥 滚动弹幕轨道分配策略 - 完全照抄NipaPlay的算法
  int? assignScrollTrack(double danmakuWidth, {int? preferredTrack, bool massiveMode = false}) {
    if (preferredTrack != null && preferredTrack != -1 && preferredTrack >= 0 && preferredTrack < _tracks.length) {
      return preferredTrack;
    }
    
    for (int i = 0; i < _tracks.length; i++) {
      if (_canAddScrollDanmakuToTrack(i, danmakuWidth)) {
        return i;
      }
    }
    
    // 海量弹幕模式，随机选择一个轨道
    if (massiveMode) {
      return math.Random().nextInt(_tracks.length);
    }
    
    return null;
  }
  
  bool _canAddScrollDanmakuToTrack(int trackIndex, double newDanmakuWidth) {
    final track = _tracks[trackIndex];
    final items = [...track.scrollItems, ...track.overflowScrollItems];
    final currentTime = _currentTick / 1000.0;


    for (var item in items) {
      final existingTime = item.creationTime / 1000.0;
      final elapsed = currentTime - existingTime;
      if (elapsed < 0) continue;


      final xPosition = _viewWidth - (elapsed / _duration) * (_viewWidth + item.width);
      final existingEndPosition = xPosition + item.width;


      if (_viewWidth - existingEndPosition < 0) {
        return false;
      }


      if (item.width < newDanmakuWidth) {
        final existingItemProgress = (_viewWidth - xPosition) / (item.width + _viewWidth);
        final newItemProgress = _viewWidth / (_viewWidth + newDanmakuWidth);
        if (1 - existingItemProgress > newItemProgress) {
          return false;
        }
      }
    }
    return true;
  }

  
  /// 🔥 移除交叉绘制相关方法（不再需要）
  
  /// 🔥 新增：动态滚动弹幕碰撞检测（照抄NipaPlay的逻辑）
  bool canAddScrollDanmakuToTrackDynamic(int trackIndex, DanmakuItem newItem, double danmakuWidth) {
    if (trackIndex < 0 || trackIndex >= _tracks.length) return false;
    
    final track = _tracks[trackIndex];
    final currentTime = _currentTick / 1000.0;
    
    // 🔥 新增：轨道密度检测 - 如果轨道太满，直接拒绝
    if (_isScrollTrackFull(trackIndex, currentTime)) {
      return false;
    }
    
    // 检查与现有滚动弹幕的动态碰撞
    for (var existingItem in track.scrollItems) {
      if (_checkScrollDanmakuCollision(existingItem, newItem, danmakuWidth, currentTime)) {
        return false;
      }
    }
    
    // 检查与溢出层滚动弹幕的动态碰撞
    for (var existingItem in track.overflowScrollItems) {
      if (_checkScrollDanmakuCollision(existingItem, newItem, danmakuWidth, currentTime)) {
        return false;
      }
    }
    
    return true;
  }
  
  /// 🔥 新增：轨道密度检测（完全照抄NipaPlay的算法）
  bool _isScrollTrackFull(int trackIndex, double currentTime) {
    if (trackIndex < 0 || trackIndex >= _tracks.length) return true;
    
    final track = _tracks[trackIndex];
    
    // 🔥 完全照抄NipaPlay：只统计5秒内的弹幕（而不是10秒）
    final visibleItems = <DanmakuItem>[];
    
    // 添加主层弹幕
    for (var item in track.scrollItems) {
      final itemTime = item.creationTime / 1000.0;
      final timeDiff = currentTime - itemTime;
      if (timeDiff >= 0 && timeDiff <= 5.0) { // 🔥 改为5秒，和NipaPlay一样
        visibleItems.add(item);
      }
    }
    
    // 添加溢出层弹幕
    for (var item in track.overflowScrollItems) {
      final itemTime = item.creationTime / 1000.0;
      final timeDiff = currentTime - itemTime;
      if (timeDiff >= 0 && timeDiff <= 5.0) { // 🔥 改为5秒，和NipaPlay一样
        visibleItems.add(item);
      }
    }
    
    // 🔥 完全照抄NipaPlay：计算总宽度和重叠情况
    double totalWidth = 0;
    double maxOverlap = 0;
    
    // 按左边界排序
    visibleItems.sort((a, b) {
      final aTime = a.creationTime / 1000.0;
      final bTime = b.creationTime / 1000.0;
      final aElapsed = currentTime - aTime;
      final bElapsed = currentTime - bTime;
      final aPosition = _viewWidth - (aElapsed / 10.0) * (_viewWidth + a.width);
      final bPosition = _viewWidth - (bElapsed / 10.0) * (_viewWidth + b.width);
      return aPosition.compareTo(bPosition);
    });
    
    // 计算重叠情况
    for (int i = 0; i < visibleItems.length; i++) {
      final current = visibleItems[i];
      totalWidth += current.width;
      
      // 检查与后续弹幕的重叠
      for (int j = i + 1; j < visibleItems.length; j++) {
        final next = visibleItems[j];
        final currenttimeI = current.creationTime / 1000.0;
        final nexttimeI = next.creationTime / 1000.0;
        final currentElapsed = currentTime - currenttimeI;
        final nextElapsed = currentTime - nexttimeI;
        final currentPosition = _viewWidth - (currentElapsed / 10.0) * (_viewWidth + current.width);
        final nextPosition = _viewWidth - (nextElapsed / 10.0) * (_viewWidth + next.width);
        final currentRight = currentPosition + current.width;
        final nextLeft = nextPosition;
        
        if (currentRight > nextLeft) {
          final overlap = currentRight - nextLeft;
          maxOverlap = math.max(maxOverlap, overlap);
        } else {
          break; // 由于已排序，后续弹幕不会重叠
        }
      }
    }
    
    // 🔥 完全照抄NipaPlay：考虑重叠情况，调整轨道密度判断
    final adjustedWidth = totalWidth - maxOverlap;
    const safetyFactor = 0.7; // 🔥 和NipaPlay一样的安全系数
    
    return adjustedWidth > _viewWidth * safetyFactor;
  }
  
  /// 🔥 改进：滚动弹幕动态碰撞检测（完全照抄NipaPlay的简单算法）
  bool _checkScrollDanmakuCollision(DanmakuItem existingItem, DanmakuItem newItem, double newDanmakuWidth, double currentTime) {
    final existingTime = existingItem.creationTime / 1000.0;
    final newTime = newItem.creationTime / 1000.0;
    final existingWidth = existingItem.width;
    
    // 🔥 滚动弹幕运动时间为10秒（从右到左完全穿过屏幕）
    const scrollDuration = 10.0;
    
    // 计算现有弹幕的当前位置
    final existingElapsed = currentTime - existingTime;
    final existingPosition = _viewWidth - (existingElapsed / scrollDuration) * (_viewWidth + existingWidth);
    final existingLeft = existingPosition;
    final existingRight = existingPosition + existingWidth;
    
    // 计算新弹幕的当前位置
    final newElapsed = currentTime - newTime;
    final newPosition = _viewWidth - (newElapsed / scrollDuration) * (_viewWidth + newDanmakuWidth);
    final newLeft = newPosition;
    final newRight = newPosition + newDanmakuWidth;
    
    // 🔥 完全照抄NipaPlay：减小安全距离到2%（而不是5%）
    final safetyMargin = _viewWidth * 0.02;
    
    // 🔥 移除所有过于严格的检测：
    // - 移除时间间隔检测
    // - 移除未来碰撞预测
    // - 只保留基本的位置重叠检测
    
    // 检查位置重叠
    return (existingRight + safetyMargin > newLeft) && 
           (existingLeft - safetyMargin < newRight);
  }

  /// 🔥 新增：基于碰撞箱的精确碰撞检测
  bool checkCollisionBoxOverlap(DanmakuItem item1, DanmakuItem item2, double fontSize, {double safetyMargin = 5.0}) {
    // 计算两个弹幕的碰撞箱
    final box1 = Utils.calculateCollisionBox(item1, fontSize);
    final box2 = Utils.calculateCollisionBox(item2, fontSize);
    
    // 添加安全边距
    final expandedBox1 = Rect.fromLTWH(
      box1.left - safetyMargin,
      box1.top - safetyMargin,
      box1.width + 2 * safetyMargin,
      box1.height + 2 * safetyMargin,
    );
    
    final expandedBox2 = Rect.fromLTWH(
      box2.left - safetyMargin,
      box2.top - safetyMargin,
      box2.width + 2 * safetyMargin,
      box2.height + 2 * safetyMargin,
    );
    
    // 检查碰撞箱是否重叠
    final overlap = expandedBox1.overlaps(expandedBox2);
    
    return overlap;
  }
  
  /// 🔥 新增：基于碰撞箱的滚动弹幕轨道检测
  bool canAddScrollDanmakuToTrack(int trackIndex, DanmakuItem newItem, double fontSize) {
    if (trackIndex < 0 || trackIndex >= _tracks.length) return false;
    
    final track = _tracks[trackIndex];
    
    // 检查与现有滚动弹幕的碰撞
    for (var existingItem in track.scrollItems) {
      if (checkCollisionBoxOverlap(newItem, existingItem, fontSize)) {
        return false;
      }
    }
    
    // 检查与溢出层滚动弹幕的碰撞
    for (var existingItem in track.overflowScrollItems) {
      if (checkCollisionBoxOverlap(newItem, existingItem, fontSize)) {
        return false;
      }
    }
    
    return true;
  }
  
  /// 🔥 新增：基于碰撞箱的静态弹幕轨道检测
  bool canAddStaticDanmakuToTrack(int trackIndex, DanmakuItem newItem, double fontSize) {
    if (trackIndex < 0 || trackIndex >= _tracks.length) return false;
    
    final track = _tracks[trackIndex];
    
    // 检查与现有顶部弹幕的碰撞
    for (var existingItem in track.topItems) {
      if (checkCollisionBoxOverlap(newItem, existingItem, fontSize)) {
        return false;
      }
    }
    
    // 检查与现有底部弹幕的碰撞
    for (var existingItem in track.bottomItems) {
      if (checkCollisionBoxOverlap(newItem, existingItem, fontSize)) {
        return false;
      }
    }
    
    // 检查与溢出层弹幕的碰撞
    for (var existingItem in track.overflowTopItems) {
      if (checkCollisionBoxOverlap(newItem, existingItem, fontSize)) {
        return false;
      }
    }
    
    for (var existingItem in track.overflowBottomItems) {
      if (checkCollisionBoxOverlap(newItem, existingItem, fontSize)) {
        return false;
      }
    }
    
    return true;
  }
  
  /// 🔥 顶部弹幕轨道分配策略 - 完全照抄NipaPlay的算法
  int? assignTopTrack({int? preferredTrack}) {
    // 🔥 修复：如果有指定的轨道编号，优先使用该轨道（用于状态恢复）
    if (preferredTrack != null && preferredTrack != -1 && preferredTrack >= 0 && preferredTrack < _tracks.length) {
      return preferredTrack;
    }
    
    // 从顶部轨道开始查找可用轨道
    for (int i = 0; i < _tracks.length; i++) {
      final track = _tracks[i];
      if (track.topItems.isEmpty && track.overflowTopItems.isEmpty) {
        return i;
      }
    }
    
    return null;
  }
  
  /// 🔥 底部弹幕轨道分配策略 - 完全照抄NipaPlay的算法
  int? assignBottomTrack({int? preferredTrack}) {
    // 🔥 修复：如果有指定的轨道编号，优先使用该轨道（用于状态恢复）
    if (preferredTrack != null && preferredTrack != -1 && preferredTrack >= 0 && preferredTrack < _tracks.length) {
      return preferredTrack;
    }
    
    // 从底部轨道开始查找可用轨道
    for (int i = _tracks.length - 1; i >= 0; i--) {
      final track = _tracks[i];
      if (track.bottomItems.isEmpty && track.overflowBottomItems.isEmpty) {
        return i;
      }
    }
    
    return null;
  }
  
  /// 🔥 新增：检查两个弹幕是否存在时间重叠（照抄NipaPlay的逻辑）
  bool _checkTimeOverlap(DanmakuItem existingItem, DanmakuItem newItem) {
    final existingTime = existingItem.creationTime / 1000.0; // 转换为秒
    final newTime = newItem.creationTime / 1000.0; // 转换为秒
    
    // 计算两个弹幕的显示时间范围
    final existingStartTime = existingTime;
    final existingEndTime = existingTime + 5; // 顶部和底部弹幕显示5秒
    
    final newStartTime = newTime;
    final newEndTime = newTime + 5;
    
    // 增加安全时间间隔，避免弹幕过于接近
    const safetyTime = 0.5; // 0.5秒的安全时间
    
    // 如果两个弹幕的显示时间有重叠，且间隔小于安全时间，则会发生重叠
    return (newStartTime <= existingEndTime + safetyTime && newEndTime + safetyTime >= existingStartTime);
  }
  
  /// 获取轨道状态信息
  String getTrackStatus() {
    final status = StringBuffer();
    status.writeln('🔥 轨道管理员状态报告：');
    
    status.writeln('🔥 详细轨道信息：');
    for (int i = 0; i < _tracks.length; i++) {
      final track = _tracks[i];
      
      status.writeln('  轨道$i: 滚动${track.scrollItems.length}条, 顶部${track.topItems.length}条, 底部${track.bottomItems.length}条');
      if (track.overflowScrollItems.isNotEmpty || track.overflowTopItems.isNotEmpty || track.overflowBottomItems.isNotEmpty) {
        status.writeln('    溢出层: 滚动${track.overflowScrollItems.length}条, 顶部${track.overflowTopItems.length}条, 底部${track.overflowBottomItems.length}条');
      }
    }
    
    return status.toString();
  }
  
  /// 添加弹幕到轨道
  void addDanmakuToTrack(int trackIndex, DanmakuItem item, {bool overflow = false}) {
    if (trackIndex >= 0 && trackIndex < _tracks.length) {
      _tracks[trackIndex].addItem(item, overflow: overflow);
    }
  }
  
  /// 从轨道移除弹幕
  void removeDanmakuFromTrack(int trackIndex, DanmakuItem item, {bool overflow = false}) {
    if (trackIndex >= 0 && trackIndex < _tracks.length) {
      _tracks[trackIndex].removeItem(item, overflow: overflow);
    }
  }
  
  /// 清空所有轨道
  void clearAllTracks() {
    for (final track in _tracks) {
      track.clear();
    }
    // 🔥 移除交叉绘制状态重置（不再需要）
  }
  
  /// 🔥 修改：只清空轨道弹幕，不重置交叉绘制状态，保持轨道分配的连续性
  void clearTrackContents(
    List<DanmakuItem> scrollItems,
    List<DanmakuItem> topItems,
    List<DanmakuItem> bottomItems,
    List<DanmakuItem> overflowScrollItems,
    List<DanmakuItem> overflowTopItems,
    List<DanmakuItem> overflowBottomItems,
  ) {
    // 🔥 关键修复：清空轨道弹幕
    for (final track in _tracks) {
      track.clear();
    }
    
    // 🔥 重新添加弹幕到轨道（不需要保持交叉绘制状态）
    for (var item in scrollItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item);
    }
    
    for (var item in topItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item);
    }
    
    for (var item in bottomItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item);
    }
    
    for (var item in overflowScrollItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item, overflow: true);
    }
    
    for (var item in overflowTopItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item, overflow: true);
    }
    
    for (var item in overflowBottomItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item, overflow: true);
    }
  }

  /// 🔥 新增：彻底重置所有状态的方法（用于切换视频等场景）
  void resetAll() {
    // 清空轨道内容
    for (final track in _tracks) {
      track.clear();
    }
    
    // 🔥 移除交叉绘制策略状态重置（不再需要）
  }
  
  /// 获取轨道数量
  int get trackCount => _tracks.length;
  
  /// 获取指定轨道的信息
  TrackInfo? getTrackInfo(int trackIndex) {
    if (trackIndex >= 0 && trackIndex < _tracks.length) {
      return _tracks[trackIndex];
    }
    return null;
  }

  /// 🔥 修改：同步轨道状态 - 根据实际弹幕列表重新构建轨道状态
  void syncTrackStates(List<DanmakuItem> scrollItems, List<DanmakuItem> topItems, List<DanmakuItem> bottomItems,
                      List<DanmakuItem> overflowScrollItems, List<DanmakuItem> overflowTopItems, List<DanmakuItem> overflowBottomItems) {
    // 🔥 修改：只清空轨道弹幕
    for (final track in _tracks) {
      track.clear();
    }
    
    // 重新添加弹幕到轨道
    for (var item in scrollItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item);
    }
    
    for (var item in topItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item);
    }
    
    for (var item in bottomItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item);
    }
    
    for (var item in overflowScrollItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item, overflow: true);
    }
    
    for (var item in overflowTopItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item, overflow: true);
    }
    
    for (var item in overflowBottomItems) {
      final trackIndex = getTrackIndexFromYPosition(item.yPosition);
      addDanmakuToTrack(trackIndex, item, overflow: true);
    }
  }
} 