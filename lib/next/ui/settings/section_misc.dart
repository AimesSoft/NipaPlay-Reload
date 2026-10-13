import 'package:flutter/widgets.dart';

import '../data/gui_calls.dart';
import '../data/settings_data.dart';
import '../data/upkeep.dart';
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

/// The room on this computer, caches to clear, and where screenshots go.
class StorageSection extends StatefulWidget {
  const StorageSection({
    super.key,
    required this.upkeep,
    required this.model,
    required this.more,
    required this.onMore,
    this.highlight,
  });
  final NextUpkeep upkeep;
  final SettingsModel model;
  final bool more;
  final VoidCallback onMore;
  final String? highlight;

  @override
  State<StorageSection> createState() => StorageSectionState();
}

class StorageSectionState extends State<StorageSection> {
  UiSpace? _space;
  List<UiCacheKind>? _caches;
  String? _spaceFailed;
  String? _cachesFailed;
  final _clearing = <String>{};
  final _failed = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([
      widget.upkeep.space().then((space) {
        if (!mounted) return;
        setState(() {
          _space = space;
          _spaceFailed = null;
        });
      }, onError: (Object _) {
        if (mounted) setState(() => _spaceFailed = '没能读取');
      }),
      widget.upkeep.caches().then((caches) {
        if (!mounted) return;
        setState(() {
          _caches = caches;
          _cachesFailed = null;
        });
      }, onError: (Object _) {
        if (mounted) setState(() => _cachesFailed = '没能读取');
      }),
    ]);
  }

  /// Clears [id] as its row's 清理 would (debug).
  Future<void> clear(String id) async {
    setState(() {
      _clearing.add(id);
      _failed.remove(id);
    });
    try {
      await widget.upkeep.clear(id);
    } catch (e) {
      if (mounted) setState(() => _failed[id] = callFailure(e));
    }
    await _load();
    if (mounted) setState(() => _clearing.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final caches = _caches;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_space case final space?)
        _SpaceLine(space)
      else if (_spaceFailed case final failed?)
        Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Text(failed, style: NextText.sans(13, color: NextColors.p3)),
        ),
      if (caches != null || _cachesFailed != null)
        SettingsCard(title: '缓存', children: [
          if (caches == null)
            SettingsRow(title: _cachesFailed!, dim: true)
          else
            for (final c in caches)
              SettingsRow(
                title: c.title,
                subtitle: c.kept > 0 ? '保留 ${sizeText(c.kept)}' : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_failed[c.id] case final failed?) ...[
                    Text(failed,
                        style: NextText.sans(12.5, color: NextColors.accent2)),
                    const SizedBox(width: 12),
                  ],
                  Text(c.bytes == 0 ? '空' : sizeText(c.bytes),
                      style: NextText.num(12.5, color: NextColors.p3)),
                  const SizedBox(width: 14),
                  PillButton(
                    label: '清理',
                    busy: _clearing.contains(c.id),
                    onTap: c.bytes == 0 ? null : () => clear(c.id),
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

/// The disk as one thin line: NipaPlay's part, the downloads, what else
/// is there, and the room left.
class _SpaceLine extends StatelessWidget {
  const _SpaceLine(this.space);
  final UiSpace space;

  @override
  Widget build(BuildContext context) {
    final s = space;
    final (free, total) = (s.free, s.total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 30),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (free != null)
          Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(sizeText(free),
                    style: NextText.num(22, weight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text('可用', style: NextText.sans(13, color: NextColors.p3)),
                const Spacer(),
                if (total != null)
                  Text('共 ${sizeText(total)}',
                      style: NextText.num(12.5, color: NextColors.p3)),
              ]),
        if (free != null && total != null && total > 0) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 4,
            child: CustomPaint(
              painter: _SpacePainter(
                total: total,
                parts: [
                  (s.app ?? 0, NextColors.accent),
                  (s.downloads ?? 0, NextColors.accent2),
                  (
                    total - free - (s.app ?? 0) - (s.downloads ?? 0),
                    const Color(0x3DF5F1EA)
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          if (s.app case final app?) _SpacePart(NextColors.accent, 'NipaPlay', app),
          if (s.downloads case final downloads?) ...[
            const SizedBox(width: 22),
            _SpacePart(NextColors.accent2, '下载', downloads),
          ],
        ]),
      ]),
    );
  }
}

class _SpacePart extends StatelessWidget {
  const _SpacePart(this.color, this.label, this.bytes);
  final Color color;
  final String label;
  final int bytes;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        StateDot(color, glow: false),
        const SizedBox(width: 8),
        Text(label, style: NextText.sans(12.5, color: NextColors.p3)),
        const SizedBox(width: 6),
        Text(sizeText(bytes), style: NextText.num(12.5, color: NextColors.p2)),
      ]);
}

class _SpacePainter extends CustomPainter {
  _SpacePainter({required this.total, required this.parts});
  final int total;
  final List<(int, Color)> parts;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(size.height / 2));
    canvas.clipRRect(bar);
    canvas.drawRRect(bar, Paint()..color = const Color(0x14FFFFFF));
    var x = 0.0;
    for (final (bytes, color) in parts) {
      if (bytes <= 0) continue;
      // A part too small to see still shows as a sliver.
      final w = (size.width * bytes / total).clamp(3.0, size.width - x);
      canvas.drawRect(
          Rect.fromLTWH(x, 0, w, size.height), Paint()..color = color);
      x += w + 1.5;
      if (x >= size.width) break;
    }
  }

  @override
  bool shouldRepaint(_SpacePainter old) =>
      old.total != total || old.parts.toString() != parts.toString();
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
      {super.key,
      required this.data,
      required this.upkeep,
      required this.model,
      this.highlight});
  final NextSettingsData data;
  final NextUpkeep upkeep;
  final SettingsModel model;
  final String? highlight;

  @override
  State<AboutSection> createState() => AboutSectionState();
}

class AboutSectionState extends State<AboutSection> {
  UiAbout? _about;
  UiUpdateCheck? _update;
  bool _checking = false;

  /// The check could not be made, or failed.
  bool _failed = false;

  /// The release page did not open.
  String? _note;

  @override
  void initState() {
    super.initState();
    widget.data.about().then((a) {
      if (mounted) setState(() => _about = a);
    });
    widget.upkeep.lastUpdate().then((u) {
      if (mounted && !_checking) setState(() => _update = u);
    }, onError: (Object _) {
      if (mounted && !_checking) setState(() => _failed = true);
    });
  }

  /// Looks for a newer version, as 检查更新 does (debug).
  Future<void> check() async {
    setState(() {
      _checking = true;
      _note = null;
    });
    UiUpdateCheck? update;
    try {
      update = await widget.upkeep.checkUpdate();
    } catch (_) {
      update = null;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _update = update;
      _failed = update == null || update.failed || update.newer == null;
    });
  }

  Future<void> _open() async {
    try {
      await widget.upkeep.openUpdate();
    } catch (e) {
      if (mounted) setState(() => _note = callFailure(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final about = _about;
    final update = _update;
    final newer = !_failed && (update?.newer ?? false);
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
        SettingsRow(
          title: '更新',
          subtitle: _note ??
              (_failed
                  ? '没能检查'
                  : update == null
                      ? null
                      : newer
                          ? '有新版本 ${update.latest ?? ''}'
                          : '已是最新'),
          mark: newer ? const StateDot(NextColors.accent) : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (newer && update!.page) ...[
              PillButton(label: '前往', primary: true, onTap: _open),
              const SizedBox(width: 8),
            ],
            PillButton(label: '检查更新', busy: _checking, onTap: check),
          ]),
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
