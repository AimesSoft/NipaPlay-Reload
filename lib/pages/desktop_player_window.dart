import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nipaplay/l10n/app_locale_utils.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/utils/app_theme.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

/// The player surface rendered in the secondary FlutterView.
///
/// Providers live above DesktopMultiWindowHost, so this MaterialApp sees the
/// same VideoPlayerState and Player instance as the main window.
class DesktopPlayerWindow extends StatelessWidget {
  const DesktopPlayerWindow({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeNotifier>().themeMode;
    final locale = context.watch<AppLanguageProvider>().locale;

    return MaterialApp(
      title: 'NipaPlay 独立播放器',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        fontFamilyFallback: AppTheme.platformFontFamilyFallback,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamilyFallback: AppTheme.platformFontFamilyFallback,
      ),
      locale: locale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          final controller = DesktopMultiWindow.controllerOf(context);
          return ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PlayVideoPage(
                  key: DesktopPlayerWindowService.instance.playerPageKey,
                ),
                // Keep native title chrome out of the player while retaining a
                // generous draggable area between its left and right actions.
                Positioned(
                  top: 0,
                  left: 72,
                  right: 72,
                  height: 38,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (_) {
                        unawaited(controller.startDragging());
                      },
                      onPointerMove: (_) {
                        if (defaultTargetPlatform == TargetPlatform.macOS) {
                          unawaited(controller.updateDragging());
                        }
                      },
                      onPointerUp: (_) {
                        if (defaultTargetPlatform == TargetPlatform.macOS) {
                          unawaited(controller.endDragging());
                        }
                      },
                      onPointerCancel: (_) {
                        if (defaultTargetPlatform == TargetPlatform.macOS) {
                          unawaited(controller.endDragging());
                        }
                      },
                      child: const Center(child: _WindowDragHandle()),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WindowDragHandle extends StatelessWidget {
  const _WindowDragHandle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 4),
          ],
        ),
      ),
    );
  }
}
