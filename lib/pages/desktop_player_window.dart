import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nipaplay/l10n/app_locale_utils.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/utils/app_theme.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/widgets/desktop_picture_in_picture_scope.dart';
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
    final windowController = DesktopMultiWindow.controllerOf(context);
    final usesWindowHostedVideoSurface = context.select<VideoPlayerState, bool>(
      (videoState) => videoState.player.usesWindowOverlayVideoSurface,
    );

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
      home: ListenableBuilder(
        listenable: DesktopPlayerWindowService.instance,
        builder: (context, _) {
          final isPictureInPicture =
              DesktopPlayerWindowService.instance.isPictureInPicture;
          return DesktopPictureInPictureScope(
            enabled: isPictureInPicture,
            child: ColoredBox(
              // Erika and the desktop HDR path render into a native surface
              // hosted below Flutter. Keep this view transparent so the
              // surface remains visible while Flutter controls stay above it.
              color: usesWindowHostedVideoSurface
                  ? Colors.transparent
                  : Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PlayVideoPage(
                    key: DesktopPlayerWindowService.instance.playerPageKey,
                  ),
                  Positioned(
                    top: 0,
                    left: isPictureInPicture ? 72 : 96,
                    right: isPictureInPicture ? 72 : 128,
                    height: 38,
                    child: ListenableBuilder(
                      listenable: windowController,
                      builder: (context, _) => windowController.isFullscreen
                          ? const SizedBox.shrink()
                          : _DetachedWindowDragRegion(
                              controller: windowController,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DetachedWindowDragRegion extends StatefulWidget {
  const _DetachedWindowDragRegion({required this.controller});

  final WindowController controller;

  @override
  State<_DetachedWindowDragRegion> createState() =>
      _DetachedWindowDragRegionState();
}

class _DetachedWindowDragRegionState extends State<_DetachedWindowDragRegion> {
  bool _dragging = false;

  void _start(PointerDownEvent event) {
    if (event.buttons & kPrimaryMouseButton == 0) return;
    _dragging = true;
    unawaited(widget.controller.startDragging());
  }

  void _update(PointerMoveEvent event) {
    if (!_dragging) return;
    unawaited(widget.controller.updateDragging());
  }

  void _end(PointerEvent event) {
    if (!_dragging) return;
    _dragging = false;
    unawaited(widget.controller.endDragging());
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _start,
        onPointerMove: _update,
        onPointerUp: _end,
        onPointerCancel: _end,
        child: const SizedBox.expand(),
      ),
    );
  }
}
