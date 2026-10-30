import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../player/next_playback.dart';
import '../data/settings_data.dart';
import '../settings/controls.dart';
import '../settings/registry_rows.dart' show SettingsModel;
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import 'menu_controls.dart';

/// The registry's settings as the player's menus show them: read when a
/// page of them opens, each change set as the settings page sets it
/// (`settings.set`, as the person), so what plays takes it at once and
/// Nipa sees who changed it.
class PlayerSettings extends StatefulWidget {
  const PlayerSettings({
    super.key,
    required this.data,
    required this.builder,
  });
  final NextSettingsData data;
  final Widget Function(BuildContext context, SettingsModel model) builder;

  @override
  State<PlayerSettings> createState() => _PlayerSettingsState();
}

class _PlayerSettingsState extends State<PlayerSettings> {
  late final _model = SettingsModel(widget.data);

  @override
  void initState() {
    super.initState();
    _model.addListener(_changed);
    unawaited(_model.load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_model.all == null) {
      return SizedBox(
        height: 58,
        child: Center(
          child: _model.failed == null
              ? const BusyDots()
              : Text('现在读不到设置',
                  style: NextText.sans(13, color: NextColors.p3)),
        ),
      );
    }
    return widget.builder(context, _model);
  }
}

/// A page of settings, scrolled when it is taller than the room above the
/// bar.
class PlayerSettingsPage extends StatelessWidget {
  const PlayerSettingsPage(
      {super.key, required this.title, required this.onBack, required this.children});
  final String title;
  final VoidCallback onBack;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final room = MediaQuery.sizeOf(context).height - 150;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Align(
          alignment: Alignment.centerLeft,
          child: PlayerMenuBack(title, onTap: onBack)),
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(200, math.min(480, room))),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ...children,
            const SizedBox(height: 4),
          ]),
        ),
      ),
    ]);
  }
}

/// A row of a settings page: its name on the left, the control after it.
class PlayerSettingRow extends StatelessWidget {
  const PlayerSettingRow({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = 72,
    this.note,
  });
  final String label;
  final Widget child;
  final double labelWidth;

  /// Why it was not taken, under the row for a while.
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 42,
            child: Row(children: [
              SizedBox(
                width: labelWidth,
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(13.5, color: NextColors.p2)),
              ),
              Expanded(child: child),
            ]),
          ),
          if (note case final note?)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(note,
                    style: NextText.sans(11.5, color: NextColors.accent)),
              ),
            ),
        ]),
      );
}

/// A heading inside a settings page.
class PlayerSettingHeading extends StatelessWidget {
  const PlayerSettingHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: NextText.sans(11.5,
                  weight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: NextColors.p4)),
        ),
      );
}

double _number(SettingsModel model, String key, double fallback) {
  final v = model[key]?.value;
  return v is num ? v.toDouble() : fallback;
}

/// A number of the registry on a slider: what it is set to shows while
/// dragged, letting go sets it.
class PlayerSettingSlider extends StatelessWidget {
  const PlayerSettingSlider({
    super.key,
    required this.model,
    required this.setting,
    required this.label,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
  });
  final SettingsModel model;
  final String setting;
  final String label;
  final double min, max, step;
  final DialUnit unit;

  @override
  Widget build(BuildContext context) {
    final s = model[setting];
    if (s == null) return const SizedBox.shrink();
    final value = _number(model, setting, min).clamp(min, max).toDouble();
    return PlayerSettingRow(
      label: label,
      note: model.errors[setting],
      child: PlayerMenuSlider(
        label: label,
        dial: PlayerDial(value, min, max, step, unit),
        onChanged: (_) {},
        onEnd: (v) =>
            unawaited(model.change(setting, s.integer ? v.round() : v)),
      ),
    );
  }
}

/// A number of the registry, a step a click: − value +.
class PlayerSettingStepper extends StatelessWidget {
  const PlayerSettingStepper({
    super.key,
    required this.model,
    required this.setting,
    required this.label,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    this.rest = 0,
  });
  final SettingsModel model;
  final String setting;
  final String label;
  final double min, max, step, rest;
  final DialUnit unit;

  @override
  Widget build(BuildContext context) {
    final s = model[setting];
    if (s == null) return const SizedBox.shrink();
    final value = _number(model, setting, rest).clamp(min, max).toDouble();
    return PlayerSettingRow(
      label: label,
      note: model.errors[setting],
      child: Align(
        alignment: Alignment.centerRight,
        child: PlayerMenuStepper(
          label: label,
          dial: PlayerDial(value, min, max, step, unit),
          rest: rest,
          onChanged: (v) =>
              unawaited(model.change(setting, s.integer ? v.round() : v)),
        ),
      ),
    );
  }
}

/// A switch of the registry.
class PlayerSettingToggle extends StatelessWidget {
  const PlayerSettingToggle(
      {super.key, required this.model, required this.setting, required this.label});
  final SettingsModel model;
  final String setting;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = model[setting];
    if (s == null) return const SizedBox.shrink();
    return PlayerSettingRow(
      label: label,
      labelWidth: 200,
      note: model.errors[setting],
      child: Align(
        alignment: Alignment.centerRight,
        child: NextToggle(
          value: s.value == true,
          label: label,
          onChanged: (v) => unawaited(model.change(setting, v)),
        ),
      ),
    );
  }
}

/// One of a few of the registry's values, side by side.
class PlayerSettingChoices extends StatelessWidget {
  const PlayerSettingChoices({
    super.key,
    required this.model,
    required this.setting,
    required this.label,
    required this.options,
  });
  final SettingsModel model;
  final String setting;
  final String label;
  final List<(Object, String)> options;

  @override
  Widget build(BuildContext context) {
    final s = model[setting];
    if (s == null) return const SizedBox.shrink();
    // 2 and 2.0 are the same choice.
    final value = options
            .where((o) => o.$1 == s.value || '${o.$1}' == '${s.value}')
            .firstOrNull
            ?.$1 ??
        s.value;
    return PlayerSettingRow(
      label: label,
      note: model.errors[setting],
      child: PlayerMenuChoices<Object?>(
        value: value,
        options: [for (final (v, l) in options) (v, l)],
        onChanged: (v) => unawaited(model.change(setting, v)),
      ),
    );
  }
}

/// Words of the registry: a font's name, typed and kept on Enter or
/// leaving the field.
class PlayerSettingField extends StatelessWidget {
  const PlayerSettingField({
    super.key,
    required this.model,
    required this.setting,
    required this.label,
    this.hint,
  });
  final SettingsModel model;
  final String setting;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final s = model[setting];
    if (s == null) return const SizedBox.shrink();
    return PlayerSettingRow(
      label: label,
      note: model.errors[setting],
      child: Align(
        alignment: Alignment.centerRight,
        child: FieldControl(
          value: '${s.value ?? ''}',
          width: 180,
          hint: hint,
          onCommit: (v) => unawaited(model.change(setting, v.trim())),
        ),
      ),
    );
  }
}

/// A colour of the registry (`#AARRGGBB`): a few to pick, and any typed.
class PlayerSettingColor extends StatelessWidget {
  const PlayerSettingColor({
    super.key,
    required this.model,
    required this.setting,
    required this.label,
    required this.swatches,
  });
  final SettingsModel model;
  final String setting;
  final String label;

  /// `0xAARRGGBB`.
  final List<int> swatches;

  static int? parse(Object? v) {
    if (v is! String) return null;
    final hex = v.replaceFirst('#', '');
    final n = int.tryParse(hex, radix: 16);
    if (n == null) return null;
    if (hex.length == 6) return 0xFF000000 | n;
    if (hex.length == 8) return n;
    return null;
  }

  static String hex(int argb) =>
      '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final s = model[setting];
    if (s == null) return const SizedBox.shrink();
    final current = parse(s.value);
    bool same(int c) =>
        current != null && (c & 0xFFFFFF) == (current & 0xFFFFFF);
    return PlayerSettingRow(
      label: label,
      labelWidth: 64,
      note: model.errors[setting],
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        for (final c in swatches)
          _Swatch(
            color: Color(c),
            on: same(c),
            onTap: () => unawaited(model.change(setting, hex(c))),
          ),
        const SizedBox(width: 8),
        FieldControl(
          value: current == null
              ? '${s.value ?? ''}'
              : hex(current).substring(3),
          width: 76,
          mono: true,
          onCommit: (text) {
            final c = parse(text.trim());
            if (c != null) unawaited(model.change(setting, hex(c)));
          },
        ),
      ]),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.on, required this.onTap});
  final Color color;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        pressScale: 0.9,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
                color: on
                    ? NextColors.paper
                    : hovered
                        ? NextColors.p3
                        : const Color(0x33FFFFFF),
                width: on ? 2 : 1),
          ),
        ),
      );
}

/// Words of the registry each kept apart (blocked words): × takes one
/// away, the field adds one.
class PlayerSettingWords extends StatelessWidget {
  const PlayerSettingWords(
      {super.key, required this.model, required this.setting});
  final SettingsModel model;
  final String setting;

  @override
  Widget build(BuildContext context) {
    final s = model[setting];
    if (s == null) return const SizedBox.shrink();
    final words = [for (final v in (s.value as List?) ?? const []) '$v'];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (words.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
            child: Text('没有屏蔽词',
                style: NextText.sans(12.5, color: NextColors.p3)),
          ),
        ListControl(
          values: words,
          onChanged: (v) => unawaited(model.change(setting, v)),
        ),
        if (model.errors[setting] case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text(error,
                style: NextText.sans(11.5, color: NextColors.accent)),
          ),
      ]),
    );
  }
}

/// A row that does something once: 恢复默认, 保存.
class PlayerSettingAction extends StatelessWidget {
  const PlayerSettingAction(
      {super.key, required this.label, required this.onTap, this.value});
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        pressScale: 0.99,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hovered && onTap != null
                ? const Color(0x14FFFFFF)
                : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Text(label,
                  style: NextText.sans(13.5,
                      color: onTap == null
                          ? NextColors.p4
                          : hovered
                              ? NextColors.paper
                              : NextColors.p2)),
            ),
            if (value case final value?)
              Text(value, style: NextText.sans(12.5, color: NextColors.p3)),
          ]),
        ),
      );
}
