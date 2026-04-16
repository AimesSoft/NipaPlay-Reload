import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/providers/theme_background_reveal_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/background_image_compositor.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

String backgroundImageUrl = (globals.isDesktop || globals.isTablet)
    ? 'assets/images/main_image.png'
    : 'assets/images/main_image_mobile.png';

String backgroundImageUrl2 = (globals.isDesktop || globals.isTablet)
    ? 'assets/images/main_image2.png'
    : 'assets/images/main_image_mobile2.png';

const _themeTransitionDuration = Duration(milliseconds: 420);
const _themeTransitionCurve = Curves.easeInOutCubic;

class BackgroundBackdrop extends StatelessWidget {
  const BackgroundBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer3<
      SettingsProvider,
      ThemeNotifier,
      ThemeBackgroundRevealProvider
    >(
      builder: (context, settingsProvider, themeNotifier, revealProvider, _) {
        final Duration backgroundTransitionDuration = revealProvider.isActive
            ? Duration.zero
            : _themeTransitionDuration;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: _buildBackgroundImage(
                context,
                themeNotifier,
                duration: backgroundTransitionDuration,
              ),
            ),
            if (settingsProvider.isBlurEnabled)
              Positioned.fill(
                child: GlassmorphicContainer(
                  blur: settingsProvider.blurPower,
                  alignment: Alignment.center,
                  borderRadius: 0,
                  border: 0,
                  padding: const EdgeInsets.all(20),
                  height: double.infinity,
                  width: double.infinity,
                  linearGradient: LinearGradient(
                    colors: [
                      const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0),
                      const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderGradient: LinearGradient(
                    colors: [
                      const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0.3),
                      const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            if (revealProvider.isActive)
              Positioned.fill(
                child: _BackgroundRevealOverlay(
                  epoch: revealProvider.epoch,
                  origin: revealProvider.origin,
                  maxRadius: revealProvider.maxRadius,
                  color: revealProvider.color,
                  reverse: revealProvider.reverse,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBackgroundImage(
    BuildContext context,
    ThemeNotifier themeNotifier, {
    required Duration duration,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDarkMode
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFF2F2F2);

    Widget buildComposite(Widget image) {
      return Stack(
        fit: StackFit.expand,
        children: [
          AnimatedContainer(
            duration: duration,
            curve: _themeTransitionCurve,
            color: baseColor,
          ),
          BackgroundImageCompositor(
            image: image,
            overlayColor: baseColor,
            renderMode: themeNotifier.backgroundImageRenderMode,
            overlayOpacity: themeNotifier.backgroundImageOverlayOpacity,
            duration: duration,
            curve: _themeTransitionCurve,
          ),
        ],
      );
    }

    if (globals.backgroundImageMode == '关闭') {
      return AnimatedContainer(
        duration: duration,
        curve: _themeTransitionCurve,
        color: baseColor,
      );
    } else if (globals.backgroundImageMode == '看板娘') {
      return buildComposite(Image.asset(backgroundImageUrl, fit: BoxFit.cover));
    } else if (globals.backgroundImageMode == '看板娘2') {
      return buildComposite(
        Image.asset(backgroundImageUrl2, fit: BoxFit.cover),
      );
    } else if (globals.backgroundImageMode == '自定义') {
      if (kIsWeb) {
        return buildComposite(
          Image.asset(backgroundImageUrl, fit: BoxFit.cover),
        );
      }
      final file = File(globals.customBackgroundPath);
      if (file.existsSync()) {
        return buildComposite(
          Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Image.asset(backgroundImageUrl, fit: BoxFit.cover);
            },
          ),
        );
      } else {
        return buildComposite(
          Image.asset(backgroundImageUrl, fit: BoxFit.cover),
        );
      }
    }
    return buildComposite(Image.asset(backgroundImageUrl, fit: BoxFit.cover));
  }
}

class BackgroundWithBlur extends StatelessWidget {
  final Widget child;
  final Rect? transparentCutout;

  const BackgroundWithBlur({
    super.key,
    required this.child,
    this.transparentCutout,
  });

  @override
  Widget build(BuildContext context) {
    final background = transparentCutout == null
        ? const BackgroundBackdrop()
        : ClipPath(
            clipper: _TransparentCutoutClipper(cutout: transparentCutout!),
            child: const BackgroundBackdrop(),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: background),
        child,
      ],
    );
  }
}

class _BackgroundRevealOverlay extends StatefulWidget {
  final int epoch;
  final Offset origin;
  final double maxRadius;
  final Color color;
  final bool reverse;

  const _BackgroundRevealOverlay({
    required this.epoch,
    required this.origin,
    required this.maxRadius,
    required this.color,
    required this.reverse,
  });

  @override
  State<_BackgroundRevealOverlay> createState() =>
      _BackgroundRevealOverlayState();
}

class _BackgroundRevealOverlayState extends State<_BackgroundRevealOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ThemeBackgroundRevealProvider.duration,
  )..forward();
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(covariant _BackgroundRevealOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.epoch != widget.epoch) {
      _controller
        ..stop()
        ..value = 0
        ..forward();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_handleStatusChanged);
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    if (!mounted) {
      return;
    }
    context.read<ThemeBackgroundRevealProvider>().markAnimationCompleted(
      widget.epoch,
    );
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          return CustomPaint(
            painter: _BackgroundRevealPainter(
              origin: widget.origin,
              radius: widget.maxRadius * _animation.value,
              color: widget.color,
              reverse: widget.reverse,
            ),
          );
        },
      ),
    );
  }
}

class _BackgroundRevealPainter extends CustomPainter {
  final Offset origin;
  final double radius;
  final Color color;
  final bool reverse;

  const _BackgroundRevealPainter({
    required this.origin,
    required this.radius,
    required this.color,
    required this.reverse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final maxRadius = _computeMaxRadius(size);
    if (reverse) {
      canvas.saveLayer(rect, Paint());
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      final holeRadius = (maxRadius - radius).clamp(0.0, maxRadius);
      canvas.drawCircle(
        origin,
        holeRadius,
        Paint()
          ..blendMode = BlendMode.clear
          ..isAntiAlias = true,
      );
      canvas.restore();
      return;
    }

    canvas.saveLayer(rect, Paint());
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..blendMode = BlendMode.clear
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  double _computeMaxRadius(Size size) {
    final topLeft = (origin - Offset.zero).distance;
    final topRight = (origin - Offset(size.width, 0)).distance;
    final bottomLeft = (origin - Offset(0, size.height)).distance;
    final bottomRight = (origin - Offset(size.width, size.height)).distance;
    return [
      topLeft,
      topRight,
      bottomLeft,
      bottomRight,
    ].reduce((a, b) => a > b ? a : b);
  }

  @override
  bool shouldRepaint(covariant _BackgroundRevealPainter oldDelegate) {
    return oldDelegate.origin != origin ||
        oldDelegate.radius != radius ||
        oldDelegate.color != color ||
        oldDelegate.reverse != reverse;
  }
}

class _TransparentCutoutClipper extends CustomClipper<Path> {
  const _TransparentCutoutClipper({required this.cutout});

  final Rect cutout;

  @override
  Path getClip(Size size) {
    final bounds = Offset.zero & size;
    final effectiveCutout = cutout.intersect(bounds);
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addRect(bounds);
    if (!effectiveCutout.isEmpty) {
      path.addRect(effectiveCutout);
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _TransparentCutoutClipper oldClipper) {
    return oldClipper.cutout != cutout;
  }
}
