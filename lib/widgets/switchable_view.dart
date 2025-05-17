import 'package:flutter/material.dart';

/// 可切换的视图组件，支持在不同视图类型之间切换
/// 目前支持切换IndexedStack（无动画）和PageView（有动画）
class SwitchableView extends StatefulWidget {
  /// 子组件列表
  final List<Widget> children;
  
  /// 当前选中的索引
  final int currentIndex;
  
  /// 是否使用动画（true使用PageView，false使用IndexedStack）
  final bool enableAnimation;
  
  /// 页面切换回调
  final ValueChanged<int>? onPageChanged;
  
  /// 控制器，可选
  final PageController? controller;
  
  /// 物理滚动效果
  final ScrollPhysics? physics;

  const SwitchableView({
    Key? key,
    required this.children,
    required this.currentIndex,
    this.enableAnimation = false,
    this.onPageChanged,
    this.controller,
    this.physics,
  }) : super(key: key);

  @override
  State<SwitchableView> createState() => _SwitchableViewState();
}

class _SwitchableViewState extends State<SwitchableView> {
  late PageController _pageController;
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _initializePageController();
  }
  
  void _initializePageController() {
    _pageController = widget.controller ?? PageController(initialPage: widget.currentIndex);
    _isInitialized = true;
  }
  
  @override
  void didUpdateWidget(SwitchableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 检查控制器是否需要重新初始化
    if (widget.controller != oldWidget.controller) {
      if (oldWidget.controller == null) {
        // 之前是内部控制器，需要释放
        _pageController.dispose();
      }
      _initializePageController();
    }
    
    // 当开关状态从false变为true时，确保PageView初始位置正确
    if (!oldWidget.enableAnimation && widget.enableAnimation) {
      // 如果从IndexedStack切换到PageView，强制跳转到正确的页面
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isInitialized && mounted) {
          _pageController.jumpToPage(widget.currentIndex);
        }
      });
    }
    
    // 如果索引变化且使用动画模式，则动画跳转到新索引
    if (oldWidget.currentIndex != widget.currentIndex) {
      if (widget.enableAnimation) {
        // 使用动画模式时，平滑切换
        _pageController.animateToPage(
          widget.currentIndex,
          duration: const Duration(milliseconds: 200),
          curve: Curves.ease,
        );
      } else if (_pageController.hasClients) {
        // 不使用动画但控制器已初始化，直接跳转以保持同步
        _pageController.jumpToPage(widget.currentIndex);
      }
    }
  }

  @override
  void dispose() {
    // 如果不是外部提供的控制器，需要自己销毁
    if (widget.controller == null) {
      _pageController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 根据是否启用动画决定使用PageView还是IndexedStack
    if (widget.enableAnimation) {
      return PageView(
        controller: _pageController,
        physics: widget.physics ?? const CustomPageScrollPhysics(),
        onPageChanged: widget.onPageChanged,
        children: widget.children,
      );
    } else {
      return IndexedStack(
        index: widget.currentIndex,
        children: widget.children,
      );
    }
  }
}

/// 自定义的页面滚动物理效果，使滑动更平滑
class CustomPageScrollPhysics extends ScrollPhysics {
  const CustomPageScrollPhysics({super.parent});

  @override
  CustomPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CustomPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 0.8, // 默认为1.0
        stiffness: 100.0, // 默认为100.0
        damping: 20.0, // 默认为10.0，增加阻尼使滚动更平滑
      );
} 