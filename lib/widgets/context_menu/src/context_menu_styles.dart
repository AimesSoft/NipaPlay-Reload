import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

import 'context_menu_widgets.dart';

class ContextMenuStyles {
  static ContextMenuStyle glass(BuildContext context) {
    if (kIsWeb) {
      return ContextMenuStyle(
        width: 196,
        itemHeight: 44,
        borderRadius: 8,
        itemPadding: const EdgeInsets.symmetric(horizontal: 14),
        iconSize: 18,
        iconColor: Colors.white,
        labelStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
        disabledForegroundColor: Colors.white54,
        hoverColor: Colors.white.withOpacity(0.10),
        highlightColor: Colors.white.withOpacity(0.08),
        surfaceBuilder: (context, style, size, child) {
          return SizedBox(
            width: size.width,
            height: size.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(style.borderRadius),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.15),
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(style.borderRadius),
                ),
                child: child,
              ),
            ),
          );
        },
      );
    }

    final enableBlur =
        context.read<AppearanceSettingsProvider>().enableWidgetBlurEffect;

    return ContextMenuStyle(
      width: 196,
      itemHeight: 44,
      borderRadius: 8,
      itemPadding: const EdgeInsets.symmetric(horizontal: 14),
      iconSize: 18,
      iconColor: Colors.white,
      labelStyle: const TextStyle(
        color: Colors.white,
        fontSize: 13,
      ),
      disabledForegroundColor: Colors.white54,
      hoverColor: Colors.white.withOpacity(0.10),
      highlightColor: Colors.white.withOpacity(0.08),
      surfaceBuilder: (context, style, size, child) {
        return GlassmorphicContainer(
          width: size.width,
          height: size.height,
          borderRadius: style.borderRadius,
          blur: enableBlur ? 16 : 0,
          border: 0.8,
          alignment: Alignment.center,
          linearGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.18),
              Colors.white.withOpacity(0.08),
            ],
          ),
          borderGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.45),
              Colors.white.withOpacity(0.15),
            ],
          ),
          child: child,
        );
      },
    );
  }

  static ContextMenuStyle solidDark() {
    return ContextMenuStyle(
      width: 196,
      itemHeight: 44,
      borderRadius: 8,
      itemPadding: const EdgeInsets.symmetric(horizontal: 14),
      iconSize: 18,
      iconColor: Colors.white,
      labelStyle: const TextStyle(
        color: Colors.white,
        fontSize: 13,
      ),
      disabledForegroundColor: Colors.white54,
      hoverColor: Colors.white.withOpacity(0.10),
      highlightColor: Colors.white.withOpacity(0.08),
      surfaceBuilder: (context, style, size, child) {
        return SizedBox(
          width: size.width,
          height: size.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(style.borderRadius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.72),
                border: Border.all(
                  color: Colors.white.withOpacity(0.18),
                  width: 0.8,
                ),
                borderRadius: BorderRadius.circular(style.borderRadius),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

