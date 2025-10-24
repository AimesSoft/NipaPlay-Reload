import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class CupertinoPlayerIndicator extends StatelessWidget {
  final bool isVisible;
  final double value;
  final IconData icon;
  final String label;

  const CupertinoPlayerIndicator({
    super.key,
    required this.isVisible,
    required this.value,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final double clampedValue = value.clamp(0.0, 1.0);
    final double barHeight = globals.isDesktopOrTablet
        ? MediaQuery.of(context).size.height * 0.22
        : MediaQuery.of(context).size.height * 0.45;

    return AnimatedOpacity(
      opacity: isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 160),
      child: IgnorePointer(
        child: AdaptiveBlurView(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(height: 12),
                _CupertinoVerticalBar(value: clampedValue, height: barHeight),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                    shadows: [
                      Shadow(
                        color: Color.fromARGB(140, 0, 0, 0),
                        offset: Offset(0, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CupertinoVerticalBar extends StatelessWidget {
  final double value;
  final double height;

  const _CupertinoVerticalBar({required this.value, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 10,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                  ),
                ),
                FractionallySizedBox(
                  heightFactor: value,
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.white,
                          Color.fromARGB(230, 255, 255, 255),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
