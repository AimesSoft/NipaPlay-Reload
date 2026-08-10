import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:provider/provider.dart';

typedef EmbySelectionContentBuilder = Widget Function(
  ValueChanged<bool> close,
);

/// Calculates responsive size limits for the desktop Emby selection dialog.
({double maxWidth, double maxHeightFactor}) calculateEmbySelectionDialogMetrics(
    Size screenSize) {
  final targetWidth = (screenSize.width * 0.72).clamp(680.0, 860.0).toDouble();
  final targetHeight =
      (screenSize.height * 0.78).clamp(560.0, 760.0).toDouble();
  return (
    maxWidth: screenSize.width <= 0 ? 0.0 : targetWidth,
    maxHeightFactor: screenSize.height <= 0
        ? 0.0
        : math.min(targetHeight / screenSize.height, 1.0),
  );
}

/// Shows media selection inside the standard desktop window surface.
Future<bool?> showEmbyMediaSelectionDialog({
  required BuildContext context,
  required bool Function() isSaving,
  required VoidCallback onDismiss,
  required EmbySelectionContentBuilder contentBuilder,
}) {
  final enableAnimation =
      context.read<AppearanceSettingsProvider>().enablePageAnimation;
  final guardKey = GlobalKey<_EmbySelectionDialogGuardState>();
  return NipaplayWindow.show<bool>(
    context: context,
    enableAnimation: enableAnimation,
    barrierDismissible: false,
    child: Builder(
      builder: (dialogContext) {
        final metrics = calculateEmbySelectionDialogMetrics(
          MediaQuery.sizeOf(dialogContext),
        );
        return NipaplayWindowScaffold(
          maxWidth: metrics.maxWidth,
          maxHeightFactor: metrics.maxHeightFactor,
          respectMaxSizeInFilledScreen: true,
          onClose: () => guardKey.currentState?.dismiss(),
          child: _EmbySelectionDialogGuard(
            key: guardKey,
            isSaving: isSaving,
            onDismiss: onDismiss,
            contentBuilder: contentBuilder,
          ),
        );
      },
    ),
  );
}

class _EmbySelectionDialogGuard extends StatefulWidget {
  const _EmbySelectionDialogGuard({
    super.key,
    required this.isSaving,
    required this.onDismiss,
    required this.contentBuilder,
  });

  final bool Function() isSaving;
  final VoidCallback onDismiss;
  final EmbySelectionContentBuilder contentBuilder;

  @override
  State<_EmbySelectionDialogGuard> createState() =>
      _EmbySelectionDialogGuardState();
}

class _EmbySelectionDialogGuardState extends State<_EmbySelectionDialogGuard> {
  bool _allowPop = false;
  bool _closing = false;

  void dismiss() {
    if (_closing || widget.isSaving()) return;
    widget.onDismiss();
    _complete(false);
  }

  void _complete(bool result) {
    if (_closing) return;
    _closing = true;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop<bool>(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) dismiss();
      },
      child: widget.contentBuilder(_complete),
    );
  }
}
