import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'typing_text.dart';

class LoadingOverlay extends StatelessWidget {
  final List<String> messages;
  final double width;
  final double height;
  final double blur;
  final double borderWidth;
  final double borderRadius;
  final Color backgroundColor;
  final double backgroundOpacity;
  final Color textColor;
  final double textOpacity;
  final double fontSize;
  final bool isBold;

  const LoadingOverlay({
    super.key,
    required this.messages,
    this.width = 300,
    this.height = 150,
    this.blur = 20,
    this.borderWidth = 1.5,
    this.borderRadius = 24,
    this.backgroundColor = Colors.black,
    this.backgroundOpacity = 0.3,
    this.textColor = Colors.white,
    this.textOpacity = 0.9,
    this.fontSize = 16,
    this.isBold = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景
        Container(
          color: backgroundColor.withOpacity(backgroundOpacity),
        ),
        // 毛玻璃加载界面
        Center(
          child: GlassmorphicContainer(
            width: width,
            height: height,
            borderRadius: borderRadius,
            blur: blur,
            alignment: Alignment.bottomCenter,
            border: borderWidth,
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(height: 20),
                TypingText(
                  messages: messages,
                  style: TextStyle(
                    color: textColor.withOpacity(textOpacity),
                    fontSize: fontSize,
                    fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
                    letterSpacing: 0.5,
                  ),
                  typingSpeed: const Duration(milliseconds: 50),
                  deleteSpeed: const Duration(milliseconds: 30),
                  pauseDuration: const Duration(seconds: 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
} 