import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/settings_data.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/nipa_avatar.dart';
import 'controls.dart';
import 'settings_layout.dart';

/// The registry as the page holds it: read once, changed one setting at a
/// time, each change shown at once and put back if NipaPlay refuses it.
class SettingsModel extends ChangeNotifier {
  SettingsModel(this.data);
  final NextSettingsData data;

  List<UiSetting>? all;
  Object? failed;
  final errors = <String, String>{};
  final saving = <String>{};

  /// Changed here, taking effect after NipaPlay restarts.
  final restart = <String>{};
  bool _disposed = false;

  Future<void> load() async {
    try {
      all = await data.settings();
      failed = null;
    } catch (error) {
      failed = error;
    }
    _notify();
  }

  UiSetting? operator [](String key) =>
      all?.where((s) => s.key == key).firstOrNull;

  void _replace(UiSetting setting) {
    final list = all;
    if (list == null) return;
    final i = list.indexWhere((s) => s.key == setting.key);
    if (i >= 0) list[i] = setting;
  }

  /// What NipaPlay last confirmed for a setting while changes to it are
  /// on their way, and how many are.
  final _settled = <String, UiSetting>{};
  final _inFlight = <String, int>{};

  Future<void> change(String key, Object? value) async {
    final current = this[key];
    if (current == null) return;
    _settled.putIfAbsent(key, () => current);
    _inFlight[key] = (_inFlight[key] ?? 0) + 1;
    _replace(current.copyWith(value: value));
    saving.add(key);
    errors.remove(key);
    _notify();
    try {
      final saved = await data.set(key, value);
      _settled[key] = saved;
      if (_inFlight[key] == 1) _replace(saved);
      if (saved.apply == 'restart_app') restart.add(key);
    } catch (error) {
      if (_inFlight[key] == 1) _replace(_settled[key]!);
      errors[key] = settingFailure(error);
      Timer(const Duration(seconds: 4), () {
        if (errors.remove(key) != null) _notify();
      });
    } finally {
      final left = _inFlight[key]! - 1;
      if (left == 0) {
        _inFlight.remove(key);
        _settled.remove(key);
        saving.remove(key);
      } else {
        _inFlight[key] = left;
      }
      _notify();
    }
  }

  /// Back to NipaPlay's defaults.
  Future<void> reset(List<String> keys) async {
    try {
      await data.reset(keys);
    } catch (error) {
      for (final key in keys) {
        errors[key] = settingFailure(error);
      }
    }
    await load();
  }

  /// Settings Nipa changed last, latest first.
  List<UiSetting> get byNipa => [
        for (final s in all ?? const <UiSetting>[])
          if (s.byNipa && SettingsLayout.shown(s)) s
      ]..sort((a, b) =>
          (b.changedAt ?? DateTime(0)).compareTo(a.changedAt ?? DateTime(0)));

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// “刚刚”, “3 小时前”, “昨天”, “10月2日”.
String whenText(DateTime at, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final d = current.difference(at);
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  final today = DateTime(current.year, current.month, current.day);
  if (!at.isBefore(today)) return '${d.inHours} 小时前';
  if (!at.isBefore(today.subtract(const Duration(days: 1)))) return '昨天';
  return '${at.month}月${at.day}日';
}

/// One registry setting: its name, Nipa's mark when she changed it last,
/// and the control its schema calls for.
class RegistryRow extends StatefulWidget {
  const RegistryRow(
      {super.key,
      required this.setting,
      required this.model,
      this.highlight = false});
  final UiSetting setting;
  final SettingsModel model;
  final bool highlight;

  @override
  State<RegistryRow> createState() => _RegistryRowState();
}

class _RegistryRowState extends State<RegistryRow> {
  bool _note = false;

  @override
  void initState() {
    super.initState();
    // Arriving at it from Nipa's list opens what she said about it.
    _note = widget.highlight && widget.setting.byNipa;
  }

  @override
  void didUpdateWidget(RegistryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.setting.byNipa) _note = false;
    if (widget.highlight && !oldWidget.highlight && widget.setting.byNipa) {
      _note = true;
    }
  }

  void _set(Object? value) => widget.model.change(widget.setting.key, value);

  Widget? _control(UiSetting s) {
    switch (s.kind) {
      case UiSettingKind.toggle:
        return NextToggle(
            value: s.value == true, onChanged: _set, label: s.title);
      case UiSettingKind.choice:
        return ChoiceControl<Object?>(
          value: s.choices
              .firstWhere((c) => '$c' == '${s.value}', orElse: () => s.value),
          options: [
            for (final c in s.choices) (c, s.nameOf(c))
          ],
          onChanged: _set,
        );
      case UiSettingKind.number:
        final value =
            s.value is num ? s.value as num : (s.defaultValue as num? ?? 0);
        final span = s.min != null && s.max != null ? s.max! - s.min! : null;
        if (span != null && span > 0 && (s.step != null || span <= 100)) {
          return SliderControl(
            value: value,
            min: s.min!,
            max: s.max!,
            step: s.step,
            integer: s.integer,
            names: s.names,
            onChanged: _set,
          );
        }
        return FieldControl(
          value: s.integer || value == value.roundToDouble()
              ? '${value.round()}'
              : '$value',
          width: 96,
          numeric: true,
          align: TextAlign.right,
          onCommit: (text) {
            final n = num.tryParse(text.trim());
            if (n == null) return setState(() {});
            _set(s.integer ? n.round() : n);
          },
        );
      case UiSettingKind.text when s.domain == 'shortcuts':
        return KeyRecorder(value: '${s.value ?? ''}', onChanged: _set);
      case UiSettingKind.text:
        return FieldControl(value: '${s.value ?? ''}', onCommit: _set);
      case UiSettingKind.secret:
        return FieldControl(
            value: '', obscure: true, hint: '未更改', onCommit: _set);
      case UiSettingKind.path:
        final value = '${s.value ?? ''}';
        return PathControl(
          value: value,
          onPick: () async {
            final path =
                await widget.model.data.pickPath(directory: s.directory);
            if (path != null) _set(path);
          },
          onClear: value.isEmpty ? null : () => _set(''),
        );
      case UiSettingKind.color:
        return ColorControl(
            value: s.value, choices: s.choices, onChanged: _set);
      case UiSettingKind.list:
        return null;
      case UiSettingKind.other:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.setting;
    final model = widget.model;
    final error = model.errors[s.key];
    final restart = model.restart.contains(s.key);
    final listValue = s.kind == UiSettingKind.list
        ? [for (final v in (s.value as List?) ?? const []) '$v']
        : null;
    return SettingsRow(
      title: SettingWords.title(s),
      subtitle: error ?? (restart ? '重新打开 NipaPlay 后生效' : null),
      highlight: widget.highlight,
      mark: s.byNipa
          ? NipaMark(open: _note, onTap: () => setState(() => _note = !_note))
          : null,
      trailing: _control(s),
      below: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (listValue != null)
              ListControl(values: listValue, onChanged: (v) => _set(v)),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: NextMotion.ease,
              alignment: Alignment.topCenter,
              child: _note && s.byNipa
                  ? NipaNote(
                      setting: s,
                      onRevert: s.previousValue == null
                          ? null
                          : () => _set(s.previousValue),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ]),
    );
  }
}

/// Nipa changed this: her face, small, after the name.
class NipaMark extends StatelessWidget {
  const NipaMark({super.key, required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: '梨花改过',
        pressScale: 0.9,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: open || hovered
                    ? const Color(0xCCFF2E55)
                    : const Color(0x00FF2E55),
                width: 1.2),
          ),
          child: const NipaAvatar(size: 16),
        ),
      );
}

/// What Nipa said when she changed it, and the way back.
class NipaNote extends StatelessWidget {
  const NipaNote({super.key, required this.setting, this.onRevert});
  final UiSetting setting;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    final at = setting.changedAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const NipaAvatar(size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(at == null ? '梨花' : '梨花 · ${whenText(at)}',
                    style: NextText.sans(12, color: NextColors.p3)),
                if (setting.reason case final reason?
                    when reason.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(reason,
                        style: NextText.sans(13.5,
                            color: NextColors.p2, height: 1.55)),
                  ),
              ],
            ),
          ),
          if (onRevert != null) ...[
            const SizedBox(width: 12),
            PillButton(label: '改回', onTap: onRevert),
          ],
        ]),
      ),
    );
  }
}

/// A section's registry settings: its groups, the folded ones behind
/// “更多”.
class RegistryGroups extends StatelessWidget {
  const RegistryGroups({
    super.key,
    required this.section,
    required this.model,
    required this.more,
    required this.onMore,
    this.highlight,
    this.skipFolded = false,
    this.extra = const {},
  });
  final SettingsSection section;
  final SettingsModel model;
  final bool more;
  final VoidCallback onMore;
  final String? highlight;
  final bool skipFolded;

  /// The page's own rows after a group's settings, by the group's title.
  final Map<String, List<Widget>> extra;

  @override
  Widget build(BuildContext context) {
    final all = model.all;
    if (all == null) return const SizedBox.shrink();
    final groups = SettingsLayout.arrange(section, all);
    final open = [
      for (final g in groups)
        if (!g.$1.folded) g
    ];
    final folded = [
      for (final g in groups)
        if (g.$1.folded) g
    ];
    // Arriving at a folded setting unfolds them.
    final showFolded =
        more || folded.any((g) => g.$2.any((s) => s.key == highlight));
    Widget card((SettingsGroup, List<UiSetting>) g) => SettingsCard(
          title: g.$1.title,
          children: [
            for (final s in g.$2)
              RegistryRow(
                  key: ValueKey(s.key),
                  setting: s,
                  model: model,
                  highlight: s.key == highlight),
            ...?extra[g.$1.title],
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in open) card(g),
        if (folded.isNotEmpty && !skipFolded) ...[
          FoldButton(open: showFolded, onTap: onMore),
          if (showFolded)
            for (final g in folded) card(g),
        ],
      ],
    );
  }
}
