import 'package:flutter/widgets.dart';

import '../data/downloads.dart';
import '../data/gui_calls.dart';
import '../data/services.dart';
import '../settings/controls.dart' show FieldControl, StateDot;
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/progress.dart';
import '../widgets/sheet.dart';
import 'units.dart';

/// How fast downloads may go, each way, as the downloader reads it back.
/// When it cannot be limited, the sheet says so and nothing more.
Future<void> openLimits(NextUiServices services) => showNextSheet<void>(
      width: 460,
      (context, close) => LimitsSheet(services: services, onClose: close),
    );

class LimitsSheet extends StatefulWidget {
  const LimitsSheet({super.key, required this.services, required this.onClose});
  final NextUiServices services;
  final VoidCallback onClose;

  @override
  State<LimitsSheet> createState() => _LimitsSheetState();
}

class _LimitsSheetState extends State<LimitsSheet> {
  UiDownloadLimits? _limits;
  String? _said;
  bool _busy = false;

  static const _presets = [0, 1 << 20, 5 << 20, 20 << 20];

  @override
  void initState() {
    super.initState();
    widget.services.downloads.limits().then((l) {
      if (mounted) setState(() => _limits = l);
    }, onError: (Object e) {
      if (mounted) setState(() => _said = callFailure(e));
    });
  }

  Future<void> _set({int? down, int? up}) async {
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      final l = await widget.services.downloads.setLimits(down: down, up: up);
      if (mounted) setState(() => _limits = l);
    } catch (e) {
      if (mounted) setState(() => _said = callFailure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _limits;
    return SheetSurface(
      padding: const EdgeInsets.fromLTRB(26, 22, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('限速',
                  style: NextText.sans(17, weight: FontWeight.w600)),
            ),
            if (_busy)
              const Padding(
                  padding: EdgeInsets.only(right: 8), child: ThinkingDots()),
            NextIconButton(
                glyph: NextGlyph.close, label: '关闭', onTap: widget.onClose),
          ]),
          const SizedBox(height: 18),
          if (l == null && _said == null)
            const SizedBox(height: 90, child: Center(child: ThinkingDots()))
          else if (l != null && !l.supported)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text('这个下载器不能限速',
                  style: NextText.sans(13.5, color: NextColors.p3)),
            )
          else if (l != null) ...[
            _Direction(
              label: '下载',
              value: l.down,
              presets: _presets,
              onSet: (v) => _set(down: v),
            ),
            const SizedBox(height: 14),
            _Direction(
              label: '上传',
              value: l.up,
              presets: _presets,
              onSet: (v) => _set(up: v),
            ),
            if (!l.running) ...[
              const SizedBox(height: 18),
              Row(children: [
                const StateDot(NextColors.p4, glow: false),
                const SizedBox(width: 8),
                Text('下载器没在运行',
                    style: NextText.sans(12.5, color: NextColors.p3)),
              ]),
            ],
          ],
          if (_said != null) ...[
            const SizedBox(height: 14),
            Text(_said!, style: NextText.sans(12.5, color: NextColors.accent2)),
          ],
        ],
      ),
    );
  }
}

/// One direction: a few common limits, and any other in KB/s.
class _Direction extends StatelessWidget {
  const _Direction(
      {required this.label,
      required this.value,
      required this.presets,
      required this.onSet});
  final String label;
  final int value;
  final List<int> presets;
  final ValueChanged<int> onSet;

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(
          width: 48,
          child:
              Text(label, style: NextText.sans(13.5, color: NextColors.p2)),
        ),
        for (final p in presets) ...[
          _Chip(
            label: p == 0 ? '不限' : rateText(p),
            on: p == value,
            onTap: () => onSet(p),
          ),
          const SizedBox(width: 6),
        ],
        const Spacer(),
        FieldControl(
          value: presets.contains(value) ? '' : '${value ~/ 1024}',
          hint: 'KB/s',
          width: 84,
          numeric: true,
          align: TextAlign.right,
          onCommit: (text) {
            final kb = int.tryParse(text.trim());
            if (kb == null) return;
            onSet(kb == 0
                ? 0
                : (kb * 1024).clamp(UiDownloadLimits.minimum, 4294967295));
          },
        ),
      ]);
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: on ? null : onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on
                ? NextColors.accentSoft
                : hovered
                    ? const Color(0x14FFFFFF)
                    : const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: on ? const Color(0x59FF2E55) : NextColors.line),
          ),
          child: Text(label,
              style: NextText.num(12,
                  color: on ? NextColors.accent2 : NextColors.p2)),
        ),
      );
}
