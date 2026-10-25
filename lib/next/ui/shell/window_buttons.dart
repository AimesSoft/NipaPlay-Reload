import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../widgets/buttons.dart';
import '../widgets/icons.dart';

/// Minimize, maximize or restore, and close, on the bar of the window. The
/// window has no frame of its own on Windows (Classic draws the buttons, and
/// Classic is under Next), so the Next bars carry them; macOS has its traffic
/// lights.
class NextWindowButtons extends StatefulWidget {
  const NextWindowButtons({super.key});

  static bool get wanted => !kIsWeb && Platform.isWindows;

  static const _size = 32.0;
  static const _gap = 12.0;

  /// The space the buttons and the gap before them take on the bar.
  static double get width => wanted ? _gap + 3 * _size : 0;

  @override
  State<NextWindowButtons> createState() => _NextWindowButtonsState();
}

class _NextWindowButtonsState extends State<NextWindowButtons>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _maximized = value);
    }, onError: (Object _) {})); // no window yet (a test, a headless view)
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: NextWindowButtons._gap),
        NextIconButton(
            glyph: NextGlyph.minus,
            label: '最小化',
            size: NextWindowButtons._size,
            onTap: () => unawaited(windowManager.minimize())),
        NextIconButton(
            glyph: _maximized ? NextGlyph.restore : NextGlyph.maximize,
            label: _maximized ? '还原' : '最大化',
            size: NextWindowButtons._size,
            onTap: () => unawaited(_maximized
                ? windowManager.unmaximize()
                : windowManager.maximize())),
        NextIconButton(
            glyph: NextGlyph.close,
            label: '关闭',
            size: NextWindowButtons._size,
            onTap: () => unawaited(windowManager.close())),
      ]);
}
