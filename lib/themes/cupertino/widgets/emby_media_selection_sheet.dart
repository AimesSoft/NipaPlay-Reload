import 'package:flutter/material.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

typedef EmbySelectionSheetContentBuilder = Widget Function(
  ValueChanged<bool> close,
);

/// Shows media selection inside the standard bottom-sheet surface.
Future<bool?> showEmbyMediaSelectionSheet({
  required BuildContext context,
  required bool Function() isSaving,
  required VoidCallback onDismiss,
  required EmbySelectionSheetContentBuilder contentBuilder,
}) {
  final guardKey = GlobalKey<_EmbySelectionSheetGuardState>();
  return CupertinoBottomSheet.show<bool>(
    context: context,
    title: '版本与轨道',
    heightRatio: 0.94,
    barrierDismissible: false,
    onClose: () => guardKey.currentState?.dismiss(),
    child: _EmbySelectionSheetGuard(
      key: guardKey,
      isSaving: isSaving,
      onDismiss: onDismiss,
      contentBuilder: contentBuilder,
    ),
  );
}

class _EmbySelectionSheetGuard extends StatefulWidget {
  const _EmbySelectionSheetGuard({
    super.key,
    required this.isSaving,
    required this.onDismiss,
    required this.contentBuilder,
  });

  final bool Function() isSaving;
  final VoidCallback onDismiss;
  final EmbySelectionSheetContentBuilder contentBuilder;

  @override
  State<_EmbySelectionSheetGuard> createState() =>
      _EmbySelectionSheetGuardState();
}

class _EmbySelectionSheetGuardState extends State<_EmbySelectionSheetGuard> {
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
      child: Material(
        color: Colors.transparent,
        child: widget.contentBuilder(_complete),
      ),
    );
  }
}
