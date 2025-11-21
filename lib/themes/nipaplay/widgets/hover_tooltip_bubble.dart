import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async'; // 添加定时器支持
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

// 全局气泡管理器 - 确保同一时间只有一个气泡显示
class _TooltipManager {
  static final _TooltipManager _instance = _TooltipManager._internal();
  factory _TooltipManager() => _instance;
  _TooltipManager._internal();

  _HoverTooltipBubbleState? _currentTooltip;
  bool _isManaging = false; // 防止管理器操作冲突

  void registerTooltip(_HoverTooltipBubbleState tooltip) {
    if (_isManaging) return;
    _isManaging = true;
    
    try {
      // 如果有旧的气泡，先强制关闭
      if (_currentTooltip != null && _currentTooltip != tooltip) {
        try {
          _currentTooltip!._forceHide();
        } catch (e) {
          // 忽略旧气泡的清理异常
        }
      }
      _currentTooltip = tooltip;
    } finally {
      _isManaging = false;
    }
  }

  void unregisterTooltip(_HoverTooltipBubbleState tooltip) {
    if (_isManaging) return;
    _isManaging = true;
    
    try {
      if (_currentTooltip == tooltip) {
        _currentTooltip = null;
      }
    } finally {
      _isManaging = false;
    }
  }
  
  // 强制清理所有气泡（用于紧急情况）
  void forceCleanup() {
    if (_isManaging) return;
    _isManaging = true;
    
    try {
      if (_currentTooltip != null) {
        try {
          _currentTooltip!._forceCleanup();
        } catch (e) {
          // 忽略清理异常
        }
        _currentTooltip = null;
      }
    } finally {
      _isManaging = false;
    }
  }
}

class HoverTooltipBubble extends StatefulWidget {
  final String text;
  final Widget child;
  final double padding;
  final double maxWidth;
  final double verticalOffset;
  final double horizontalOffset;
  final bool showOnTop;
  final bool autoAlign; // 新增：是否自动对齐
  final Duration showDelay;
  final Duration hideDelay;

  const HoverTooltipBubble({
    super.key,
    required this.text,
    required this.child,
    this.padding = 16,
    this.maxWidth = 300,
    this.verticalOffset = 10,
    this.horizontalOffset = 10,
    this.showOnTop = false,
    this.autoAlign = true, // 默认启用自动对齐
    this.showDelay = const Duration(milliseconds: 500),
    this.hideDelay = const Duration(milliseconds: 100),
  });

  @override
  State<HoverTooltipBubble> createState() => _HoverTooltipBubbleState();
}

class _HoverTooltipBubbleState extends State<HoverTooltipBubble> {
  bool _isHovered = false;
  bool _isOverlayVisible = false; // 新增：跟踪overlay的实际显示状态
  final GlobalKey _childKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  final _TooltipManager _manager = _TooltipManager();
  
  // 添加定时器管理
  Timer? _showTimer;
  Timer? _hideTimer;
  
  // 添加安全锁，防止并发操作
  bool _isOperating = false;
  
  @override
  void dispose() {
    _manager.unregisterTooltip(this);
    _cancelAllTimers(); // 取消所有定时器
    _forceCleanup(); // 强制清理所有资源
    super.dispose();
  }
  
  @override
  void deactivate() {
    // 当 widget 被移除时，立即清理资源
    _cancelAllTimers();
    if (_isOverlayVisible) {
      _hideOverlay();
    }
    super.deactivate();
  }

  // 取消所有定时器
  void _cancelAllTimers() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _showTimer = null;
    _hideTimer = null;
  }

  // 强制清理所有资源
  void _forceCleanup() {
    if (_isOperating) return; // 防止重复操作
    _isOperating = true;
    
    try {
      _cancelAllTimers();
      _overlayEntry?.remove();
      _overlayEntry = null;
      _isOverlayVisible = false;
      _isHovered = false;
    } catch (e) {
      // 忽略清理时的异常
    } finally {
      _isOperating = false;
    }
  }

  // 强制隐藏（供管理器调用）
  void _forceHide() {
    if (_isOperating) return; // 防止重复操作
    _isOperating = true;
    
    try {
      _cancelAllTimers();
      if (mounted) {
        setState(() => _isHovered = false);
      }
      _hideOverlay();
    } catch (e) {
      // 如果setState失败，直接清理资源
      _forceCleanup();
    } finally {
      _isOperating = false;
    }
  }

  void _showOverlay(BuildContext context) {
    if (widget.text.isEmpty || _isOperating || _isOverlayVisible) return;
    
    _isOperating = true;
    
    try {
      // 先注册到管理器（这会自动关闭其他气泡）
      _manager.registerTooltip(this);
      
      final RenderBox? renderBox = _childKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) {
        _isOperating = false;
        return;
      }
      
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      final screenSize = MediaQuery.of(context).size;
    
    // 计算气泡尺寸
    final bubbleSize = _calculateBubbleSize();
    
    // 智能定位
    double left, top;
    
    if (widget.autoAlign) {
      // 检查右侧是否有足够空间
      final rightSpace = screenSize.width - (position.dx + size.width + widget.horizontalOffset);
      final leftSpace = position.dx - widget.horizontalOffset;
      
      if (rightSpace >= bubbleSize.width) {
        // 右侧有足够空间，在右侧显示
        left = position.dx + size.width + widget.horizontalOffset;
      } else if (leftSpace >= bubbleSize.width) {
        // 左侧有足够空间，在左侧显示
        left = position.dx - bubbleSize.width - widget.horizontalOffset;
      } else {
        // 两侧都没有足够空间，选择空间更大的一侧
        if (rightSpace > leftSpace) {
          left = position.dx + size.width + widget.horizontalOffset;
        } else {
          left = position.dx - bubbleSize.width - widget.horizontalOffset;
        }
      }
      
      // 垂直居中对齐
      top = position.dy + (size.height - bubbleSize.height) / 2;
    } else {
      // 原有逻辑
      left = position.dx + (size.width - bubbleSize.width) / 2;
      if (widget.showOnTop) {
        top = position.dy - bubbleSize.height - widget.verticalOffset;
      } else {
        top = position.dy + size.height + widget.verticalOffset;
      }
    }
    
    // 边界检查和调整
    left = left.clamp(10.0, screenSize.width - bubbleSize.width - 10);
    top = top.clamp(10.0, screenSize.height - bubbleSize.height - 10);
    
      _overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: _buildBubble(bubbleSize),
          ),
        ),
      );

      Overlay.of(context).insert(_overlayEntry!);
      _isOverlayVisible = true;
      
    } catch (e) {
      // 如果显示失败，清理资源
      _overlayEntry?.remove();
      _overlayEntry = null;
      _isOverlayVisible = false;
    } finally {
      _isOperating = false;
    }
  }

  void _hideOverlay() {
    if (_isOperating || !_isOverlayVisible) return;
    
    _isOperating = true;
    
    try {
      _cancelAllTimers(); // 确保取消所有定时器
      _manager.unregisterTooltip(this);
      _overlayEntry?.remove();
      _overlayEntry = null;
      _isOverlayVisible = false;
    } catch (e) {
      // 忽略隐藏时的异常，但确保状态正确
      _overlayEntry = null;
      _isOverlayVisible = false;
    } finally {
      _isOperating = false;
    }
  }

  Size _calculateBubbleSize() {
    const textStyle = TextStyle(
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w400,
    );
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
      maxLines: null, // 允许无限行
    )..layout(maxWidth: widget.maxWidth - widget.padding * 2);
    
    // 确保最小尺寸和合理的最大尺寸
    final width = (textPainter.width + widget.padding * 2).clamp(100.0, widget.maxWidth);
    final height = (textPainter.height + widget.padding * 2).clamp(40.0, 400.0);
    
    return Size(width, height);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (event) {
        
        // 取消之前的所有定时器
        _cancelAllTimers();
        
        if (mounted) {
          setState(() => _isHovered = true);
        }
        
        // 使用可管理的定时器
        _showTimer = Timer(widget.showDelay, () {
          if (_isHovered && mounted && !_isOverlayVisible) {
            _showOverlay(context);
          }
          _showTimer = null; // 清空引用
        });
      },
      onExit: (_) {
        // 取消之前的所有定时器
        _cancelAllTimers();
        
        if (mounted) {
          setState(() => _isHovered = false);
        }
        
        // 使用可管理的定时器
        _hideTimer = Timer(widget.hideDelay, () {
          if (!_isHovered && mounted && _isOverlayVisible) {
            _hideOverlay();
          }
          _hideTimer = null; // 清空引用
        });
      },
      child: KeyedSubtree(
        key: _childKey,
        child: widget.child,
      ),
    );
  }

  Widget _buildBubble(Size size) {
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w400,
    );
    
    return Container(
      constraints: BoxConstraints(
        minWidth: 100,
        maxWidth: widget.maxWidth,
        minHeight: 40,
        maxHeight: 400,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
          child: Consumer<AppearanceSettingsProvider>(
            builder: (context, settingsProvider, _) => BackdropFilter(
              filter: ImageFilter.blur(sigmaX: settingsProvider.enableWidgetBlurEffect ? 25 : 0, sigmaY: settingsProvider.enableWidgetBlurEffect ? 25 : 0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.25),
                      Colors.white.withOpacity(0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(widget.padding),
                  child: IntrinsicHeight(
                    child: IntrinsicWidth(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: widget.maxWidth - widget.padding * 2,
                        ),
                        child: Text(
                          widget.text,
                          style: textStyle,
                          textAlign: TextAlign.left,
                          softWrap: true,
                          overflow: TextOverflow.visible,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }
}