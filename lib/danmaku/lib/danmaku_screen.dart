import 'utils.dart';
import 'package:flutter/material.dart';
import 'danmaku_item.dart';
import 'scroll_danmaku_painter.dart';
import 'static_danmaku_painter.dart';
import 'danmaku_controller.dart';
import 'dart:ui' as ui;
import 'danmaku_option.dart';
import 'danmaku_content_item.dart';
import 'dart:math';
import '../../utils/globals.dart' as globals;
import 'danmaku_track_manager.dart'; // 🔥 新增：轨道管理员

class DanmakuScreen extends StatefulWidget {
  // 创建Screen后返回控制器
  final Function(DanmakuController) createdController;
  final DanmakuOption option;

  const DanmakuScreen({
    required this.createdController,
    required this.option,
    super.key,
  });

  @override
  State<DanmakuScreen> createState() => _DanmakuScreenState();
}

class _DanmakuScreenState extends State<DanmakuScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// 视图宽度
  double _viewWidth = 0;

  /// 弹幕控制器
  late DanmakuController _controller;

  /// 弹幕动画控制器
  late AnimationController _animationController;

  /// 静态弹幕动画控制器
  late AnimationController _staticAnimationController;

  /// 弹幕配置
  late DanmakuOption _option;

  /// 滚动弹幕
  final List<DanmakuItem> _scrollDanmakuItems = [];

  /// 顶部弹幕
  final List<DanmakuItem> _topDanmakuItems = [];

  /// 底部弹幕
  final List<DanmakuItem> _bottomDanmakuItems = [];

  /// 🔥 新增：溢出弹幕数据 - 溢出层
  final List<DanmakuItem> _overflowScrollDanmakuItems = [];
  final List<DanmakuItem> _overflowTopDanmakuItems = [];
  final List<DanmakuItem> _overflowBottomDanmakuItems = [];

  /// 弹幕高度
  late double _danmakuHeight;

  /// 弹幕轨道数
  late int _trackCount;

  /// 弹幕轨道位置
  final List<double> _trackYPositions = [];

  /// 🔥 新增：轨道管理员
  final DanmakuTrackManager _trackManager = DanmakuTrackManager();

  /// 内部计时器
  late int _tick;

  /// 运行状态
  bool _running = false;

  /// 🔥 添加轨道分配计数器，确保均匀分布
  int _currentScrollTrack = 0;
  int _currentTopTrack = 0;
  int _currentBottomTrack = 0;

  /// 🔥 新增：溢出层轨道分配计数器
  int _overflowScrollTrack = 0;
  int _overflowTopTrack = 0;
  int _overflowBottomTrack = 0;

  /// 🔥 修改：直接使用播放暂停状态，不需要额外的时间暂停状态
  bool _isPaused = false;

  /// 🔥 新增：标记是否是时间跳转或状态恢复场景
  bool _isTimeJumpOrRestoring = false;
  
  /// 🔥 新增：设置时间跳转或状态恢复标记
  void setTimeJumpOrRestoring(bool value) {
    _isTimeJumpOrRestoring = value;
  }

  @override
  void initState() {
    super.initState();
    // 计时器初始化
    _tick = 0;
    _running = true; // 🔥 确保初始化时就开始运行
    _startTick();
    _option = widget.option;
    _controller = DanmakuController(
      onAddDanmaku: addDanmaku,
      onUpdateOption: updateOption,
      onPause: pause,
      onResume: resume,
      onClear: clearDanmakus,
      onResetAll: resetAll, // 🔥 新增：彻底重置回调
      onGetCurrentTick: getCurrentTick, // 🔥 新增：获取当前时间tick
      onSetCurrentTick: setCurrentTick, // 🔥 新增：设置当前时间tick
      onGetDanmakuStates: getDanmakuStates, // 🔥 新增：获取弹幕状态
      onSetTimeJumpOrRestoring: setTimeJumpOrRestoring, // 🔥 新增：设置时间跳转或状态恢复标记
    );
    _controller.option = _option;
    widget.createdController.call(
      _controller,
    );

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _option.duration),
    )..repeat();

    _staticAnimationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _option.duration),
    );

    WidgetsBinding.instance.addObserver(this);
  }

  /// 处理 Android/iOS 应用后台或熄屏导致的动画问题
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      pause();
    }
  }

  @override
  void dispose() {
    _running = false;
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _staticAnimationController.dispose();
    super.dispose();
  }

  /// 🔥 新增：获取当前时间tick
  int getCurrentTick() {
    return _tick;
  }

  /// 🔥 新增：设置当前时间tick（用于模拟弹幕按原始时间添加）
  void setCurrentTick(int tick) {
    _tick = tick;
    _trackManager.updateCurrentTick(_tick);
  }

  /// 添加弹幕
  void addDanmaku(DanmakuContentItem content) {
    if (!_running || !mounted) {
      return;
    }
    
    // 🔥 检查是否是时间跳转场景（不包括弹幕状态恢复）
    // 如果指定了轨道编号且有时间偏移，说明是弹幕状态恢复，不需要时间跳转逻辑
    final isStateRestore = content.trackIndex != null && content.timeOffset > 0;
    final isTimeJumpOrRestoring = _isTimeJumpOrRestoring && !isStateRestore;
    
    // 在这里提前创建 Paragraph 缓存防止卡顿
    final textPainter = TextPainter(
      text: TextSpan(
          text: content.text, style: TextStyle(fontSize: _option.fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final danmakuWidth = textPainter.width;

    final ui.Paragraph paragraph =
        Utils.generateParagraph(content, danmakuWidth, _option.fontSize);

    ui.Paragraph? strokeParagraph;

    // 🔥 关键修改：考虑时间偏移，模拟弹幕已经运动了一段时间
    final adjustedCreationTime = _tick - content.timeOffset;

    // 🔥 完全照抄NipaPlay的轨道分配策略：优先寻找最合适的轨道
    bool danmakuAdded = false;
    
    if (content.type == DanmakuItemType.scroll && !_option.hideScroll) {
      // 🔥 创建临时弹幕项目用于碰撞检测
      final tempDanmakuItem = DanmakuItem(
          content: content,
          xPosition: _viewWidth,
          yPosition: 0, // 临时Y位置，会在分配轨道后更新
          width: danmakuWidth,
          creationTime: adjustedCreationTime,
          paragraph: paragraph,
          strokeParagraph: strokeParagraph);
      
      // 🔥 使用轨道管理员分配滚动弹幕轨道（包括碰撞检测）
      final availableTrack = _trackManager.assignScrollTrack(
        danmakuWidth, 
        preferredTrack: content.trackIndex, // 优先使用指定轨道（状态恢复）
        newItem: tempDanmakuItem,
        fontSize: _option.fontSize,
        isTimeJump: isTimeJumpOrRestoring, // 🔥 关键修复：正确传递时间跳转标记
      );
      
      if (availableTrack != null) {
        final yPosition = _trackManager.getTrackYPosition(availableTrack);
        final danmakuItem = DanmakuItem(
            content: content,
            xPosition: _viewWidth,
            yPosition: yPosition,
            width: danmakuWidth,
            creationTime: adjustedCreationTime,
            paragraph: paragraph,
            strokeParagraph: strokeParagraph);
        
        _scrollDanmakuItems.add(danmakuItem);
        _trackManager.addDanmakuToTrack(availableTrack, danmakuItem);
        danmakuAdded = true;
      } else {
        // 🔥 主层满了，尝试分配到溢出层
        if (_option.massiveMode && _trackYPositions.isNotEmpty) {
          // 溢出层重新从第一轨道开始分配
          _overflowScrollTrack = (_overflowScrollTrack + 1) % _trackYPositions.length;
          final yPosition = _trackManager.getTrackYPosition(_overflowScrollTrack);
          final danmakuItem = DanmakuItem(
              content: content,
              xPosition: _viewWidth,
              yPosition: yPosition,
              width: danmakuWidth,
              creationTime: adjustedCreationTime,
              paragraph: paragraph,
              strokeParagraph: strokeParagraph);
          
          _overflowScrollDanmakuItems.add(danmakuItem);
          _trackManager.addDanmakuToTrack(_overflowScrollTrack, danmakuItem, overflow: true);
          danmakuAdded = true;
        }
        // 如果不允许堆叠，弹幕会被丢弃（danmakuAdded保持false）
      }
    } else if (content.type == DanmakuItemType.top && !_option.hideTop) {
      // 🔥 创建临时弹幕项目用于碰撞检测
      final tempDanmakuItem = DanmakuItem(
          content: content,
          xPosition: (_viewWidth - danmakuWidth) / 2,
          yPosition: 0, // 临时Y位置，会在分配轨道后更新
          width: danmakuWidth,
          creationTime: adjustedCreationTime,
          paragraph: paragraph,
          strokeParagraph: strokeParagraph);
      
      // 🔥 使用轨道管理员分配顶部弹幕轨道（包括碰撞检测）
      final availableTrack = _trackManager.assignTopTrack(
        preferredTrack: content.trackIndex, // 优先使用指定轨道（状态恢复）
        newItem: tempDanmakuItem,
        fontSize: _option.fontSize,
        isTimeJump: isTimeJumpOrRestoring, // 🔥 关键修复：正确传递时间跳转标记
      );
      
      if (availableTrack != null) {
        final yPosition = _trackManager.getTrackYPosition(availableTrack);
        final danmakuItem = DanmakuItem(
            content: content,
            xPosition: (_viewWidth - danmakuWidth) / 2,
            yPosition: yPosition,
            width: danmakuWidth,
            creationTime: adjustedCreationTime,
            paragraph: paragraph,
            strokeParagraph: strokeParagraph);
        
        _topDanmakuItems.add(danmakuItem);
        _trackManager.addDanmakuToTrack(availableTrack, danmakuItem);
        danmakuAdded = true;
      }
      
      // 🔥 主层满了，尝试分配到溢出层
      if (!danmakuAdded && _option.massiveMode && _trackYPositions.isNotEmpty) {
        // 溢出层重新从第一轨道开始分配
        _overflowTopTrack = (_overflowTopTrack + 1) % _trackYPositions.length;
        final yPosition = _trackManager.getTrackYPosition(_overflowTopTrack);
        final danmakuItem = DanmakuItem(
            content: content,
            xPosition: (_viewWidth - danmakuWidth) / 2,
            yPosition: yPosition,
            width: danmakuWidth,
            creationTime: adjustedCreationTime,
            paragraph: paragraph,
            strokeParagraph: strokeParagraph);
        
        _overflowTopDanmakuItems.add(danmakuItem);
        _trackManager.addDanmakuToTrack(_overflowTopTrack, danmakuItem, overflow: true);
        danmakuAdded = true;
      }
    } else if (content.type == DanmakuItemType.bottom && !_option.hideBottom) {
      // 🔥 创建临时弹幕项目用于碰撞检测
      final tempDanmakuItem = DanmakuItem(
          content: content,
          xPosition: (_viewWidth - danmakuWidth) / 2,
          yPosition: 0, // 临时Y位置，会在分配轨道后更新
          width: danmakuWidth,
          creationTime: adjustedCreationTime,
          paragraph: paragraph,
          strokeParagraph: strokeParagraph);
      
      // 🔥 使用轨道管理员分配底部弹幕轨道（包括碰撞检测）
      final availableTrack = _trackManager.assignBottomTrack(
        preferredTrack: content.trackIndex, // 优先使用指定轨道（状态恢复）
        newItem: tempDanmakuItem,
        fontSize: _option.fontSize,
        isTimeJump: isTimeJumpOrRestoring, // 🔥 关键修复：正确传递时间跳转标记
      );
      
      if (availableTrack != null) {
        final yPosition = _trackManager.getTrackYPosition(availableTrack);
        final danmakuItem = DanmakuItem(
            content: content,
            xPosition: (_viewWidth - danmakuWidth) / 2,
            yPosition: yPosition,
            width: danmakuWidth,
            creationTime: adjustedCreationTime,
            paragraph: paragraph,
            strokeParagraph: strokeParagraph);
        
        _bottomDanmakuItems.add(danmakuItem);
        _trackManager.addDanmakuToTrack(availableTrack, danmakuItem);
        danmakuAdded = true;
      }
      
      // 🔥 主层满了，尝试分配到溢出层
      if (!danmakuAdded && _option.massiveMode && _trackYPositions.isNotEmpty) {
        // 溢出层重新从第一轨道开始分配
        _overflowBottomTrack = (_overflowBottomTrack + 1) % _trackYPositions.length;
        final yPosition = _trackManager.getTrackYPosition(_overflowBottomTrack);
        final danmakuItem = DanmakuItem(
            content: content,
            xPosition: (_viewWidth - danmakuWidth) / 2,
            yPosition: yPosition,
            width: danmakuWidth,
            creationTime: adjustedCreationTime,
            paragraph: paragraph,
            strokeParagraph: strokeParagraph);
        
        _overflowBottomDanmakuItems.add(danmakuItem);
        _trackManager.addDanmakuToTrack(_overflowBottomTrack, danmakuItem, overflow: true);
        danmakuAdded = true;
      }
    }

    // 🔥 修改：只有在未暂停时才启动动画控制器
    if (!_isPaused && _running && mounted) {
      if ((_scrollDanmakuItems.isNotEmpty || _overflowScrollDanmakuItems.isNotEmpty) &&
          !_animationController.isAnimating) {
        _animationController.repeat();
      }
      if ((_topDanmakuItems.isNotEmpty || _bottomDanmakuItems.isNotEmpty ||
          _overflowTopDanmakuItems.isNotEmpty || _overflowBottomDanmakuItems.isNotEmpty)) {
        _staticAnimationController.value = 0;
      }
    }
    // 🔥 关键修复：移除屏幕外滚动弹幕 - 主层和溢出层，同时从轨道管理器中移除
    final expiredScrollItems = _scrollDanmakuItems.where((item) => item.xPosition + item.width < 0).toList();
    for (final item in expiredScrollItems) {
      final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
      _trackManager.removeDanmakuFromTrack(trackIndex, item);
    }
    _scrollDanmakuItems.removeWhere((item) => item.xPosition + item.width < 0);
    
    final expiredOverflowScrollItems = _overflowScrollDanmakuItems.where((item) => item.xPosition + item.width < 0).toList();
    for (final item in expiredOverflowScrollItems) {
      final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
      _trackManager.removeDanmakuFromTrack(trackIndex, item, overflow: true);
    }
    _overflowScrollDanmakuItems.removeWhere((item) => item.xPosition + item.width < 0);
    
    // 🔥 关键修复：移除过期的顶部弹幕 - 主层和溢出层，同时从轨道管理器中移除
    final expiredTopItems = _topDanmakuItems.where((item) => ((_tick - item.creationTime) > (5 * 1000))).toList();
    for (final item in expiredTopItems) {
      final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
      _trackManager.removeDanmakuFromTrack(trackIndex, item);
    }
    _topDanmakuItems.removeWhere((item) => ((_tick - item.creationTime) > (5 * 1000))); // 5秒而不是_option.duration
    
    final expiredOverflowTopItems = _overflowTopDanmakuItems.where((item) => ((_tick - item.creationTime) > (5 * 1000))).toList();
    for (final item in expiredOverflowTopItems) {
      final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
      _trackManager.removeDanmakuFromTrack(trackIndex, item, overflow: true);
    }
    _overflowTopDanmakuItems.removeWhere((item) => ((_tick - item.creationTime) > (5 * 1000))); // 5秒而不是_option.duration
    
    // 🔥 关键修复：移除过期的底部弹幕 - 主层和溢出层，同时从轨道管理器中移除
    final expiredBottomItems = _bottomDanmakuItems.where((item) => ((_tick - item.creationTime) > (5 * 1000))).toList();
    for (final item in expiredBottomItems) {
      final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
      _trackManager.removeDanmakuFromTrack(trackIndex, item);
    }
    _bottomDanmakuItems.removeWhere((item) => ((_tick - item.creationTime) > (5 * 1000))); // 5秒而不是_option.duration
    
    final expiredOverflowBottomItems = _overflowBottomDanmakuItems.where((item) => ((_tick - item.creationTime) > (5 * 1000))).toList();
    for (final item in expiredOverflowBottomItems) {
      final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
      _trackManager.removeDanmakuFromTrack(trackIndex, item, overflow: true);
    }
    _overflowBottomDanmakuItems.removeWhere((item) => ((_tick - item.creationTime) > (5 * 1000))); // 5秒而不是_option.duration

    /// 重绘静态弹幕
    setState(() {
      _staticAnimationController.value = 0;
    });
  }

  /// 🔥 暂停弹幕
  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    _animationController.stop();
    _staticAnimationController.stop();
  }

  /// 恢复
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    
    // 🔥 关键修改：恢复时重新启动动画控制器
    if (_running && mounted) {
      if (_scrollDanmakuItems.isNotEmpty || _overflowScrollDanmakuItems.isNotEmpty) {
        _animationController.repeat();
      }
      if (_topDanmakuItems.isNotEmpty || _bottomDanmakuItems.isNotEmpty ||
          _overflowTopDanmakuItems.isNotEmpty || _overflowBottomDanmakuItems.isNotEmpty) {
        _staticAnimationController.value = 0;
      }
    }
  }

  /// 更新弹幕设置
  void updateOption(DanmakuOption option) {
    bool needRestart = false;
    bool needStateUpdate = false; // 🔥 新增：标记是否需要更新状态
    
    if (_animationController.isAnimating) {
      _animationController.stop();
      needRestart = true;
    }

    // 🔥 关键修改：不再清空弹幕列表，而是通过绘制器的渲染逻辑来隐藏弹幕
    // 这样可以保持弹幕的动画状态，隐藏后再显示时弹幕能从正确的位置继续
    
    // 🔥 新增：检查弹幕类型显示/隐藏状态变化，同步轨道管理器状态
    bool trackStateChanged = false;
    if (_option.hideScroll != option.hideScroll || 
        _option.hideTop != option.hideTop || 
        _option.hideBottom != option.hideBottom) {
      trackStateChanged = true;
    }
    
    // 🔥 检查是否有其他需要更新UI的选项变化
    if (_option.opacity != option.opacity || 
        _option.fontSize != option.fontSize ||
        _option.area != option.area ||
        _option.showStroke != option.showStroke ||
        _option.hideTop != option.hideTop ||
        _option.hideBottom != option.hideBottom ||
        _option.hideScroll != option.hideScroll ||
        _option.massiveMode != option.massiveMode ||
        _option.showCollisionBoxes != option.showCollisionBoxes) {
      needStateUpdate = true;
    }
    
    _option = option;
    _controller.option = _option;

    /// 清理已经存在的 Paragraph 缓存 - 主层和溢出层
    for (DanmakuItem item in _scrollDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    for (DanmakuItem item in _overflowScrollDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    for (DanmakuItem item in _topDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    for (DanmakuItem item in _overflowTopDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    for (DanmakuItem item in _bottomDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    for (DanmakuItem item in _overflowBottomDanmakuItems) {
      if (item.paragraph != null) {
        item.paragraph = null;
      }
      if (item.strokeParagraph != null) {
        item.strokeParagraph = null;
      }
    }
    
    // 🔥 新增：如果轨道状态发生变化，同步轨道管理器状态
    if (trackStateChanged) {
      _trackManager.syncTrackStates(
        _scrollDanmakuItems,
        _topDanmakuItems,
        _bottomDanmakuItems,
        _overflowScrollDanmakuItems,
        _overflowTopDanmakuItems,
        _overflowBottomDanmakuItems
      );
    }
    
    // 🔥 关键修改：只有在未暂停且需要重启时才重启动画控制器
    if (needRestart && !_isPaused) {
      _animationController.repeat();
    }
    
    // 🔥 关键修改：只有在需要更新状态时才调用setState
    if (needStateUpdate) {
      setState(() {});
    }
  }

  /// 清空弹幕
  void clearDanmakus() {
    setState(() {
      // 🔥 关键修复：在清空弹幕列表之前先调用轨道管理器的清空方法
      // 这样可以保持轨道分配的连续性，避免每个轨道只有一个弹幕的问题
      _trackManager.clearTrackContents(
        _scrollDanmakuItems,
        _topDanmakuItems,
        _bottomDanmakuItems,
        _overflowScrollDanmakuItems,
        _overflowTopDanmakuItems,
        _overflowBottomDanmakuItems,
      );
      
      _scrollDanmakuItems.clear();
      _topDanmakuItems.clear();
      _bottomDanmakuItems.clear();
      _overflowScrollDanmakuItems.clear();
      _overflowTopDanmakuItems.clear();
      _overflowBottomDanmakuItems.clear();
      
      // 🔥 重置轨道计数器 - 主层和溢出层
      _currentScrollTrack = 0;
      _currentTopTrack = 0;
      _currentBottomTrack = 0;
      _overflowScrollTrack = 0;
      _overflowTopTrack = 0;
      _overflowBottomTrack = 0;
    });
    _animationController.stop();
  }

  /// 🔥 新增：彻底重置所有状态（用于切换视频等场景）
  void resetAll() {
    setState(() {
      _scrollDanmakuItems.clear();
      _topDanmakuItems.clear();
      _bottomDanmakuItems.clear();
      _overflowScrollDanmakuItems.clear();
      _overflowTopDanmakuItems.clear();
      _overflowBottomDanmakuItems.clear();
      
      // 🔥 重置轨道计数器 - 主层和溢出层
      _currentScrollTrack = 0;
      _currentTopTrack = 0;
      _currentBottomTrack = 0;
      _overflowScrollTrack = 0;
      _overflowTopTrack = 0;
      _overflowBottomTrack = 0;
      
      // 🔥 彻底重置轨道管理器的所有状态
      _trackManager.resetAll();
    });
    _animationController.stop();
  }

  /// 🔥 修改：使用轨道管理员获取轨道编号
  int _getTrackIndexFromYPosition(double yPosition) {
    return _trackManager.getTrackIndexFromYPosition(yPosition);
  }

  /// 🔥 新增：获取当前弹幕状态
  List<DanmakuItemState> getDanmakuStates() {
    final List<DanmakuItemState> states = [];
    final currentTime = _tick / 1000.0; // 转换为秒
    
    // 获取滚动弹幕状态
    for (final item in _scrollDanmakuItems) {
      final elapsedTime = currentTime - (item.creationTime / 1000.0);
      final totalDuration = 10.0; // 滚动弹幕10秒运动时间
      final normalizedProgress = (elapsedTime / totalDuration).clamp(0.0, 1.0);
      final remainingTime = ((totalDuration - elapsedTime) * 1000).round().clamp(0, (totalDuration * 1000).round());
      
      // 🔥 关键修复：只保存仍在有效时间内的弹幕（避免保存已经消失的弹幕）
      if (remainingTime > 0 && elapsedTime >= 0) {
        // 🔥 重要修改：保存轨道编号，确保弹幕关闭重新打开时能恢复到原有位置
        final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
        states.add(DanmakuItemState(
          content: item.content.text,
          color: item.content.color,
          type: item.content.type,
          normalizedProgress: normalizedProgress,
          originalCreationTime: item.creationTime,
          remainingTime: remainingTime,
          yPosition: item.yPosition,
          trackIndex: trackIndex, // 🔥 保存真实的轨道编号
        ));
      }
    }
    
    // 获取溢出滚动弹幕状态
    for (final item in _overflowScrollDanmakuItems) {
      final elapsedTime = currentTime - (item.creationTime / 1000.0);
      final totalDuration = 10.0; // 滚动弹幕10秒运动时间
      final normalizedProgress = (elapsedTime / totalDuration).clamp(0.0, 1.0);
      final remainingTime = ((totalDuration - elapsedTime) * 1000).round().clamp(0, (totalDuration * 1000).round());
      
      // 🔥 关键修复：只保存仍在有效时间内的弹幕
      if (remainingTime > 0 && elapsedTime >= 0) {
        // 🔥 重要修改：保存轨道编号，确保弹幕关闭重新打开时能恢复到原有位置
        final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
        states.add(DanmakuItemState(
          content: item.content.text,
          color: item.content.color,
          type: item.content.type,
          normalizedProgress: normalizedProgress,
          originalCreationTime: item.creationTime,
          remainingTime: remainingTime,
          yPosition: item.yPosition,
          trackIndex: trackIndex, // 🔥 保存真实的轨道编号
        ));
      }
    }
    
    // 获取顶部弹幕状态
    for (final item in _topDanmakuItems) {
      final elapsedTime = currentTime - (item.creationTime / 1000.0);
      final totalDuration = 5.0; // 顶部弹幕5秒显示时间
      final normalizedProgress = (elapsedTime / totalDuration).clamp(0.0, 1.0);
      final remainingTime = ((totalDuration - elapsedTime) * 1000).round().clamp(0, (totalDuration * 1000).round());
      
      // 🔥 关键修复：只保存仍在有效时间内的弹幕
      if (remainingTime > 0 && elapsedTime >= 0) {
        // 🔥 重要修改：保存轨道编号，确保弹幕关闭重新打开时能恢复到原有位置
        final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
        states.add(DanmakuItemState(
          content: item.content.text,
          color: item.content.color,
          type: item.content.type,
          normalizedProgress: normalizedProgress,
          originalCreationTime: item.creationTime,
          remainingTime: remainingTime,
          yPosition: item.yPosition,
          trackIndex: trackIndex, // 🔥 保存真实的轨道编号
        ));
      }
    }
    
    // 获取溢出顶部弹幕状态
    for (final item in _overflowTopDanmakuItems) {
      final elapsedTime = currentTime - (item.creationTime / 1000.0);
      final totalDuration = 5.0; // 顶部弹幕5秒显示时间
      final normalizedProgress = (elapsedTime / totalDuration).clamp(0.0, 1.0);
      final remainingTime = ((totalDuration - elapsedTime) * 1000).round().clamp(0, (totalDuration * 1000).round());
      
      // 🔥 关键修复：只保存仍在有效时间内的弹幕
      if (remainingTime > 0 && elapsedTime >= 0) {
        // 🔥 重要修改：保存轨道编号，确保弹幕关闭重新打开时能恢复到原有位置
        final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
        states.add(DanmakuItemState(
          content: item.content.text,
          color: item.content.color,
          type: item.content.type,
          normalizedProgress: normalizedProgress,
          originalCreationTime: item.creationTime,
          remainingTime: remainingTime,
          yPosition: item.yPosition,
          trackIndex: trackIndex, // 🔥 保存真实的轨道编号
        ));
      }
    }
    
    // 获取底部弹幕状态
    for (final item in _bottomDanmakuItems) {
      final elapsedTime = currentTime - (item.creationTime / 1000.0);
      final totalDuration = 5.0; // 底部弹幕5秒显示时间
      final normalizedProgress = (elapsedTime / totalDuration).clamp(0.0, 1.0);
      final remainingTime = ((totalDuration - elapsedTime) * 1000).round().clamp(0, (totalDuration * 1000).round());
      
      // 🔥 关键修复：只保存仍在有效时间内的弹幕
      if (remainingTime > 0 && elapsedTime >= 0) {
        // 🔥 重要修改：保存轨道编号，确保弹幕关闭重新打开时能恢复到原有位置
        final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
        states.add(DanmakuItemState(
          content: item.content.text,
          color: item.content.color,
          type: item.content.type,
          normalizedProgress: normalizedProgress,
          originalCreationTime: item.creationTime,
          remainingTime: remainingTime,
          yPosition: item.yPosition,
          trackIndex: trackIndex, // 🔥 保存真实的轨道编号
        ));
      }
    }
    
    // 获取溢出底部弹幕状态
    for (final item in _overflowBottomDanmakuItems) {
      final elapsedTime = currentTime - (item.creationTime / 1000.0);
      final totalDuration = 5.0; // 底部弹幕5秒显示时间
      final normalizedProgress = (elapsedTime / totalDuration).clamp(0.0, 1.0);
      final remainingTime = ((totalDuration - elapsedTime) * 1000).round().clamp(0, (totalDuration * 1000).round());
      
      // 🔥 关键修复：只保存仍在有效时间内的弹幕
      if (remainingTime > 0 && elapsedTime >= 0) {
        // 🔥 重要修改：保存轨道编号，确保弹幕关闭重新打开时能恢复到原有位置
        final trackIndex = _trackManager.getTrackIndexFromYPosition(item.yPosition);
        states.add(DanmakuItemState(
          content: item.content.text,
          color: item.content.color,
          type: item.content.type,
          normalizedProgress: normalizedProgress,
          originalCreationTime: item.creationTime,
          remainingTime: remainingTime,
          yPosition: item.yPosition,
          trackIndex: trackIndex, // 🔥 保存真实的轨道编号
        ));
      }
    }
    
    return states;
  }

  /// 确定滚动弹幕是否可以添加 - 照抄NipaPlay逻辑
  bool _scrollCanAddToTrack(double yPosition, double newDanmakuWidth) {
    for (var item in _scrollDanmakuItems) {
      if (item.yPosition == yPosition) {
        // 🔥 完全照抄NipaPlay的碰撞检测逻辑
        final existingTime = item.creationTime / 1000.0; // 转换为秒
        final newTime = _tick / 1000.0; // 转换为秒
        
        final existingWidth = item.width;
        final newWidth = newDanmakuWidth;
        
        // 计算现有弹幕的当前位置（10秒运动时间）
        final existingElapsed = newTime - existingTime;
        final existingPosition = _viewWidth - (existingElapsed / 10) * (_viewWidth + existingWidth);
        final existingLeft = existingPosition;
        final existingRight = existingPosition + existingWidth;
        
        // 计算新弹幕的当前位置
        final newElapsed = 0.0; // 新弹幕刚开始
        final newPosition = _viewWidth - (newElapsed / 10) * (_viewWidth + newWidth);
        final newLeft = newPosition;
        final newRight = newPosition + newWidth;
        
        // 安全距离：屏幕宽度的2%
        final safetyMargin = _viewWidth * 0.02;
        
        // 如果两个弹幕在屏幕上的位置有重叠，且距离小于安全距离，则会发生碰撞
        if ((existingRight + safetyMargin > newLeft) && 
            (existingLeft - safetyMargin < newRight)) {
          return false;
        }
      }
    }
    return true;
  }

  /// 确定顶部弹幕是否可以添加 - 照抄NipaPlay逻辑
  bool _topCanAddToTrack(double yPosition) {
    for (var item in _topDanmakuItems) {
      if (item.yPosition == yPosition) {
        // 🔥 完全照抄NipaPlay的时间重叠检测逻辑
        final existingTime = item.creationTime / 1000.0; // 转换为秒
        final newTime = _tick / 1000.0; // 转换为秒
        
        // 计算两个弹幕的显示时间范围
        final existingStartTime = existingTime;
        final existingEndTime = existingTime + 5; // 顶部弹幕显示5秒
        
        final newStartTime = newTime;
        final newEndTime = newTime + 5;
        
        // 增加安全时间间隔，避免弹幕过于接近
        const safetyTime = 0.5; // 0.5秒的安全时间
        
        // 如果两个弹幕的显示时间有重叠，且间隔小于安全时间，则会发生重叠
        if (newStartTime <= existingEndTime + safetyTime && 
            newEndTime + safetyTime >= existingStartTime) {
          return false;
        }
      }
    }
    return true;
  }

  /// 确定底部弹幕是否可以添加 - 照抄NipaPlay逻辑
  bool _bottomCanAddToTrack(double yPosition) {
    for (var item in _bottomDanmakuItems) {
      if (item.yPosition == yPosition) {
        // 🔥 完全照抄NipaPlay的时间重叠检测逻辑
        final existingTime = item.creationTime / 1000.0; // 转换为秒
        final newTime = _tick / 1000.0; // 转换为秒
        
        // 计算两个弹幕的显示时间范围
        final existingStartTime = existingTime;
        final existingEndTime = existingTime + 5; // 底部弹幕显示5秒
        
        final newStartTime = newTime;
        final newEndTime = newTime + 5;
        
        // 增加安全时间间隔，避免弹幕过于接近
        const safetyTime = 0.5; // 0.5秒的安全时间
        
        // 如果两个弹幕的显示时间有重叠，且间隔小于安全时间，则会发生重叠
        if (newStartTime <= existingEndTime + safetyTime && 
            newEndTime + safetyTime >= existingStartTime) {
          return false;
        }
      }
    }
    return true;
  }

  // 基于Stopwatch的计时器同步
  void _startTick() async {
    final stopwatch = Stopwatch()..start();
    int lastElapsedTime = 0;
    int printCounter = 0; // 限制打印频率

    while (_running && mounted) {
      await Future.delayed(const Duration(milliseconds: 1));
      int currentElapsedTime = stopwatch.elapsedMilliseconds; // 获取当前的已用时间
      int delta = currentElapsedTime - lastElapsedTime; // 计算自上次记录以来的时间差
      
      // 🔥 关键修改：只有在未暂停时才更新时间
      if (!_isPaused) {
        _tick += delta;
        // 🔥 新增：同步轨道管理员的时间
        _trackManager.updateCurrentTick(_tick);
      }
      
      lastElapsedTime = currentElapsedTime; // 更新最后记录的时间
    }

    stopwatch.stop();
  }

  @override
  Widget build(BuildContext context) {
    /// 🔥 修改：统一设置垂直间距为10.0，电脑和手机保持一致
    final verticalSpacing = 10.0;
    final textPainter = TextPainter(
      text: TextSpan(text: '弹幕', style: TextStyle(fontSize: _option.fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    _danmakuHeight = textPainter.height;
    
    return LayoutBuilder(builder: (context, constraints) {
      /// 计算视图宽度
      if (constraints.maxWidth != _viewWidth) {
        _viewWidth = constraints.maxWidth;
      }

      /// 计算轨道数量，考虑垂直间距
      final trackHeight = _danmakuHeight + verticalSpacing;
      _trackCount = ((constraints.maxHeight * _option.area - verticalSpacing) / trackHeight).floor();
      
      /// 重新计算轨道位置，加入垂直间距
      _trackYPositions.clear();
      for (int i = 0; i < _trackCount; i++) {
        _trackYPositions.add(i * trackHeight + verticalSpacing);
      }
      
      // 🔥 新增：初始化轨道管理员
      _trackManager.initializeTracks(_trackYPositions, _viewWidth);
      
      return ClipRect(
        child: IgnorePointer(
          child: Opacity(
            opacity: _option.opacity,
            child: Stack(children: [
              // 主层弹幕
              RepaintBoundary(
                  child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: ScrollDanmakuPainter(
                        _animationController.value,
                        _scrollDanmakuItems,
                        _option.duration,
                        _option.fontSize,
                        _option.showStroke,
                        _danmakuHeight,
                        _running,
                        _tick,
                        _isPaused, // 🔥 传递暂停状态
                        _option), // 🔥 传递弹幕选项
                    child: Container(),
                  );
                },
              )),
              RepaintBoundary(
                  child: AnimatedBuilder(
                animation: _staticAnimationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: StaticDanmakuPainter(
                        _staticAnimationController.value,
                        _topDanmakuItems,
                        _bottomDanmakuItems,
                        _option.duration,
                        _option.fontSize,
                        _option.showStroke,
                        _danmakuHeight,
                        _running,
                        _tick,
                        _isPaused, // 🔥 传递暂停状态
                        _option), // 🔥 传递弹幕选项
                    child: Container(),
                  );
                },
              )),
              // 🔥 溢出层弹幕
              RepaintBoundary(
                  child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: ScrollDanmakuPainter(
                        _animationController.value,
                        _overflowScrollDanmakuItems,
                        _option.duration,
                        _option.fontSize,
                        _option.showStroke,
                        _danmakuHeight,
                        _running,
                        _tick,
                        _isPaused, // 🔥 传递暂停状态
                        _option), // 🔥 传递弹幕选项
                    child: Container(),
                  );
                },
              )),
              RepaintBoundary(
                  child: AnimatedBuilder(
                animation: _staticAnimationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: StaticDanmakuPainter(
                        _staticAnimationController.value,
                        _overflowTopDanmakuItems,
                        _overflowBottomDanmakuItems,
                        _option.duration,
                        _option.fontSize,
                        _option.showStroke,
                        _danmakuHeight,
                        _running,
                        _tick,
                        _isPaused, // 🔥 传递暂停状态
                        _option), // 🔥 传递弹幕选项
                    child: Container(),
                  );
                },
              )),
            ]),
          ),
        ),
      );
    });
  }


}
