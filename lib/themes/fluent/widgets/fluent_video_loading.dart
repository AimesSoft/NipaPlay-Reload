import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;

/// FluentUI风格的视频加载中控件
class FluentVideoLoading extends StatefulWidget {
  final String? message;
  final double? progress; // 0.0 - 1.0, null表示不确定进度
  final VoidCallback? onCancel;
  final bool showCancelButton;

  const FluentVideoLoading({
    super.key,
    this.message,
    this.progress,
    this.onCancel,
    this.showCancelButton = false,
  });

  @override
  State<FluentVideoLoading> createState() => _FluentVideoLoadingState();
}

class _FluentVideoLoadingState extends State<FluentVideoLoading>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        color: material.Colors.black.withOpacity(0.8),
        child: Center(
          child: Card(
            padding: const EdgeInsets.all(32),
            borderRadius: BorderRadius.circular(12),
            backgroundColor: theme.cardColor,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 400,
                minWidth: 300,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 图标
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: theme.accentColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      FluentIcons.video,
                      size: 40,
                      color: theme.accentColor,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 标题
                  Text(
                    '正在加载视频',
                    style: theme.typography.subtitle?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 进度条
                  if (widget.progress != null)
                    Column(
                      children: [
                        ProgressBar(
                          value: widget.progress! * 100,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(widget.progress! * 100).toInt()}%',
                          style: theme.typography.caption?.copyWith(
                            color: theme.inactiveColor,
                          ),
                        ),
                      ],
                    )
                  else
                    const ProgressRing(),
                  
                  const SizedBox(height: 16),
                  
                  // 消息文本
                  if (widget.message != null)
                    Text(
                      widget.message!,
                      style: theme.typography.caption?.copyWith(
                        color: theme.inactiveColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  
                  // 取消按钮
                  if (widget.showCancelButton && widget.onCancel != null) ...[
                    const SizedBox(height: 24),
                    Button(
                      onPressed: widget.onCancel,
                      child: const Text('取消'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// FluentUI风格的简单加载指示器
class FluentVideoLoadingIndicator extends StatelessWidget {
  final String? message;
  final double size;

  const FluentVideoLoadingIndicator({
    super.key,
    this.message,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: ProgressRing(),
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(
            message!,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}