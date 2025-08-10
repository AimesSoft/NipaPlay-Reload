import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';
import 'typing_text.dart'; // 重新导入TypingText
import 'dart:async'; // 添加Timer的导入

class LoadingOverlay extends StatefulWidget {
  final List<String> messages;
  final double width;
  final double? height;
  final double blur;
  final double borderWidth;
  final double borderRadius;
  final Color backgroundColor;
  final double backgroundOpacity;
  final Color textColor;
  final double textOpacity;
  final double fontSize;
  final bool isBold;
  final bool highPriorityAnimation;

  const LoadingOverlay({
    super.key,
    required this.messages,
    this.width = 300,
    this.height,
    this.blur = 20,
    this.borderWidth = 1.5,
    this.borderRadius = 15,
    this.backgroundColor = Colors.black,
    this.backgroundOpacity = 0.3,
    this.textColor = Colors.white,
    this.textOpacity = 0.9,
    this.fontSize = 16,
    this.isBold = true,
    this.highPriorityAnimation = true,
  });

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _cursorController;
  late Animation<double> _cursorAnimation;

  @override
  void initState() {
    super.initState();
    // 设置光标闪烁动画
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), // 闪烁频率
    )..repeat(reverse: true); // 重复执行并反向（产生闪烁效果）
    
    _cursorAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_cursorController);
  }

  @override
  void didUpdateWidget(LoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当消息列表更新时，滚动到底部
    if (oldWidget.messages != widget.messages) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 计算比例尺寸时考虑屏幕大小
    final screenWidth = MediaQuery.of(context).size.width;
    final effectiveWidth = widget.width < screenWidth ? widget.width : screenWidth;
    
    // 获取文本样式
    final textStyle = TextStyle(
      color: widget.textColor.withOpacity(widget.textOpacity),
      fontSize: widget.fontSize,
      fontWeight: widget.isBold ? FontWeight.w600 : FontWeight.normal,
      letterSpacing: 0.5,
    );
    
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景
        Container(
          color: widget.backgroundColor.withOpacity(widget.backgroundOpacity),
        ),
        // 毛玻璃加载界面
        Center(
          child: Material(
            type: MaterialType.transparency,
            child: GlassmorphicContainer(
              width: effectiveWidth,
              height: widget.height ?? 100, // 使用固定高度
              borderRadius: widget.borderRadius,blur: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 20 : 0,
              alignment: Alignment.center,
              border: widget.borderWidth,
              linearGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFffffff).withOpacity(0.15),
                  const Color(0xFFFFFFFF).withOpacity(0.08),
                ],
              ),
              borderGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFffffff).withOpacity(0.6),
                  const Color((0xFFFFFFFF)).withOpacity(0.4),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 20.0),
                child: ScrollConfiguration(
                  // 隐藏滚动条
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: false,
                  ),
                  child: widget.messages.isEmpty 
                      ? const SizedBox() // 如果没有消息，显示空白
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          itemCount: widget.messages.length,
                          itemBuilder: (context, index) {
                            // 最新的消息使用打字机效果并添加闪烁光标
                            if (index == widget.messages.length - 1) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Stack(
                                  children: [
                                    // 打字机文本
                                    TypingText(
                                      messages: [widget.messages[index]],
                                      style: textStyle,
                                      typingSpeed: const Duration(milliseconds: 50),
                                      deleteSpeed: const Duration(milliseconds: 30),
                                      pauseDuration: const Duration(seconds: 1),
                                    ),
                                    // 闪烁的下划线光标
                                    Positioned.fill(
                                      child: TypingTextCursor(
                                        text: widget.messages[index],
                                        style: textStyle,
                                        cursorAnimation: _cursorAnimation,
                                        cursorColor: widget.textColor.withOpacity(widget.textOpacity),
                                        typingSpeed: const Duration(milliseconds: 50),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            // 历史消息直接显示
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: Text(
                                widget.messages[index],
                                style: textStyle,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 自定义打字机文本光标组件
class TypingTextCursor extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Animation<double> cursorAnimation;
  final Color cursorColor;
  final Duration typingSpeed;

  const TypingTextCursor({
    Key? key,
    required this.text,
    required this.style,
    required this.cursorAnimation,
    required this.cursorColor,
    required this.typingSpeed,
  }) : super(key: key);

  @override
  State<TypingTextCursor> createState() => _TypingTextCursorState();
}

class _TypingTextCursorState extends State<TypingTextCursor> {
  String _currentText = '';
  int _charIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTypingAnimation();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(TypingTextCursor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _currentText = '';
      _charIndex = 0;
      _startTypingAnimation();
    }
  }

  void _startTypingAnimation() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.typingSpeed, (timer) {
      if (_charIndex < widget.text.length) {
        setState(() {
          _charIndex++;
          _currentText = widget.text.substring(0, _charIndex);
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 计算光标位置
    final textPainter = TextPainter(
      text: TextSpan(
        text: _currentText,
        style: widget.style,
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    return Stack(
      children: [
                 Positioned(
           left: textPainter.width,
           bottom: 5, // 绝对贴于底部
           child: FadeTransition(
             opacity: widget.cursorAnimation,
             child: Container(
               width: 10, // 光标宽度
               height: 3, // 光标高度（下划线厚度）
               color: widget.cursorColor,
             ),
           ),
        ),
      ],
    );
  }
} 