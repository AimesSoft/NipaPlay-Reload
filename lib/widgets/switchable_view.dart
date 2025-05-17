import 'package:flutter/material.dart';

/// 可切换的视图组件，支持在不同视图类型之间切换
/// 目前支持切换IndexedStack（无动画）和TabBarView（有动画）
class SwitchableView extends StatefulWidget {
  /// 子组件列表
  final List<Widget> children;
  
  /// 当前选中的索引
  final int currentIndex;
  
  /// 是否使用动画（true使用TabBarView，false使用IndexedStack）
  final bool enableAnimation;
  
  /// 页面切换回调
  final ValueChanged<int>? onPageChanged;
  
  /// 滚动物理效果
  final ScrollPhysics? physics;

  const SwitchableView({
    Key? key,
    required this.children,
    required this.currentIndex,
    this.enableAnimation = false,
    this.onPageChanged,
    this.physics,
  }) : super(key: key);

  @override
  State<SwitchableView> createState() => _SwitchableViewState();
}

class _SwitchableViewState extends State<SwitchableView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _initializeTabController();
  }
  
  void _initializeTabController() {
    _tabController = TabController(
      length: widget.children.length,
      vsync: this,
      initialIndex: widget.currentIndex,
    );
    
    _tabController.addListener(() {
      // 仅在索引变化且不是动画中时触发回调
      if (_tabController.indexIsChanging && widget.onPageChanged != null) {
        widget.onPageChanged!(_tabController.index);
      }
    });
  }
  
  @override
  void didUpdateWidget(SwitchableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 检查子项数量是否变化，如果变化需要重新初始化控制器
    if (widget.children.length != oldWidget.children.length) {
      _tabController.dispose();
      _initializeTabController();
    }
    
    // 如果索引变化，更新控制器索引
    if (oldWidget.currentIndex != widget.currentIndex && 
        _tabController.index != widget.currentIndex) {
      _tabController.animateTo(widget.currentIndex);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 根据是否启用动画决定使用TabBarView还是IndexedStack
    if (widget.enableAnimation) {
      return TabBarView(
        controller: _tabController,
        physics: widget.physics ?? const CustomTabScrollPhysics(),
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