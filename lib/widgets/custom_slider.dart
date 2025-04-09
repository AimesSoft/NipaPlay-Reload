import 'package:flutter/material.dart';
import 'dart:ui';

class CustomSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final String label;
  final String hintText;

  const CustomSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.hintText,
  });

  @override
  State<CustomSlider> createState() => _CustomSliderState();
}

class _CustomSliderState extends State<CustomSlider> with SingleTickerProviderStateMixin {
  final GlobalKey _sliderKey = GlobalKey();
  bool _isHovering = false;
  bool _isThumbHovered = false;
  bool _isDragging = false;
  OverlayEntry? _overlayEntry;
  late AnimationController _thumbAnimationController;
  late Animation<double> _thumbAnimation;

  @override
  void initState() {
    super.initState();
    _thumbAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _thumbAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _thumbAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _thumbAnimationController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(BuildContext context, double progress) {
    _removeOverlay();
    
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox == null) return;

    final position = sliderBox.localToGlobal(Offset.zero);
    final size = sliderBox.size;
    final bubbleX = position.dx + (progress * size.width) - 20;
    final bubbleY = position.dy - 40;

    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              left: bubbleX,
              top: bubbleY,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '${(widget.value * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateValueFromPosition(Offset localPosition) {
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox != null) {
      final width = sliderBox.size.width;
      final progress = (localPosition.dx / width).clamp(0.0, 1.0);
      
      // 将值调整为最接近的档位
      final List<double> steps = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];
      double closest = steps[0];
      for (double step in steps) {
        if ((progress - step).abs() < (progress - closest).abs()) {
          closest = step;
        }
      }
      
      widget.onChanged(closest);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        MouseRegion(
          onEnter: (_) {
            setState(() {
              _isHovering = true;
            });
          },
          onExit: (_) {
            setState(() {
              _isHovering = false;
            });
          },
          child: GestureDetector(
            onTapDown: (details) {
              setState(() => _isDragging = true);
              _updateValueFromPosition(details.localPosition);
              _showOverlay(context, widget.value);
            },
            onTapUp: (details) {
              setState(() => _isDragging = false);
              _updateValueFromPosition(details.localPosition);
              _removeOverlay();
            },
            onPanStart: (details) {
              setState(() => _isDragging = true);
              _showOverlay(context, widget.value);
            },
            onPanUpdate: (details) {
              _updateValueFromPosition(details.localPosition);
              _showOverlay(context, widget.value);
            },
            onPanEnd: (details) {
              setState(() => _isDragging = false);
              _removeOverlay();
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  key: _sliderKey,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 20,
                      child: FractionallySizedBox(
                        widthFactor: widget.value,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.3),
                                blurRadius: 2,
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (widget.value * constraints.maxWidth) - (_isThumbHovered || _isDragging ? 8 : 6),
                      top: 22 - (_isThumbHovered || _isDragging ? 8 : 6),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) {
                          setState(() => _isThumbHovered = true);
                          _thumbAnimationController.forward();
                        },
                        onExit: (_) {
                          setState(() => _isThumbHovered = false);
                          _thumbAnimationController.reverse();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
                          width: _isThumbHovered || _isDragging ? 16 : 12,
                          height: _isThumbHovered || _isDragging ? 16 : 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: _isThumbHovered || _isDragging ? 6 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.hintText,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
} 