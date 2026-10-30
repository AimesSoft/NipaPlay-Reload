import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../ui_data/host_settings.dart';
import '../data/gui_calls.dart' show callFailure, rawFailureText;
import '../data/settings_data.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/progress.dart';
import '../widgets/segmented.dart';
import 'controls.dart';
import 'dsh_config_card.dart';
import '../../settings/reasoning_effort.dart';
import 'registry_rows.dart';
import 'section_accounts.dart';
import 'settings_layout.dart';

/// This device in the mesh: whether it is in, what it is called, the other
/// devices, and whether they may run programs here; Classic's remote
/// access and the devices it trusts. Only the person at this device
/// changes these.
class DevicesSection extends StatefulWidget {
  const DevicesSection({super.key, required this.host});
  final NextHostSettings host;

  @override
  State<DevicesSection> createState() => DevicesSectionState();
}

class DevicesSectionState extends State<DevicesSection> {
  UiMeshSetup? _mesh;
  bool? _programs;
  bool _saving = false;
  String? _error;
  StreamSubscription<void>? _changes;
  int _loadRevision = 0;
  final _loadErrors = <String, String>{};

  /// Null on a host without Classic's remote access.
  UiRemoteAccess? _remote;
  bool _remoteSaving = false;
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = widget.host.changes.listen((_) => _load());
  }

  @override
  void didUpdateWidget(DevicesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host, widget.host)) {
      _changes?.cancel();
      _changes = widget.host.changes.listen((_) => _load());
      _mesh = null;
      _programs = null;
      _remote = null;
      _loadErrors.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    final host = widget.host;
    Future<void> read<T>(
        String label, Future<T> Function() load, void Function(T) save) async {
      try {
        final value = await load();
        if (!mounted || revision != _loadRevision) return;
        setState(() {
          save(value);
          _loadErrors.remove(label);
        });
      } catch (error) {
        if (mounted && revision == _loadRevision) {
          setState(() => _loadErrors[label] = rawFailureText(error));
        }
      }
    }

    await Future.wait([
      read('组网', host.mesh, (value) => _mesh = value),
      read('程序权限', host.remotePrograms, (value) => _programs = value),
      read('远程访问', () => _remoteAccess(host), (value) => _remote = value),
    ]);
  }

  Future<UiRemoteAccess?> _remoteAccess(NextHostSettings host) async {
    try {
      return await host.deviceSettings.remoteAccess();
    } on UnsupportedError {
      return null;
    }
  }

  /// Remote access as chosen here, shown at once; the host's answer
  /// replaces it.
  Future<void> _setRemote(UiRemoteAccess r,
      {bool? running,
      bool? autoStart,
      int? port,
      bool? ipv6,
      bool? receiverEnabled}) async {
    final choice = UiRemoteAccessChoice(
      running: running ?? r.running,
      autoStart: autoStart ?? r.autoStart,
      port: port ?? r.port,
      ipv6: ipv6 ?? r.ipv6,
      receiverEnabled: receiverEnabled ?? r.receiverEnabled,
    );
    setState(() {
      _remoteSaving = true;
      _remoteError = null;
      _remote = UiRemoteAccess(
          running: choice.running,
          autoStart: choice.autoStart,
          port: choice.port,
          ipv6: choice.ipv6,
          receiverEnabled: choice.receiverEnabled,
          devices: r.devices);
    });
    try {
      await widget.host.deviceSettings.setRemoteAccess(choice);
    } catch (e) {
      if (mounted) setState(() => _remoteError = callFailure(e));
    }
    if (mounted) setState(() => _remoteSaving = false);
    await _load();
  }

  Future<void> _forget(UiRemoteDevice d) async {
    setState(() => _remoteError = null);
    try {
      await widget.host.deviceSettings.forgetRemoteDevice(d.clientKey);
    } catch (e) {
      if (mounted) setState(() => _remoteError = callFailure(e));
    }
    await _load();
  }

  List<Widget> _remoteCards(UiRemoteAccess r) => [
        SettingsCard(children: [
          SettingsRow(
            title: '远程访问',
            mark: r.problem == null && _remoteError == null
                ? null
                : const StateDot(NextColors.accent2),
            subtitle: r.problem ?? _remoteError,
            trailing: NextToggle(
              value: r.running,
              label: '远程访问',
              onChanged:
                  _remoteSaving ? null : (on) => _setRemote(r, running: on),
            ),
          ),
        ]),
        if (r.devices.isNotEmpty)
          SettingsCard(title: '信任的设备', children: [
            for (final d in r.devices)
              SettingsRow(
                key: ValueKey(d.clientKey),
                title: d.name,
                trailing: ConfirmPill(
                    label: '移除', confirm: '确定移除', onConfirm: () => _forget(d)),
              ),
          ]),
      ];

  Widget _remoteMore(UiRemoteAccess r) =>
      SettingsCard(title: '远程访问', children: [
        SettingsRow(
          title: '随 NipaPlay 启动',
          trailing: NextToggle(
            value: r.autoStart,
            onChanged:
                _remoteSaving ? null : (on) => _setRemote(r, autoStart: on),
          ),
        ),
        SettingsRow(
          title: '端口',
          trailing: FieldControl(
            value: '${r.port}',
            width: 96,
            numeric: true,
            align: TextAlign.right,
            onCommit: (v) {
              final port = int.tryParse(v.trim());
              if (port == null) return setState(() {});
              _setRemote(r, port: port);
            },
          ),
        ),
        SettingsRow(
          title: 'IPv6',
          trailing: NextToggle(
            value: r.ipv6,
            onChanged: _remoteSaving ? null : (on) => _setRemote(r, ipv6: on),
          ),
        ),
        SettingsRow(
          title: '接受遥控',
          trailing: NextToggle(
            value: r.receiverEnabled,
            onChanged: _remoteSaving
                ? null
                : (on) => _setRemote(r, receiverEnabled: on),
          ),
        ),
      ]);

  // Kept for older debug clients; device settings are always visible.
  void debugAdvanced(bool open) {}

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

  /// Takes a device out of the account's devices; it loses access at once.
  Future<void> _remove(UiMeshDevice d) async {
    setState(() => _error = null);
    try {
      await widget.host.removeMeshDevice(d.id);
    } catch (_) {
      if (mounted) setState(() => _error = '没能移除');
    }
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
    final remote = _remote;
    final usable = m != null && m.available && !_saving;
    final others = [
      for (final d in m?.devices ?? const <UiMeshDevice>[])
        if (!d.self) d
    ];
    final online = others.where((d) => d.online).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final error in _loadErrors.entries)
        SettingsCard(children: [
          SettingsRow(title: '${error.key}读取失败', subtitle: error.value),
        ]),
      if (m == null && !_loadErrors.containsKey('组网'))
        const SettingsCard(children: [
          SettingsRow(title: '正在读取设备信息…'),
        ]),
      if (m != null) ...[
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
              for (final d in m.devices)
                _DeviceCard(
                    device: d,
                    onRemove: d.self || d.id.isEmpty ? null : () => _remove(d)),
            ]),
          ),
      ],
      SettingsCard(children: [
        SettingsRow(
          title: '允许别的设备在这里运行程序',
          trailing: NextToggle(
            value: _programs ?? false,
            onChanged: _saving || _programs == null ? null : _setPrograms,
          ),
        ),
      ]),
      if (remote != null) ..._remoteCards(remote),
      if (m?.available == true || remote != null) ...[
        if (m != null && m.available)
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
        if (remote != null) _remoteMore(remote),
      ],
    ]);
  }
}

/// A device of the mesh: lit when it is there.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, this.onRemove});
  final UiMeshDevice device;

  /// Null for this device itself: it is not removed from here.
  final VoidCallback? onRemove;

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
          if (onRemove != null) ...[
            ConfirmPill(label: '移除', confirm: '确定移除', onConfirm: onRemove!),
            const SizedBox(width: 10),
          ],
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
  StreamSubscription<void>? _changes, _hostChanges, _memoryChanges;

  /// Reading what Nipa remembers, and whether to read it once more after.
  Future<void>? _reading;
  bool _again = false;

  // The runtime Nipa thinks in: DeepSeek Harness (fetched by NipaPlay) or Codex.
  UiAgentRuntime? _agent;
  UiDshRuntime? _dsh;
  bool _dshDirty = false, _importing = false;
  String _registryMirror = '', _nodeMirror = '';
  String? _dshError;
  UiModelApi _api = UiModelApi.responses;
  String _reasoning = defaultReasoningEffort;
  Map<String, Object?>? _compat;

  // The Codex Nipa runs in: fetched by NipaPlay, or one already here.
  UiCodexRuntime? _runtime;
  bool _runtimeDirty = false;
  UiCodexSource _runtimeSource = UiCodexSource.managed;
  String _mirror = '', _executable = '';
  String? _runtimeError;

  NextHostSettings get _host => widget.data.host;

  /// Only hosts that fetch Codex themselves have these.
  NextHostRuntimeSettings? get _runtimeHost {
    final host = _host;
    return host is NextHostRuntimeSettings
        ? host as NextHostRuntimeSettings
        : null;
  }

  /// Official addresses and model names, filled in for the viewer; any
  /// address and model can be typed instead. What a vendor's models need on
  /// the wire comes with its template, never from the address.
  static const _templates = [
    _Template('DeepSeek', 'https://api.deepseek.com', 'deepseek-flash',
        UiModelApi.chat, 'high', {
      'supportsStore': false,
      'supportsDeveloperRole': false,
      'maxTokensField': 'max_tokens',
      'requiresReasoningContentOnAssistantMessages': true,
      'thinkingFormat': 'deepseek',
      'supportsStrictMode': true,
    }),
    _Template('智谱', 'https://open.bigmodel.cn/api/paas/v4', 'glm-5.3-flash',
        UiModelApi.chat, 'high', {
      'supportsStore': false,
      'supportsDeveloperRole': false,
      'supportsReasoningEffort': true,
      'maxTokensField': 'max_tokens',
      'thinkingFormat': 'zai',
      'supportsStrictMode': true,
    }),
  ];

  /// Codex speaks only the Responses API.
  static const _responsesTemplates = [
    _Template('DeepSeek', 'https://api.deepseek.com/', 'deepseek-flash',
        UiModelApi.responses, '', {}),
    _Template('智谱', 'https://open.bigmodel.cn/api/v1', 'glm-5.3-flash',
        UiModelApi.responses, '', {}),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _changes = widget.data.changes.listen((_) => _loadMemory());
    _hostChanges = _host.changes.listen((_) => _loadModel());
    _memoryChanges = widget.data.memoryChanges.listen((_) => _loadMemory());
  }

  @override
  void dispose() {
    _changes?.cancel();
    _hostChanges?.cancel();
    _memoryChanges?.cancel();
    super.dispose();
  }

  void _load() {
    _loadModel();
    _loadMemory();
  }

  Future<void> _loadModel() async {
    unawaited(_loadRuntime());
    unawaited(_loadDsh());
    final setup = await _host.model();
    if (!mounted) return;
    setState(() {
      _setup = setup;
      if (!_dirty) {
        _provider = setup.provider ?? '';
        _url = setup.baseUrl ?? '';
        _modelName = setup.model ?? '';
        _api = setup.api;
        _reasoning = setup.reasoning ?? defaultReasoningEffort;
        _compat = setup.compat;
        _key = '';
      }
    });
  }

  /// Which runtime is chosen and what DeepSeek Harness runs on; a host that
  /// fetches neither has no such cards.
  Future<void> _loadDsh() async {
    final host = _runtimeHost;
    if (host == null) return;
    try {
      final (agent, dsh) = await (host.agentRuntime(), host.dshRuntime()).wait;
      if (!mounted) return;
      setState(() {
        _agent = agent;
        _dsh = dsh;
        if (!_dshDirty) {
          _registryMirror = dsh.registryMirror ?? '';
          _nodeMirror = dsh.nodeMirror ?? '';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _dsh = null);
    }
  }

  /// Separate from the model: the runtime may answer late, or not at all on
  /// a host that does not fetch Codex.
  Future<void> _loadRuntime() async {
    final host = _runtimeHost;
    if (host == null) return;
    UiCodexRuntime runtime;
    try {
      runtime = await host.codexRuntime();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _runtime = runtime;
      if (!_runtimeDirty) {
        _runtimeSource = runtime.source;
        _mirror = runtime.mirror ?? '';
        _executable = runtime.executable ?? '';
      }
    });
  }

  /// Runs a runtime operation; progress arrives through the host's changes.
  void _runtimeDo(Future<void> Function(NextHostRuntimeSettings) op) {
    final host = _runtimeHost;
    if (host == null) return;
    setState(() => _runtimeError = null);
    unawaited(op(host).catchError((Object _) {
      if (mounted) setState(() => _runtimeError = '没能完成');
    }).whenComplete(_loadModel));
  }

  Future<void> _saveRuntime() async {
    final host = _runtimeHost;
    if (host == null) return;
    try {
      await host.setCodexRuntime(UiCodexRuntimeChoice(
        source: _runtimeSource,
        executable: _runtimeSource == UiCodexSource.specified
            ? _executable.trim()
            : null,
        mirror: _mirror.trim(),
      ));
      _runtimeDirty = false;
      if (mounted) setState(() => _runtimeError = null);
    } catch (_) {
      if (mounted) setState(() => _runtimeError = '没能保存');
    }
    await _loadModel();
  }

  void _runtimeEdit(void Function() change) => setState(() {
        change();
        _runtimeDirty = true;
      });

  Future<void> _loadMemory() async {
    if (_reading != null) {
      _again = true;
      return;
    }
    _reading = _readMemory();
    await _reading;
    _reading = null;
    if (_again) {
      _again = false;
      await _loadMemory();
    }
  }

  Future<void> _readMemory() async {
    try {
      final files = await widget.data.memories();
      if (mounted) setState(() => _files = files);
    } catch (_) {
      if (mounted) setState(() => _files = const []);
    }
  }

  /// Opens a memory note (debug and Nipa's links).
  void debugOpenMemory(String? path) => setState(() => _open = path);

  /// The notes as listed (debug).
  List<String> get debugMemory => [for (final f in _files ?? []) f.path];
  Future<void> debugCheck() => _test();

  /// 导入 Codex 配置, as the button does (debug).
  Future<void> debugImportCodex() => _importCodex();

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
    var saved = false;
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
        api: _api,
        reasoning: _reasoning,
        compat: _compat ?? const {},
      ));
      _dirty = false;
      saved = true;
    } catch (_) {
      if (mounted) setState(() => _error = '没能保存');
    }
    if (mounted) setState(() => _saving = false);
    await _loadModel();
    if (saved) unawaited(_prepare());
  }

  /// A model is set and the runtime is not there: fetch it, as the person
  /// has said they want Nipa.
  Future<void> _prepare() async {
    final host = _runtimeHost;
    if (host == null) return;
    try {
      final agent = await host.agentRuntime();
      if (agent.kind != UiAgentRuntimeKind.dsh) return;
      final dsh = await host.dshRuntime();
      if (dsh.status == UiDshStatus.notInstalled && !dsh.fixed) {
        _runtimeDo((h) => h.installDsh());
      }
    } catch (_) {}
  }

  Future<void> _importCodex() async {
    setState(() {
      _importing = true;
      _error = null;
      _check = null;
    });
    var imported = false;
    try {
      await _host.importCodexModel();
      _dirty = false;
      imported = true;
    } catch (_) {
      if (mounted) setState(() => _error = '没能导入');
    }
    if (mounted) setState(() => _importing = false);
    await _loadModel();
    if (imported) unawaited(_prepare());
  }

  Future<void> _setAgent(UiAgentRuntimeKind kind) async {
    final host = _runtimeHost;
    if (host == null) return;
    setState(() => _dshError = null);
    try {
      await host.setAgentRuntime(kind);
      _dirty = false;
    } catch (_) {
      if (mounted) setState(() => _dshError = '没能切换');
    }
    await _loadModel();
  }

  Future<void> _saveDsh() async {
    final host = _runtimeHost;
    if (host == null) return;
    try {
      await host.setDshMirrors(
          registry: _registryMirror.trim(), node: _nodeMirror.trim());
      _dshDirty = false;
      if (mounted) setState(() => _dshError = null);
    } catch (_) {
      if (mounted) setState(() => _dshError = '没能保存');
    }
    await _loadModel();
  }

  void _dshEdit(void Function() change) => setState(() {
        change();
        _dshDirty = true;
      });

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

  Widget _field(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(
              width: 64,
              child: Text(label,
                  style: NextText.sans(12.5, color: NextColors.p3))),
          child,
        ]),
      );

  Widget _modelCard(UiModelSetup s) {
    final dsh = s.runtime == UiAgentRuntimeKind.dsh;
    final here = dsh || s.source == UiModelSource.nipaplay;
    final status =
        _error ?? s.problem ?? (s.inUse == null ? null : '正在用 ${s.inUse}');
    final templates = dsh ? _templates : _responsesTemplates;
    return SettingsCard(title: '模型', children: [
      SettingsRow(
        leading: const NipaAvatar(size: 32),
        title: here ? (s.provider ?? (dsh ? '设置模型' : '在这里设置')) : '已有配置',
        subtitle: status,
        trailing: dsh
            ? (s.codexAvailable
                ? PillButton(
                    label: '导入 Codex 配置', busy: _importing, onTap: _importCodex)
                : null)
            : Segmented<UiModelSource>(
                value: s.source,
                options: [
                  (
                    UiModelSource.nipaplay,
                    '在这里设置',
                    (c) => Text('在这里设置', style: NextText.sans(12.5, color: c))
                  ),
                  (
                    UiModelSource.codex,
                    '已有配置',
                    (c) => Text('已有配置', style: NextText.sans(12.5, color: c))
                  ),
                ],
                onChanged: _setSource,
              ),
        below:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!here && !s.codexAvailable && s.problem == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 0, 18, 6),
              child: Text('这台电脑上没有 Codex 配置',
                  style: NextText.sans(12.5, color: NextColors.p3)),
            ),
          if (here)
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 2, 18, 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _field(
                        '',
                        Wrap(spacing: 6, children: [
                          for (final t in templates)
                            PillButton(
                                label: t.name,
                                onTap: () => _edit(() {
                                      _provider = t.name;
                                      _url = t.baseUrl;
                                      _modelName = t.model;
                                      _api = t.api;
                                      _reasoning = t.reasoning;
                                      _compat = t.compat;
                                    })),
                        ])),
                    _field(
                        '提供方',
                        LiveTextField(
                            value: _provider,
                            hint: 'DeepSeek、智谱、中转…',
                            width: 300,
                            onChanged: (v) => _edit(() => _provider = v))),
                    _field(
                        '地址',
                        LiveTextField(
                            value: _url,
                            hint: 'https://',
                            width: 300,
                            onChanged: (v) => _edit(() => _url = v))),
                    _field(
                        '模型',
                        LiveTextField(
                            value: _modelName,
                            width: 300,
                            onChanged: (v) => _edit(() => _modelName = v))),
                    _field(
                        'API key',
                        LiveTextField(
                            value: _key,
                            obscure: true,
                            hint: s.hasKey ? '已保存' : null,
                            width: 300,
                            onChanged: (v) => _edit(() => _key = v))),
                    if (dsh) ...[
                      _field(
                          '接口',
                          Segmented<UiModelApi>(
                            value: _api,
                            options: [
                              for (final (v, t) in const [
                                (UiModelApi.responses, 'Responses'),
                                (UiModelApi.chat, 'Chat Completions'),
                              ])
                                (
                                  v,
                                  t,
                                  (c) => Text(t,
                                      style: NextText.sans(12.5, color: c))
                                ),
                            ],
                            onChanged: (v) => _edit(() => _api = v),
                          )),
                      _field(
                          '思考',
                          Segmented<String>(
                            value: _reasoning,
                            options: [
                              for (final (v, t) in const [
                                ('', '关'),
                                ('low', '低'),
                                ('medium', '中'),
                                ('high', '高'),
                              ])
                                (
                                  v,
                                  t,
                                  (c) => Text(t,
                                      style: NextText.sans(12.5, color: c))
                                ),
                            ],
                            onChanged: (v) => _edit(() => _reasoning = v),
                          )),
                    ],
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

  /// Which runtime Nipa thinks in, when the person may choose.
  Widget? _runtimeChoice() {
    final agent = _agent;
    if (agent == null || agent.fixed) return null;
    // Without a Codex of its own the host offers no other runtime.
    if (_runtime == null && agent.kind == UiAgentRuntimeKind.dsh) return null;
    return _field(
        '运行器',
        Segmented<UiAgentRuntimeKind>(
          value: agent.kind,
          options: [
            for (final (v, t) in const [
              (UiAgentRuntimeKind.dsh, 'DeepSeek Harness'),
              (UiAgentRuntimeKind.codex, 'Codex'),
            ])
              (v, t, (c) => Text(t, style: NextText.sans(12.5, color: c))),
          ],
          onChanged: _setAgent,
        ));
  }

  Widget _dshCard(UiDshRuntime r) {
    final total = r.totalBytes;
    final String? subtitle = _dshError ??
        switch (r.status) {
          UiDshStatus.notInstalled => total == null ? null : _size(total),
          UiDshStatus.downloading => total == null
              ? _size(r.receivedBytes)
              : '${_size(r.receivedBytes)} / ${_size(total)}',
          UiDshStatus.unpacking => null,
          UiDshStatus.ready => r.version,
          UiDshStatus.failed => r.problem,
          UiDshStatus.unsupported => null,
        };
    final title = r.fixed
        ? '使用指定的运行环境'
        : switch (r.status) {
            UiDshStatus.notInstalled => '未下载',
            UiDshStatus.downloading => '下载中',
            UiDshStatus.unpacking => '正在安装',
            UiDshStatus.ready => '已就绪',
            UiDshStatus.failed => '没能下载',
            UiDshStatus.unsupported => '这个平台暂时没有',
          };
    final Widget? action = r.fixed
        ? null
        : switch (r.status) {
            UiDshStatus.notInstalled => PillButton(
                label: '下载',
                primary: true,
                onTap: () => _runtimeDo((h) => h.installDsh())),
            UiDshStatus.downloading => PillButton(
                label: '取消',
                onTap: () => _runtimeDo((h) => h.cancelDshInstall())),
            UiDshStatus.failed => PillButton(
                label: '重试',
                primary: true,
                onTap: () => _runtimeDo((h) => h.installDsh())),
            _ => null,
          };
    final choice = _runtimeChoice();
    return SettingsCard(title: '运行环境', children: [
      SettingsRow(
        title: title,
        subtitle: subtitle,
        mark: !r.fixed && r.status == UiDshStatus.ready
            ? const StateDot(NextColors.mint)
            : r.status == UiDshStatus.failed
                ? const StateDot(NextColors.accent2)
                : null,
        trailing: action,
        below: r.status == UiDshStatus.downloading && total != null
            ? Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: ThinBar(
                    progress: r.receivedBytes / total, live: true, height: 3),
              )
            : null,
      ),
      if (choice != null || !r.fixed)
        SettingsRow(
          title: '运行环境选项',
          below: Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (choice != null) choice,
              if (!r.fixed) ...[
                _field(
                    'npm',
                    LiveTextField(
                        value: _registryMirror,
                        hint: 'registry.npmjs.org',
                        width: 300,
                        mono: true,
                        onChanged: (v) => _dshEdit(() => _registryMirror = v))),
                _field(
                    'Node',
                    LiveTextField(
                        value: _nodeMirror,
                        hint: 'nodejs.org/dist',
                        width: 300,
                        mono: true,
                        onChanged: (v) => _dshEdit(() => _nodeMirror = v))),
              ],
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_dshDirty)
                  PillButton(label: '保存', primary: true, onTap: _saveDsh),
                if (!r.fixed && r.status == UiDshStatus.ready)
                  PillButton(
                      label: '移除',
                      danger: true,
                      onTap: () => _runtimeDo((h) => h.removeDsh())),
              ]),
            ]),
          ),
        ),
    ]);
  }

  static String _size(int bytes) => bytes >= 1 << 30
      ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
      : '${(bytes / (1 << 20)).toStringAsFixed(bytes >= 100 << 20 ? 0 : 1)} MB';

  Widget _runtimeCard(UiCodexRuntime r) {
    final managed = r.source == UiCodexSource.managed;
    final total = r.totalBytes;
    final String? subtitle = !managed
        ? (r.executable ?? '系统里的 Codex')
        : switch (r.status) {
            UiCodexStatus.notInstalled => total == null ? null : _size(total),
            UiCodexStatus.downloading => total == null
                ? _size(r.receivedBytes)
                : '${_size(r.receivedBytes)} / ${_size(total)}',
            UiCodexStatus.verifying => null,
            UiCodexStatus.ready => r.version,
            UiCodexStatus.failed => r.problem,
          };
    final title = !managed
        ? '系统里的 Codex'
        : switch (r.status) {
            UiCodexStatus.notInstalled => '未下载',
            UiCodexStatus.downloading => '下载中',
            UiCodexStatus.verifying => '校验中',
            UiCodexStatus.ready => '已就绪',
            UiCodexStatus.failed => '没能下载',
          };
    final Widget? action = !managed
        ? null
        : switch (r.status) {
            UiCodexStatus.notInstalled => PillButton(
                label: '下载',
                primary: true,
                onTap: () => _runtimeDo((h) => h.installCodex())),
            UiCodexStatus.downloading => PillButton(
                label: '取消',
                onTap: () => _runtimeDo((h) => h.cancelCodexInstall())),
            UiCodexStatus.failed => PillButton(
                label: '重试',
                primary: true,
                onTap: () => _runtimeDo((h) => h.installCodex())),
            _ => null,
          };
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
    return SettingsCard(title: 'Codex', children: [
      SettingsRow(
        title: title,
        subtitle: _runtimeError ?? subtitle,
        mark: managed && r.status == UiCodexStatus.ready
            ? const StateDot(NextColors.mint)
            : null,
        trailing: action,
        below: r.status == UiCodexStatus.downloading && total != null
            ? Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: ThinBar(
                    progress: r.receivedBytes / total, live: true, height: 3),
              )
            : null,
      ),
      SettingsRow(
        title: '运行环境选项',
        below: Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_runtimeChoice() case final choice?) choice,
            field(
                '使用',
                Segmented<UiCodexSource>(
                  value: _runtimeSource,
                  options: [
                    for (final (v, t) in const [
                      (UiCodexSource.managed, '自动下载'),
                      (UiCodexSource.path, '系统里的'),
                      (UiCodexSource.specified, '指定路径'),
                    ])
                      (
                        v,
                        t,
                        (c) => Text(t, style: NextText.sans(12.5, color: c))
                      ),
                  ],
                  onChanged: (v) => _runtimeEdit(() => _runtimeSource = v),
                )),
            if (_runtimeSource == UiCodexSource.specified)
              field(
                  '路径',
                  LiveTextField(
                      value: _executable,
                      hint: '/usr/local/bin/codex',
                      width: 300,
                      mono: true,
                      onChanged: (v) => _runtimeEdit(() => _executable = v))),
            if (_runtimeSource == UiCodexSource.managed)
              field(
                  '镜像',
                  LiveTextField(
                      value: _mirror,
                      hint: 'GitHub',
                      width: 300,
                      onChanged: (v) => _runtimeEdit(() => _mirror = v))),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_runtimeDirty)
                PillButton(label: '保存', primary: true, onTap: _saveRuntime),
              if (r.licensesDirectory case final dir?)
                if (Platform.isMacOS)
                  PillButton(
                      label: '开源许可',
                      onTap: () => unawaited(Process.run('open', [dir]))),
              if (managed && r.status == UiCodexStatus.ready)
                PillButton(
                    label: '移除',
                    danger: true,
                    onTap: () => _runtimeDo((h) => h.removeCodex())),
            ]),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final setup = _setup;
    final files = _files;
    final changed = widget.model.byNipa;
    final runtime = _runtime;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (setup != null) _modelCard(setup),
      if (setup?.runtime == UiAgentRuntimeKind.dsh)
        if (_dsh case final dsh?) _dshCard(dsh),
      if (setup?.runtime == UiAgentRuntimeKind.dsh &&
          _host is NextHostDshConfigSettings)
        DshConfigCard(host: _host as NextHostDshConfigSettings),
      if (setup?.runtime != UiAgentRuntimeKind.dsh && runtime != null)
        _runtimeCard(runtime),
      if (files != null)
        SettingsCard(title: '梨花记得的事', children: [
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
        SettingsCard(title: '梨花改过的设置', children: [
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

/// A provider's fill-in: address, model, wire protocol and what its models
/// need from it.
class _Template {
  const _Template(this.name, this.baseUrl, this.model, this.api, this.reasoning,
      this.compat);
  final String name, baseUrl, model, reasoning;
  final UiModelApi api;
  final Map<String, Object?> compat;
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
