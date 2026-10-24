import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/host_settings.dart';
import '../settings/settings_layout.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import 'shell_controller.dart';

/// Whether Nipa has a model to think with, from this device's own
/// settings. Everything else in Next works without one; where Nipa is
/// (her avatar, the conversation's input) shows the way to set one up,
/// never in the way.
class NipaSetup extends ChangeNotifier {
  NipaSetup(this.host) {
    _load();
    _changes = host.changes.listen((_) => _load());
  }

  final NextHostSettings host;
  late final StreamSubscription<void> _changes;
  bool _needsModel = false;
  double? _preparing;
  bool _isPreparing = false;

  /// No model is set up, or the one set up cannot be used.
  bool get needsModel => _needsModel;

  /// NipaPlay is fetching what Nipa runs on: how far, when that is known.
  bool get preparing => _isPreparing;
  double? get progress => _preparing;

  Future<void> _load() async {
    try {
      // Reading the model touches the vault; a download reports often, and
      // its progress is all that changes while it runs.
      if (host is NextHostRuntimeSettings) {
        final dsh = await (host as NextHostRuntimeSettings).dshRuntime();
        final busy = dsh.status == UiDshStatus.downloading ||
            dsh.status == UiDshStatus.unpacking;
        final total = dsh.totalBytes;
        final progress = dsh.status == UiDshStatus.downloading && total != null
            ? (dsh.receivedBytes / total).clamp(0.0, 1.0)
            : null;
        if (busy != _isPreparing || progress != _preparing) {
          _isPreparing = busy;
          _preparing = progress;
          _needsModel = busy || _needsModel;
          notifyListeners();
        }
        if (busy) return;
      }
      final setup = await host.model();
      _set(setup.problem != null);
    } on UnsupportedError {
      try {
        _set((await host.model()).problem != null);
      } catch (e) {
        debugPrint('[NextUi] model setup: $e');
      }
    } catch (e) {
      debugPrint('[NextUi] model setup: $e');
    }
  }

  /// Reads the setup again (after the settings page changed it).
  Future<void> reload() => _load();

  void _set(bool needs) {
    if (needs == _needsModel) return;
    _needsModel = needs;
    notifyListeners();
  }

  @override
  void dispose() {
    _changes.cancel();
    super.dispose();
  }
}

/// The way to Nipa's settings: an amber dot and “设置 Nipa”. Nothing at
/// all when she has a model.
class NipaSetupChip extends StatelessWidget {
  const NipaSetupChip({super.key, this.padding = EdgeInsets.zero});

  /// Around it, when it shows.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    return ListenableBuilder(
      listenable: shell.nipaSetup,
      builder: (context, _) => !shell.nipaSetup.needsModel
          ? const SizedBox.shrink()
          : Padding(
              padding: padding,
              child: Pressable(
              onTap: () => shell.openSettings(section: SettingsSection.nipa),
              semanticLabel: '设置 Nipa',
              builder: (context, hovered) => AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: hovered
                      ? const Color(0x1FFFBF5C)
                      : const Color(0x0FFFBF5C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x40FFBF5C)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const NipaSetupDot(),
                  const SizedBox(width: 8),
                  Text(
                      shell.nipaSetup.preparing
                          ? shell.nipaSetup.progress == null
                              ? '正在准备 Nipa'
                              : '正在准备 Nipa · ${(shell.nipaSetup.progress! * 100).floor()}%'
                          : '设置 Nipa',
                      style: NextText.sans(12.5,
                          color: hovered ? NextColors.paper : NextColors.p2)),
                ]),
              ),
            ),
            ),
    );
  }
}

/// The small amber dot that means Nipa has no model yet.
class NipaSetupDot extends StatelessWidget {
  const NipaSetupDot({super.key, this.size = 6});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: NextColors.amber,
          boxShadow: [BoxShadow(color: Color(0x99FFBF5C), blurRadius: 6)],
        ),
      );
}
