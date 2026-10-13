import 'package:flutter/widgets.dart';

import '../data/settings_data.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/nipa_avatar.dart';
import 'controls.dart';
import 'registry_rows.dart';
import 'settings_layout.dart';

/// “1.2 GB”, “340 MB”.
String sizeText(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '$bytes B'
      : '${value >= 100 ? value.round() : value.toStringAsFixed(1)} ${units[unit]}';
}

/// Caches to clear, and where screenshots go.
class StorageSection extends StatefulWidget {
  const StorageSection({
    super.key,
    required this.data,
    required this.model,
    required this.more,
    required this.onMore,
    this.highlight,
  });
  final NextSettingsData data;
  final SettingsModel model;
  final bool more;
  final VoidCallback onMore;
  final String? highlight;

  @override
  State<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<StorageSection> {
  UiStorage? _storage;
  final _clearing = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = await widget.data.storage();
    if (mounted) setState(() => _storage = storage);
  }

  Future<void> _clear(String id) async {
    setState(() => _clearing.add(id));
    try {
      await widget.data.clearCache(id);
    } catch (_) {}
    await _load();
    if (mounted) setState(() => _clearing.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final storage = _storage;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (storage != null && storage.available && storage.caches.isNotEmpty)
        SettingsCard(title: '缓存', children: [
          for (final c in storage.caches)
            SettingsRow(
              title: c.title,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (c.bytes != null)
                  Text(c.bytes == 0 ? '空' : sizeText(c.bytes!),
                      style: NextText.num(12.5, color: NextColors.p3)),
                const SizedBox(width: 14),
                PillButton(
                  label: '清理',
                  busy: _clearing.contains(c.id),
                  onTap: c.bytes == 0 ? null : () => _clear(c.id),
                ),
              ]),
            ),
        ]),
      RegistryGroups(
        section: SettingsSection.storage,
        model: widget.model,
        more: widget.more,
        onMore: widget.onMore,
        highlight: widget.highlight,
      ),
    ]);
  }
}

/// The interface's own keys, and the player's, each one changeable.
class ShortcutsSection extends StatelessWidget {
  const ShortcutsSection({super.key, required this.model, this.highlight});
  final SettingsModel model;
  final String? highlight;

  static const own = [
    ('问 Nipa', '⌘ K'),
    ('设置', '⌘ ,'),
    ('返回', 'Esc'),
  ];

  @override
  Widget build(BuildContext context) {
    final player = [
      for (final s in model.all ?? const <UiSetting>[])
        if (s.domain == 'shortcuts' && SettingsLayout.shown(s)) s.key
    ];
    final changed = player.where((k) => !(model[k]?.isDefault ?? true));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsCard(title: '界面', children: [
        for (final (title, keys) in own)
          SettingsRow(title: title, trailing: KeyHint(keys)),
      ]),
      RegistryGroups(
        section: SettingsSection.shortcuts,
        model: model,
        more: false,
        onMore: () {},
        highlight: highlight,
      ),
      if (changed.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: PillButton(
              label: '恢复默认', onTap: () => model.reset(changed.toList())),
        ),
    ]);
  }
}

/// The version, newer ones, and how NipaPlay looks for them.
class AboutSection extends StatefulWidget {
  const AboutSection(
      {super.key, required this.data, required this.model, this.highlight});
  final NextSettingsData data;
  final SettingsModel model;
  final String? highlight;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  UiAbout? _about;
  UiUpdate? _update;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    widget.data.about().then((a) {
      if (mounted) setState(() => _about = a);
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final update = await widget.data.checkUpdate();
    if (mounted) {
      setState(() {
        _checking = false;
        _update = update;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final about = _about;
    final update = _update;
    final auto = widget.model['general.autoCheckUpdates'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Row(children: [
          const NipaAvatar(size: 56),
          const SizedBox(width: 18),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NipaPlay', style: NextText.serif(26, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(about?.version ?? '',
                style: NextText.num(13, color: NextColors.p3)),
          ]),
        ]),
      ),
      SettingsCard(children: [
        if (about?.updates ?? false)
          SettingsRow(
            title: '更新',
            subtitle: update == null
                ? null
                : update.newer
                    ? '有新版本 ${update.latest ?? ''}'
                    : '已是最新',
            trailing: PillButton(label: '检查更新', busy: _checking, onTap: _check),
          ),
        if (auto != null && SettingsLayout.shown(auto))
          RegistryRow(
              setting: auto,
              model: widget.model,
              highlight: widget.highlight == auto.key),
      ]),
    ]);
  }
}

/// Back to the classic interface, and the settings only it uses.
class ClassicSection extends StatelessWidget {
  const ClassicSection({
    super.key,
    required this.model,
    required this.onLeave,
    required this.more,
    required this.onMore,
    this.highlight,
  });
  final SettingsModel model;
  final VoidCallback onLeave;
  final bool more;
  final VoidCallback onMore;
  final String? highlight;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SettingsCard(children: [
          SettingsRow(
            title: '经典界面',
            trailing:
                PillButton(label: '回到经典界面', primary: true, onTap: onLeave),
          ),
        ]),
        RegistryGroups(
          section: SettingsSection.classic,
          model: model,
          more: more,
          onMore: onMore,
          highlight: highlight,
        ),
      ]);
}
