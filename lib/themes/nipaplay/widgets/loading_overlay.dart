import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals; // 添加globals导入
import 'typing_text.dart'; // 重新导入TypingText
import 'dart:async'; // 添加Timer的导入
import 'dart:math' as math; // 添加math导入用于max/min计算

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
  
  // 新增：媒体信息参数
  final String? animeTitle;
  final String? episodeTitle;
  final String? fileName;
  final String? coverImageUrl;

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
    this.animeTitle,
    this.episodeTitle,
    this.fileName,
    this.coverImageUrl,
  });

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _cursorController;
  late Animation<double> _cursorAnimation;

  // 滚动到底部的通用方法
  void _scrollToBottom() {
    if (_scrollController.hasClients && mounted) {
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
      // 延迟执行，确保新内容已经渲染完成
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          // 增加小延迟确保布局完成
          Future.delayed(const Duration(milliseconds: 50), () {
            if (_scrollController.hasClients && mounted) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
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
    // 计算比例尺寸时考虑屏幕大小，修复clamp参数顺序问题
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // 手机使用较小的宽度，平板和桌面使用较大的宽度
    final targetWidth = globals.isPhone && !globals.isTablet 
        ? math.min(screenWidth * 0.9, 400.0) // 手机上较小宽度
        : math.min(screenWidth * 0.9, (widget.width * 2.5).clamp(300.0, 800.0)); // 平板/桌面较大宽度
    
    final effectiveWidth = math.max(300.0, targetWidth);
    final effectiveHeight = math.max(200.0, math.min(screenHeight * 0.5, widget.height ?? 300));
    
    // 获取文本样式
    final textStyle = TextStyle(
      color: widget.textColor.withOpacity(widget.textOpacity),
      fontSize: widget.fontSize,
      fontWeight: widget.isBold ? FontWeight.w600 : FontWeight.normal,
      letterSpacing: 0.5,
    );
    
    final titleStyle = TextStyle(
      color: widget.textColor.withOpacity(widget.textOpacity * 0.9),
      fontSize: widget.fontSize + 2,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    );
    
    final subtitleStyle = TextStyle(
      color: widget.textColor.withOpacity(widget.textOpacity * 0.8),
      fontSize: widget.fontSize - 2,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
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
              height: effectiveHeight,
              borderRadius: widget.borderRadius,
              blur: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 20 : 0,
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
                padding: const EdgeInsets.all(20.0),
                child: globals.isPhone && !globals.isTablet 
                    ? Column( // 手机上使用上下双行布局
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 上方：媒体信息区域
                          _buildMediaInfoSection(titleStyle, subtitleStyle),
                          // 分隔线
                          Container(
                            height: 1,
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(vertical: 16.0),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  widget.textColor.withOpacity(0.1),
                                  widget.textColor.withOpacity(0.3),
                                  widget.textColor.withOpacity(0.1),
                                ],
                              ),
                            ),
                          ),
                          // 下方：加载信息区域
                          Expanded(
                            child: _buildLoadingMessagesSection(textStyle),
                          ),
                        ],
                      )
                    : Row( // 平板和桌面保持双栏布局
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 左侧：媒体信息区域 (1/3 宽度)
                          Expanded(
                            flex: 1,
                            child: _buildMediaInfoSection(titleStyle, subtitleStyle),
                          ),
                          // 分隔线
                          Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 16.0),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  widget.textColor.withOpacity(0.1),
                                  widget.textColor.withOpacity(0.3),
                                  widget.textColor.withOpacity(0.1),
                                ],
                              ),
                            ),
                          ),
                          // 右侧：加载信息区域 (2/3 宽度)
                          Expanded(
                            flex: 2,
                            child: _buildLoadingMessagesSection(textStyle),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 构建左侧媒体信息区域
  Widget _buildMediaInfoSection(TextStyle titleStyle, TextStyle subtitleStyle) {
    // 手机上使用横向布局，平板/桌面保持竖向布局
    if (globals.isPhone && !globals.isTablet) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 封面图片（手机上较小）
          _buildCoverImage(80, 106, titleStyle), // 3:4 比例，但更小
          const SizedBox(width: 16),
          // 文字信息
          Expanded(
            child: _buildTextInfo(titleStyle, subtitleStyle),
          ),
        ],
      );
    } else {
      // 平板/桌面使用原来的竖向布局
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCoverImage(120, 160, titleStyle), // 原来的尺寸
          _buildTextInfo(titleStyle, subtitleStyle),
        ],
      );
    }
  }

  // 构建封面图片
  Widget _buildCoverImage(double width, double height, TextStyle titleStyle) {
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: widget.textColor.withOpacity(0.1),
      ),
      child: widget.coverImageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                widget.coverImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: BoxDecoration(
                      color: widget.textColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.movie,
                      size: width * 0.4,
                      color: widget.textColor.withOpacity(0.5),
                    ),
                  );
                },
              ),
            )
          : Icon(
              Icons.movie,
              size: width * 0.4,
              color: widget.textColor.withOpacity(0.5),
            ),
    );
  }

  // 构建文字信息
  Widget _buildTextInfo(TextStyle titleStyle, TextStyle subtitleStyle) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start, // 都是左对齐，无需判断
      children: [
        // 动画名称
        if (widget.animeTitle != null && widget.animeTitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.animeTitle!,
              style: titleStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        
        // 集数标题
        if (widget.episodeTitle != null && widget.episodeTitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.episodeTitle!,
              style: subtitleStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        
        // 文件名（如果没有动画名时显示）
        if ((widget.animeTitle == null || widget.animeTitle!.isEmpty) && 
            widget.fileName != null && widget.fileName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.fileName!,
              style: titleStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  // 构建右侧加载消息区域
  Widget _buildLoadingMessagesSection(TextStyle textStyle) {
    return ScrollConfiguration(
      // 隐藏滚动条
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
      ),
      child: widget.messages.isEmpty 
          ? Center(
              child: Text(
                '正在加载...',
                style: textStyle,
              ),
            )
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
                          onTextChanged: _scrollToBottom, // 每次文本变化时滚动到底部
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
    super.key,
    required this.text,
    required this.style,
    required this.cursorAnimation,
    required this.cursorColor,
    required this.typingSpeed,
  });

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