import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:nipaplay/themes/nipaplay/widgets/player_menu_theme.dart';
import 'package:nipaplay/themes/nipaplay/widgets/player_overlay_surface.dart';

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

  // Cached overlay position for in-place updates
  Offset _overlayOffset = Offset.zero;
  double _overlayWidth = 0;

  // Debounce timers for filtering spurious enter/exit events on Windows
  Timer? _enterTimer;
  Timer? _exitTimer;

  void _recalculatePosition() {
    final RenderBox renderBox =
        _childKey.currentContext?.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final bubbleWidth = _getBubbleWidth();
    final bubbleHeight = _getBubbleHeight();

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

    final screenSize = MediaQuery.of(context).size;
    final maxLeft = screenSize.width - bubbleWidth - 10.0;
    if (maxLeft <= 10.0) {
      left = 10.0;
    } else {
      left = left.clamp(10.0, maxLeft);
    }
    final maxTop = screenSize.height - bubbleHeight - 10.0;
    if (maxTop <= 10.0) {
      top = 10.0;
    } else {
      top = top.clamp(10.0, maxTop);
    }

    _overlayOffset = Offset(left, top);
    _overlayWidth = bubbleWidth;
  }

  void _updateOverlay(BuildContext context, [Offset? newMousePosition]) {
    if (newMousePosition != null) {
      _mousePosition = newMousePosition;
    }

    if (!_isHovered || widget.text.isEmpty) {
      _hideOverlay();
      return;
    }

    _recalculatePosition();

    if (_overlayEntry != null) {
      // Overlay already exists — update in place without removing/reinserting
      _overlayEntry!.markNeedsBuild();
    } else {
      _overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          left: _overlayOffset.dx,
          top: _overlayOffset.dy,
          child: Material(
            color: Colors.transparent,
            child: _buildBubble(_overlayWidth),
          ),
        ),
      );
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  double _getBubbleWidth() {
    const textStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = (screenWidth - 20).clamp(80.0, 320.0);
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaleFactor: textScaleFactor,
    )..layout(minWidth: 0, maxWidth: maxWidth - widget.padding * 2);

    // 增加额外的宽度，确保组合键能够完整显示
    final String lowerText = widget.text.toLowerCase();
    double width;
    if (Platform.isWindows &&
        lowerText.contains('(') &&
        lowerText.contains(')')) {
      // 只在 Windows 端，如果文本包含括号（通常是快捷键），增加额外宽度
      width = textPainter.width + widget.padding * 2 + 20;
    } else if (lowerText.contains('shift') ||
        lowerText.contains('ctrl') ||
        lowerText.contains('command') ||
        lowerText.contains('tab') ||
        lowerText.contains('alt') ||
        lowerText.contains('esc')) {
      width = textPainter.width + widget.padding * 2 + 20;
    } else {
      width = textPainter.width + widget.padding * 2 + 4;
    }
    return width.clamp(48.0, maxWidth);
  }

  double _getBubbleHeight() {
    const textStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      textScaleFactor: textScaleFactor,
    )..layout(maxWidth: _getBubbleWidth() - widget.padding * 2);
    return (textPainter.height + 12).clamp(30.0, 48.0);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _enterTimer?.cancel();
    _exitTimer?.cancel();
    _hideOverlay();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TooltipBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text && _isHovered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateOverlay(context);
      });
    }
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
        _exitTimer?.cancel();
        _enterTimer = Timer(const Duration(milliseconds: 80), () {
          if (!mounted) return;
          setState(() => _isHovered = true);
          _updateOverlay(context, event.position);
        });
      },
      onExit: (_) {
        _enterTimer?.cancel();
        _exitTimer = Timer(const Duration(milliseconds: 50), () {
          if (!mounted) return;
          setState(() => _isHovered = false);
          _hideOverlay();
        });
      },
      child: KeyedSubtree(
        key: _childKey,
        child: widget.child,
      ),
    );
  }

  Widget _buildBubble(double width) {
    final colors = PlayerMenuTheme.colorsOf(context);
    final textStyle = TextStyle(
      color: colors.foreground,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );

    return PlayerOverlaySurface(
      width: width,
      height: _getBubbleHeight(),
      borderRadius: 8,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.padding),
          child: Text(
            widget.text,
            style: textStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
