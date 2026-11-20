import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/custom_scaffold.dart';

/// 可切换的视图组件，支持在不同视图类型之间切换
/// 目前支持切换TabBarView（有动画）和IndexedStack（无动画）
class SwitchableView extends StatefulWidget {
  /// 子组件列表
  final List<Widget> children;

  /// 当前选中的索引
  final int currentIndex;

  /// 是否使用动画（true使用TabBarView，false使用IndexedStack）
  final bool enableAnimation;

  /// 禁用动画时是否保留已访问页面的状态
  ///
  /// - `true`: 采用懒加载 + IndexedStack 缓存，切换时不会销毁页面（更流畅）
  /// - `false`: 仅渲染当前页面，切换时会销毁/重建页面（更省资源）
  final bool keepAlive;

  /// 预热指定页面索引（仅在 `keepAlive=true` 且 `enableAnimation=false` 时生效）。
  ///
  /// 典型场景：开屏期间把大页面先构建/触发初始化，避免第一次切换卡顿。
  final List<int> preloadIndices;

  /// 页面切换回调
  final ValueChanged<int>? onPageChanged;

  /// 滚动物理效果
  final ScrollPhysics? physics;

  /// 可选的 TabController
  final TabController? controller;

  const SwitchableView({
    super.key,
    required this.children,
    required this.currentIndex,
    this.enableAnimation = false,
    this.keepAlive = false,
    this.preloadIndices = const [],
    this.onPageChanged,
    this.physics,
    this.controller,
  });

  @override
  State<SwitchableView> createState() => _SwitchableViewState();
}

class _SwitchableViewState extends State<SwitchableView> {
  // 当前索引（用于禁用动画模式）
  late int _currentIndex;

  TabController? _listenedController;
  bool _isControllerListenerAttached = false;
  List<Widget?>? _cachedChildren;
  List<int> _preloadQueue = const [];
  int _preloadCursor = 0;
  bool _preloadScheduled = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncControllerListener();
    _refreshPreloadQueue();
    _schedulePreloadIfNeeded();
  }

  @override
  void didUpdateWidget(SwitchableView oldWidget) {
    super.didUpdateWidget(oldWidget);

    _syncControllerListener(oldWidget: oldWidget);

    // 无 controller 时，同步内部索引与传入的索引
    if (_listenedController == null && widget.currentIndex != _currentIndex) {
      _currentIndex = widget.currentIndex;
    }

    // children 长度变化时重置缓存
    if (widget.children.length != oldWidget.children.length ||
        widget.keepAlive != oldWidget.keepAlive) {
      _cachedChildren = null;
      _preloadCursor = 0;
    }

    if (!_listEquals(widget.preloadIndices, oldWidget.preloadIndices)) {
      _preloadCursor = 0;
    }

    _refreshPreloadQueue();
    _schedulePreloadIfNeeded();
  }

  @override
  void dispose() {
    _detachControllerListener();
    super.dispose();
  }

  void _syncControllerListener({SwitchableView? oldWidget}) {
    final TabController? controller =
        widget.controller ?? TabControllerScope.of(context);

    final bool shouldListen = controller != null && !widget.enableAnimation;
    if (controller != _listenedController) {
      _detachControllerListener();
      _listenedController = controller;
      if (shouldListen) {
        _attachControllerListener();
      }
    } else {
      // controller 未变化，但 enableAnimation 可能切换
      if (shouldListen && !_isControllerListenerAttached) {
        _attachControllerListener();
      } else if (!shouldListen && _isControllerListenerAttached) {
        _detachControllerListener();
        _listenedController = controller;
      }
    }

    // 同步索引（避免外部跳转时显示不同步）
    final int nextIndex = controller?.index ?? widget.currentIndex;
    if (nextIndex != _currentIndex) {
      setState(() {
        _currentIndex = nextIndex;
      });
    }
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _refreshPreloadQueue() {
    if (!widget.keepAlive || widget.enableAnimation) {
      _preloadQueue = const [];
      _preloadCursor = 0;
      return;
    }

    final length = widget.children.length;
    if (length == 0 || widget.preloadIndices.isEmpty) {
      _preloadQueue = const [];
      _preloadCursor = 0;
      return;
    }

    final set = <int>{};
    for (final index in widget.preloadIndices) {
      if (index >= 0 && index < length) {
        set.add(index);
      }
    }

    final nextQueue = set.toList()..sort();
    if (_listEquals(_preloadQueue, nextQueue)) {
      return;
    }

    _preloadQueue = nextQueue;
    _preloadCursor = 0;
  }

  void _schedulePreloadIfNeeded() {
    if (!widget.keepAlive || widget.enableAnimation) return;
    if (_preloadQueue.isEmpty) return;
    if (_preloadCursor >= _preloadQueue.length) return;
    if (_preloadScheduled) return;

    _preloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadScheduled = false;
      if (!mounted) return;
      if (!widget.keepAlive || widget.enableAnimation) return;
      if (_preloadQueue.isEmpty || _preloadCursor >= _preloadQueue.length) {
        return;
      }

      final length = widget.children.length;
      if (length == 0) return;
      _cachedChildren ??= List<Widget?>.filled(length, null);
      if (_cachedChildren!.length != length) {
        _cachedChildren = List<Widget?>.filled(length, null);
      }

      bool changed = false;
      while (_preloadCursor < _preloadQueue.length) {
        final index = _preloadQueue[_preloadCursor++];
        if (index < 0 || index >= length) continue;
        if (_cachedChildren![index] == null) {
          _cachedChildren![index] = widget.children[index];
          changed = true;
          break;
        }
      }

      if (changed) {
        setState(() {});
      }

      _schedulePreloadIfNeeded();
    });
  }

  void _attachControllerListener() {
    final controller = _listenedController;
    if (controller == null) return;
    if (_isControllerListenerAttached) return;
    controller.addListener(_handleControllerChanged);
    _isControllerListenerAttached = true;
  }

  void _detachControllerListener() {
    final controller = _listenedController;
    if (controller == null) return;
    if (!_isControllerListenerAttached) return;
    controller.removeListener(_handleControllerChanged);
    _isControllerListenerAttached = false;
  }

  void _handleControllerChanged() {
    final controller = _listenedController;
    if (controller == null || !mounted) return;

    // TabController 在动画过程中会高频 notify，但 index 通常只在开始/结束变化
    final int nextIndex = controller.index;
    if (nextIndex == _currentIndex) return;

    setState(() {
      _currentIndex = nextIndex;
    });
  }

  List<Widget> _buildCachedChildren(int safeIndex) {
    final length = widget.children.length;
    _cachedChildren ??= List<Widget?>.filled(length, null);
    if (_cachedChildren!.length != length) {
      _cachedChildren = List<Widget?>.filled(length, null);
    }

    // Refresh the active child to avoid stale cached UI when its state changes.
    _cachedChildren![safeIndex] = widget.children[safeIndex];

    return List<Widget>.generate(length, (i) {
      final cached = _cachedChildren![i];
      return TickerMode(
        enabled: i == safeIndex,
        child: ExcludeFocus(
          excluding: i != safeIndex,
          child: cached ?? const SizedBox.shrink(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // 从作用域获取TabController
    final TabController? tabController =
        widget.controller ?? TabControllerScope.of(context);

    // 如果启用了动画模式，则使用TabBarView
    if (widget.enableAnimation && tabController != null) {
      // 检查TabController长度是否匹配子元素数量，如果不匹配则回退到非动画模式
      if (tabController.length != widget.children.length) {
        print(
            'TabController长度(${tabController.length})与子元素数量(${widget.children.length})不匹配，降级为IndexedStack模式');
        // 不匹配时使用IndexedStack
        return IndexedStack(
          index: _currentIndex,
          sizing: StackFit.expand,
          children: widget.children,
        );
      }

      return NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          // 页面切换完成时通知父组件
          if (notification is ScrollEndNotification) {
            final int currentPage = tabController.index;
            if (currentPage != _currentIndex) {
              _currentIndex = currentPage;
              widget.onPageChanged?.call(currentPage);
            }
          }
          return false;
        },
        child: TabBarView(
          controller: tabController,
          physics: widget.physics ?? const PageScrollPhysics(),
          children: widget.children,
        ),
      );
    } else {
      final int length = widget.children.length;
      if (length == 0) {
        return const SizedBox.shrink();
      }

      final int safeIndex = _currentIndex.clamp(0, length - 1);
      if (widget.keepAlive) {
        return IndexedStack(
          index: safeIndex,
          sizing: StackFit.expand,
          children: _buildCachedChildren(safeIndex),
        );
      }

      // 🔥 CPU优化：仅渲染当前页面（会在切换时销毁/重建页面）
      if (safeIndex >= 0 && safeIndex < length) {
        return widget.children[safeIndex];
      }

      return const Center(child: Text('页面索引超出范围'));
    }
  }
}

/// 自定义的标签页滚动物理效果，使滑动更平滑
class CustomTabScrollPhysics extends ScrollPhysics {
  const CustomTabScrollPhysics({super.parent});

  @override
  CustomTabScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CustomTabScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 0.8, // 默认为1.0，减小质量使动画更轻快
        stiffness: 100.0, // 默认为100.0，保持弹性系数
        damping: 20.0, // 默认为10.0，增加阻尼使滚动更平滑
      );
}
