import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/custom_scaffold.dart';

/// 可切换的视图组件，支持在不同视图类型之间切换
/// 目前支持切换TabBarView（有动画）和IndexedStack（无动画）
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

class _SwitchableViewState extends State<SwitchableView> {
  // 当禁用滑动动画时使用的索引
  late int _currentIndex;
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
  }
  
  @override
  void didUpdateWidget(SwitchableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 同步内部索引与传入的索引
    if (widget.currentIndex != _currentIndex) {
      setState(() {
        _currentIndex = widget.currentIndex;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // 从作用域获取TabController
    final TabController? tabController = TabControllerScope.of(context);
    
    // 如果启用了动画模式，则使用TabBarView
    if (widget.enableAnimation && tabController != null) {
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
      // 禁用动画模式使用IndexedStack
      return IndexedStack(
        index: _currentIndex,
        sizing: StackFit.expand,
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