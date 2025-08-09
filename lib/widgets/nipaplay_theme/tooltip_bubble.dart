import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

class TooltipBubble extends StatefulWidget {
  final String text;
  final Widget child;
  final double padding;
  final double arrowSize;
  final double verticalOffset;
  final bool showOnTop;
  final bool showOnRight;
  final bool followMouse;
  final double? position;

  const TooltipBubble({
    super.key,
    required this.text,
    required this.child,
    this.padding = 12,
    this.arrowSize = 8,
    this.verticalOffset = 20,
    this.showOnTop = false,
    this.showOnRight = false,
    this.followMouse = false,
    this.position,
  });

  @override
  State<TooltipBubble> createState() => _TooltipBubbleState();
}

class _TooltipBubbleState extends State<TooltipBubble> {
  bool _isHovered = false;
  final GlobalKey _childKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  Offset? _mousePosition;

  void _updateOverlay(BuildContext context, [Offset? newMousePosition]) {
    if (newMousePosition != null) {
      _mousePosition = newMousePosition;
    }
    _hideOverlay();
    if (_isHovered && widget.text.isNotEmpty) {
      _showOverlay(context);
    }
  }

  void _showOverlay(BuildContext context) {
    final RenderBox renderBox = _childKey.currentContext?.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final bubbleWidth = _getBubbleWidth();
    final bubbleHeight = _getBubbleHeight();
    
    // 添加调试日志
    //debugPrint('[TooltipBubble] 显示气泡，文本: "${widget.text}", 宽度: $bubbleWidth');

    double left;
    double top;

    if (widget.position != null) {
      left = widget.position! - bubbleWidth / 2;
      top = widget.showOnTop 
          ? position.dy - bubbleHeight - widget.verticalOffset
          : position.dy + size.height + widget.verticalOffset;
    } else if (widget.followMouse && _mousePosition != null) {
      left = _mousePosition!.dx - bubbleWidth / 2;
      top = widget.showOnTop 
          ? _mousePosition!.dy - bubbleHeight - widget.verticalOffset
          : _mousePosition!.dy + widget.verticalOffset;
    } else if (widget.showOnRight) {
      left = position.dx + size.width + widget.verticalOffset;
      top = position.dy + (size.height - bubbleHeight) / 2;
    } else {
      left = position.dx + (size.width - bubbleWidth) / 2;
      top = widget.showOnTop 
          ? position.dy - bubbleHeight - widget.verticalOffset
          : position.dy + size.height + widget.verticalOffset;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          color: Colors.transparent,
          child: _buildBubble(bubbleWidth),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  double _getBubbleWidth() {
    const textStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    
    // 增加额外的宽度，确保组合键能够完整显示
    final String lowerText = widget.text.toLowerCase();
    if (lowerText.contains('shift') || 
        lowerText.contains('ctrl') || 
        lowerText.contains('command') || 
        lowerText.contains('tab') || 
        lowerText.contains('alt') || 
        lowerText.contains('esc')) {
      return textPainter.width + widget.padding * 2 + 20;
    } else {
      return textPainter.width + widget.padding * 2 + 4;
    }
  }

  double _getBubbleHeight() {
    return 30; // 固定高度，因为文字只有一行
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        if (widget.followMouse) {
          _updateOverlay(context, event.position);
        }
      },
      onEnter: (event) {
        setState(() => _isHovered = true);
        _updateOverlay(context, event.position);
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _hideOverlay();
      },
      child: KeyedSubtree(
        key: _childKey,
        child: widget.child,
      ),
    );
  }

  Widget _buildBubble(double width) {
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );
    
    return Container(
      width: width,
      height: _getBubbleHeight(),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.padding),
                child: Text(
                  widget.text,
                  style: textStyle,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  //textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 