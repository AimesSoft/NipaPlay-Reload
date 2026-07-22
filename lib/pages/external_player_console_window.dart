import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nipaplay/l10n/app_locale_utils.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/pages/external_player_console_page.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/utils/app_theme.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

class ExternalPlayerConsoleWindow extends StatelessWidget {
  const ExternalPlayerConsoleWindow({
    super.key,
    required this.controller,
    required this.pane,
    required this.onClose,
    this.onShowDanmakuList,
  });

  final WindowController controller;
  final ExternalPlayerConsolePane pane;
  final VoidCallback onClose;
  final VoidCallback? onShowDanmakuList;

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeNotifier>().themeMode;
    final locale = context.watch<AppLanguageProvider>().locale;

    return MaterialApp(
      title: pane == ExternalPlayerConsolePane.danmakuList
          ? 'NipaPlay 弹幕列表'
          : 'NipaPlay 弹幕控制台',
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
          return ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ExternalPlayerConsolePage(
                  pane: pane,
                  onShowDanmakuList: onShowDanmakuList,
                  onCloseWindow: onClose,
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: onShowDanmakuList == null ? 66 : 120,
                  height: 48,
                  child: _ConsoleWindowDragRegion(controller: controller),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConsoleWindowDragRegion extends StatefulWidget {
  const _ConsoleWindowDragRegion({required this.controller});

  final WindowController controller;

  @override
  State<_ConsoleWindowDragRegion> createState() =>
      _ConsoleWindowDragRegionState();
}

class _ConsoleWindowDragRegionState extends State<_ConsoleWindowDragRegion> {
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
