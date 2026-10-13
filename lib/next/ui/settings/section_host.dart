import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/host_settings.dart';
import '../data/settings_data.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/segmented.dart';
import 'controls.dart';
import 'registry_rows.dart';
import 'section_accounts.dart';
import 'settings_layout.dart';

/// This device in the mesh: whether it is in, what it is called, the other
/// devices, and whether they may run programs here. Only the person at
/// this device changes these.
class DevicesSection extends StatefulWidget {
  const DevicesSection({super.key, required this.host});
  final NextHostSettings host;

  @override
  State<DevicesSection> createState() => DevicesSectionState();
}

class DevicesSectionState extends State<DevicesSection> {
  UiMeshSetup? _mesh;
  bool? _programs;
  bool _advanced = false;
  bool _saving = false;
  String? _error;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = widget.host.changes.listen((_) => _load());
  }

  @override
  void didUpdateWidget(DevicesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host, widget.host)) _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final (mesh, programs) =
        await (widget.host.mesh(), widget.host.remotePrograms()).wait;
    if (mounted) {
      setState(() {
        _mesh = mesh;
        _programs = programs;
      });
    }
  }

  void debugAdvanced(bool open) => setState(() => _advanced = open);

  UiMeshChoice _choice(UiMeshSetup m,
          {bool? joined,
          String? name,
          String? coordinator,
          int? port,
          bool? loopbackOnly,
          bool? broadcastDiscovery,
          List<String>? addresses,
          int? fileProxyPort,
          bool clearFileProxyPort = false}) =>
      UiMeshChoice(
        joined: joined ?? m.joined,
        name: name ?? m.name,
        coordinator: coordinator ?? m.coordinator,
        port: port ?? m.port,
        loopbackOnly: loopbackOnly ?? m.loopbackOnly,
        broadcastDiscovery: broadcastDiscovery ?? m.broadcastDiscovery,
        addresses: addresses ?? m.addresses,
        fileProxyPort:
            clearFileProxyPort ? null : fileProxyPort ?? m.fileProxyPort,
      );

  Future<void> _set(UiMeshChoice choice) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.host.setMesh(choice);
    } catch (_) {
      if (mounted) setState(() => _error = '没能保存');
    }
    if (mounted) setState(() => _saving = false);
    await _load();
  }

  Future<void> _setPrograms(bool allowed) async {
    setState(() => _programs = allowed);
    try {
      await widget.host.setRemotePrograms(allowed);
    } catch (_) {
      if (mounted) setState(() => _error = '没能保存');
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final m = _mesh;
    if (m == null) return const SizedBox(height: 120);
    final usable = m.available && !_saving;
    final others = [
      for (final d in m.devices)
        if (!d.self) d
    ];
    final online = others.where((d) => d.online).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsCard(children: [
        SettingsRow(
          leading: _DeviceTile(on: m.joined),
          title: m.joined ? (m.name ?? '这台设备') : '组网',
          subtitle: _error ??
              (!m.available
                  ? m.problem
                  : m.problem ??
                      (m.joined && others.isNotEmpty
                          ? '$online / ${others.length} 台在线'
                          : null)),
          trailing: NextToggle(
            value: m.joined,
            label: '加入',
            onChanged: usable ? (on) => _set(_choice(m, joined: on)) : null,
          ),
        ),
        if (m.available)
          SettingsRow(
            title: '本机名',
            trailing: FieldControl(
              value: m.name ?? '',
              width: 200,
              onCommit: (v) => _set(_choice(m, name: v.trim())),
            ),
          ),
      ]),
      if (m.joined && m.devices.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Wrap(spacing: 14, runSpacing: 14, children: [
            for (final d in m.devices) _DeviceCard(device: d),
          ]),
        ),
      SettingsCard(children: [
        SettingsRow(
          title: '允许别的设备在这里运行程序',
          trailing: NextToggle(
            value: _programs ?? false,
            onChanged: _saving ? null : _setPrograms,
          ),
        ),
      ]),
      if (m.available) ...[
        FoldButton(
            open: _advanced,
            label: '高级',
            onTap: () => setState(() => _advanced = !_advanced)),
        if (_advanced)
          SettingsCard(children: [
            SettingsRow(
              title: '协调地址',
              trailing: FieldControl(
                value: m.coordinator ?? '',
                hint: '自动',
                onCommit: (v) => _set(_choice(m, coordinator: v.trim())),
              ),
            ),
            SettingsRow(
              title: '端口',
              trailing: FieldControl(
                value: m.port == null ? '' : '${m.port}',
                width: 96,
                numeric: true,
                align: TextAlign.right,
                hint: '自动',
                onCommit: (v) => _set(_choice(m, port: int.tryParse(v.trim()))),
              ),
            ),
            SettingsRow(
              title: '只在这台电脑上',
              trailing: NextToggle(
                value: m.loopbackOnly,
                onChanged:
                    usable ? (on) => _set(_choice(m, loopbackOnly: on)) : null,
              ),
            ),
            SettingsRow(
              title: '在局域网里让别的设备发现',
              trailing: NextToggle(
                value: m.broadcastDiscovery,
                onChanged: usable
                    ? (on) => _set(_choice(m, broadcastDiscovery: on))
                    : null,
              ),
            ),
            SettingsRow(
              title: '文件转换端口',
              trailing: FieldControl(
                value: m.fileProxyPort == null ? '' : '${m.fileProxyPort}',
                width: 96,
                numeric: true,
                align: TextAlign.right,
                hint: '自动',
                onCommit: (v) {
                  final port = int.tryParse(v.trim());
                  _set(_choice(m,
                      fileProxyPort: port, clearFileProxyPort: port == null));
                },
              ),
            ),
            SettingsRow(
              title: '其他地址',
              below: ListControl(
                values: m.addresses,
                onChanged: (v) => _set(_choice(m, addresses: v)),
              ),
            ),
          ]),
      ],
    ]);
  }
}

/// A device of the mesh: lit when it is there.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});
  final UiMeshDevice device;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final on = d.online || d.self;
    return Container(
      width: 176,
      height: 128,
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: d.self ? const Color(0x0F5BE3B0) : const Color(0x08FFFFFF),
        border: Border.all(
            color: d.self ? const Color(0x405BE3B0) : NextColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          NextIcon(NextGlyph.device,
              size: 26, color: on ? NextColors.paper : NextColors.p4),
          const Spacer(),
          StateDot(on ? NextColors.mint : NextColors.p4, glow: on),
        ]),
        const Spacer(),
        Text(d.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NextText.sans(14,
                weight: FontWeight.w600,
                color: on ? NextColors.paper : NextColors.p3)),
        const SizedBox(height: 3),
        Text(
            [
              ...d.roles,
              if (d.remotePrograms) '可运行程序',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NextText.sans(11.5, color: NextColors.p3)),
      ]),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? const Color(0x295BE3B0) : const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(9),
        ),
        child: NextIcon(NextGlyph.device,
            size: 18, color: on ? NextColors.mint : NextColors.p3),
      );
}

/// Nipa: what she thinks with, what she remembers, what she changed.
class NipaSection extends StatefulWidget {
  const NipaSection({
    super.key,
    required this.data,
    required this.model,
    required this.onShow,
    required this.more,
    required this.onMore,
    this.highlight,
  });
  final NextSettingsData data;
  final SettingsModel model;

  /// Go to a setting where it lives.
  final void Function(String key) onShow;
  final bool more;
  final VoidCallback onMore;
  final String? highlight;

  @override
  State<NipaSection> createState() => NipaSectionState();
}

class NipaSectionState extends State<NipaSection> {
  UiModelSetup? _setup;
  List<UiMemoryFile>? _files;
  String? _open;

  // The form for a provider set up here.
  String _provider = '', _url = '', _modelName = '', _key = '';
  bool _dirty = false, _saving = false, _checking = false;
  UiModelCheck? _check;
  String? _error;
  StreamSubscription<void>? _changes, _hostChanges;

  NextHostSettings get _host => widget.data.host;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = widget.data.changes.listen((_) => _loadMemory());
    _hostChanges = _host.changes.listen((_) => _loadModel());
  }

  @override
  void dispose() {
    _changes?.cancel();
    _hostChanges?.cancel();
    super.dispose();
  }

  void _load() {
    _loadModel();
    _loadMemory();
  }

  Future<void> _loadModel() async {
    final setup = await _host.model();
    if (!mounted) return;
    setState(() {
      _setup = setup;
      if (!_dirty) {
        _provider = setup.provider ?? '';
        _url = setup.baseUrl ?? '';
        _modelName = setup.model ?? '';
        _key = '';
      }
    });
  }

  Future<void> _loadMemory() async {
    try {
      final files = await widget.data.memories();
      if (mounted) setState(() => _files = files);
    } catch (_) {
      if (mounted) setState(() => _files = const []);
    }
  }

  /// Opens a memory note (debug and Nipa's links).
  void debugOpenMemory(String? path) => setState(() => _open = path);
  Future<void> debugCheck() => _test();

  Future<void> _setSource(UiModelSource source) async {
    setState(() {
      _error = null;
      _check = null;
    });
    try {
      await _host.setModel(UiModelChoice(
        source: source,
        provider: _provider.trim().isEmpty ? null : _provider.trim(),
        baseUrl: _url.trim().isEmpty ? null : _url.trim(),
        model: _modelName.trim().isEmpty ? null : _modelName.trim(),
      ));
    } catch (_) {
      if (mounted) setState(() => _error = '没能保存');
    }
    await _loadModel();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _check = null;
    });
    try {
      await _host.setModel(UiModelChoice(
        source: UiModelSource.nipaplay,
        provider: _provider.trim(),
        baseUrl: _url.trim(),
        model: _modelName.trim(),
        apiKey: _key.isEmpty ? null : _key,
      ));
      _dirty = false;
    } catch (_) {
      if (mounted) setState(() => _error = '没能保存');
    }
    if (mounted) setState(() => _saving = false);
    await _loadModel();
  }

  Future<void> _test() async {
    setState(() {
      _checking = true;
      _check = null;
    });
    final r = await _host.checkModel();
    if (mounted) {
      setState(() {
        _checking = false;
        _check = r;
      });
    }
  }

  void _edit(void Function() change) => setState(() {
        change();
        _dirty = true;
        _check = null;
      });

  Widget _modelCard(UiModelSetup s) {
    final here = s.source == UiModelSource.nipaplay;
    final status =
        _error ?? s.problem ?? (s.inUse == null ? null : '正在用 ${s.inUse}');
    Widget field(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(
                width: 64,
                child: Text(label,
                    style: NextText.sans(12.5, color: NextColors.p3))),
            child,
          ]),
        );
    return SettingsCard(title: '模型', children: [
      SettingsRow(
        leading: const NipaAvatar(size: 32),
        title: here ? (s.provider ?? '在这里设置') : 'Codex',
        subtitle: status,
        trailing: Segmented<UiModelSource>(
          value: s.source,
          options: [
            (
              UiModelSource.codex,
              '这台电脑的 Codex',
              (c) => Text('这台电脑的 Codex', style: NextText.sans(12.5, color: c))
            ),
            (
              UiModelSource.nipaplay,
              '在这里设置',
              (c) => Text('在这里设置', style: NextText.sans(12.5, color: c))
            ),
          ],
          onChanged: _setSource,
        ),
        below:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!here && !s.codexAvailable && s.problem == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 0, 18, 6),
              child: Text('这台电脑上没有 Codex',
                  style: NextText.sans(12.5, color: NextColors.p3)),
            ),
          if (here)
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 2, 18, 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    field(
                        '提供方',
                        LiveTextField(
                            value: _provider,
                            hint: 'OpenAI、DeepSeek…',
                            width: 300,
                            onChanged: (v) => _edit(() => _provider = v))),
                    field(
                        '地址',
                        LiveTextField(
                            value: _url,
                            hint: 'https://',
                            width: 300,
                            onChanged: (v) => _edit(() => _url = v))),
                    field(
                        '模型',
                        LiveTextField(
                            value: _modelName,
                            width: 300,
                            onChanged: (v) => _edit(() => _modelName = v))),
                    field(
                        'API key',
                        LiveTextField(
                            value: _key,
                            obscure: true,
                            hint: s.hasKey ? '已保存' : null,
                            width: 300,
                            onChanged: (v) => _edit(() => _key = v))),
                  ]),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(here ? 64 : 18, 4, 18, 16),
            child: Row(children: [
              if (here && _dirty) ...[
                PillButton(
                    label: '保存', primary: true, busy: _saving, onTap: _save),
                const SizedBox(width: 8),
              ],
              PillButton(
                  label: '测试连接', busy: _checking, onTap: _dirty ? null : _test),
              if (_check case final check?) ...[
                const SizedBox(width: 12),
                StateDot(check.ok ? NextColors.mint : NextColors.accent),
                const SizedBox(width: 8),
                Text(
                    check.ok
                        ? (check.latency == null
                            ? '可以用'
                            : '可以用 · ${check.latency!.inMilliseconds} ms')
                        : check.message ?? '不能用',
                    style: NextText.sans(12.5,
                        color: check.ok ? NextColors.p2 : NextColors.accent2)),
              ],
            ]),
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final setup = _setup;
    final files = _files;
    final changed = widget.model.byNipa;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (setup != null) _modelCard(setup),
      if (files != null)
        SettingsCard(title: 'Nipa 记得的事', children: [
          if (files.isEmpty) const SettingsRow(title: '还没有记下什么', dim: true),
          for (final f in files)
            SettingsRow(
              title: f.name,
              trailing: AnimatedRotation(
                turns: _open == f.path ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                curve: NextMotion.ease,
                child: const NextIcon(NextGlyph.chevronRight,
                    size: 14, color: NextColors.p3),
              ),
              onTap: () =>
                  setState(() => _open = _open == f.path ? null : f.path),
              below: _open == f.path
                  ? _MemoryEditor(
                      key: ValueKey(f.path),
                      data: widget.data,
                      path: f.path,
                      onGone: () {
                        setState(() => _open = null);
                        _loadMemory();
                      },
                    )
                  : null,
            ),
        ]),
      if (changed.isNotEmpty)
        SettingsCard(title: 'Nipa 改过的设置', children: [
          for (final s in changed)
            SettingsRow(
              title: SettingWords.title(s),
              subtitle: s.reason,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(SettingsLayout.sectionOf(s.key).title,
                    style: NextText.sans(12.5, color: NextColors.p3)),
                const SizedBox(width: 8),
                const NextIcon(NextGlyph.chevronRight,
                    size: 14, color: NextColors.p3),
              ]),
              onTap: () => widget.onShow(s.key),
            ),
        ]),
      RegistryGroups(
        section: SettingsSection.nipa,
        model: widget.model,
        more: widget.more,
        onMore: widget.onMore,
        highlight: widget.highlight,
      ),
    ]);
  }
}

/// A memory note as it is written: change it and save, or forget it.
class _MemoryEditor extends StatefulWidget {
  const _MemoryEditor(
      {super.key,
      required this.data,
      required this.path,
      required this.onGone});
  final NextSettingsData data;
  final String path;
  final VoidCallback onGone;

  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  UiMemoryDoc? _doc;
  String _text = '';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final doc = await widget.data.memory(widget.path);
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _text = doc.content;
    });
  }

  Future<void> _save() async {
    final doc = _doc;
    if (doc == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.data.editMemory(doc, _text);
      await _read();
    } catch (error) {
      if (mounted) setState(() => _error = settingFailure(error));
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _forget() async {
    final doc = _doc;
    if (doc == null) return;
    try {
      await widget.data.forgetMemory(doc);
      widget.onGone();
    } catch (error) {
      if (mounted) setState(() => _error = settingFailure(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc == null) return const SizedBox(height: 80);
    final changed = _text != doc.content;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LiveTextField(
          value: doc.content,
          width: null,
          lines: 6,
          onChanged: (v) => setState(() => _text = v),
        ),
        const SizedBox(height: 10),
        Row(children: [
          if (changed)
            PillButton(label: '保存', primary: true, busy: _saving, onTap: _save),
          if (_error != null) ...[
            const SizedBox(width: 12),
            Text(_error!,
                style: NextText.sans(12.5, color: NextColors.accent2)),
          ],
          const Spacer(),
          ConfirmPill(label: '忘掉', confirm: '确定忘掉', onConfirm: _forget),
        ]),
      ]),
    );
  }
}
