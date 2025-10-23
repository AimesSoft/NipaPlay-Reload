import 'package:flutter/cupertino.dart';

/// iOS风格的页面进入bounce动画包装器
/// 模拟原生iOS应用切换页面时的轻微向上偏移后回弹的效果
class CupertinoBounceWrapper extends StatefulWidget {
  /// 要包装的子控件
  final Widget child;

  /// 动画持续时间，默认200毫秒
  final Duration duration;

  /// 向上偏移的像素数，默认2像素
  final double offsetPixels;

  /// 是否在创建时自动播放动画，默认true
  final bool autoPlay;

  const CupertinoBounceWrapper({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 200),
    this.offsetPixels = -2.0,
    this.autoPlay = true,
  });

  @override
  State<CupertinoBounceWrapper> createState() => CupertinoBounceWrapperState();

  /// 播放bounce动画的静态方法
  static Future<void> playAnimation(GlobalKey<CupertinoBounceWrapperState> key) async {
    await key.currentState?.playBounceAnimation();
  }

  /// 重置动画的静态方法
  static void resetAnimation(GlobalKey<CupertinoBounceWrapperState> key) {
    key.currentState?.resetAnimation();
  }
}

class CupertinoBounceWrapperState extends State<CupertinoBounceWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();

    // 初始化bounce动画控制器
    _bounceController = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    // 创建从偏移位置到正常位置的动画
    _bounceAnimation = Tween<double>(
      begin: widget.offsetPixels, // 向上偏移
      end: 0.0,                   // 恢复到正常位置
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeOutBack,  // 使用回弹曲线
    ));

    // 如果启用自动播放，在页面构建完成后触发动画
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          playBounceAnimation();
        }
      });
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  /// 播放bounce动画
  Future<void> playBounceAnimation() async {
    if (!mounted) return;
    _bounceController.reset();
    await _bounceController.forward();
  }

  /// 重置动画到初始状态
  void resetAnimation() {
    if (!mounted) return;
    _bounceController.reset();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounceAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _bounceAnimation.value),
          child: widget.child,
        );
      },
    );
  }
}