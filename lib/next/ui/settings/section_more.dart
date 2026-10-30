import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/gui_calls.dart';
import '../data/settings_data.dart';
import '../data/upkeep.dart';
import '../theme/tokens.dart';
import '../widgets/sheet.dart' show withDecisions;
import 'controls.dart';
import 'registry_rows.dart';
import 'section_accounts.dart' show ConfirmPill;
import 'settings_layout.dart';

/// Plugins: the installed ones, each on or off, updated or deleted; the
/// market and a script from this computer behind “更多”.
class PluginsSection extends StatefulWidget {
  const PluginsSection({
    super.key,
    required this.plugins,
    required this.data,
    required this.model,
    required this.more,
    required this.onMore,
    this.highlight,
  });
  final NextPlugins plugins;

  /// The system's file picker.
  final NextSettingsData data;

  /// The plugins' own settings, from the registry.
  final SettingsModel model;
  final bool more;
  final VoidCallback onMore;
  final String? highlight;

  @override
  State<PluginsSection> createState() => PluginsSectionState();
}

class PluginsSectionState extends State<PluginsSection> {
  List<UiPlugin>? _installed;
  UiMarket? _market;
  String? _failed;
  String? _marketFailed;
  bool _fetching = false;
  String? _open;

  /// Plugins (or `file`) being installed, updated, switched or deleted.
  final _busy = <String>{};
  final _errors = <String, String>{};

  /// Switched, until NipaPlay answers.
  final _switched = <String, bool>{};

  /// A plugin's own actions running (`id/actionId`), and what each plugin
  /// last answered.
  final _doing = <String>{};
  final _answers = <String, UiPluginResult>{};

  @override
  void initState() {
    super.initState();
    _load();
    _fetch();
  }

  @override
  void didUpdateWidget(PluginsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.more && !oldWidget.more) _fetch();
  }

  Future<void> _load() async {
    try {
      final installed = await widget.plugins.installed();
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _failed = null;
        _switched.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _failed = '没能读取');
    }
    try {
      final market = await widget.plugins.market();
      if (!mounted) return;
      setState(() {
        _market = market;
        _marketFailed = null;
      });
    } catch (_) {
      if (mounted) setState(() => _marketFailed = '没能取到');
    }
  }

  /// The market as it is now (opening “更多”).
  Future<void> _fetch() async {
    setState(() {
      _fetching = true;
      _marketFailed = null;
    });
    try {
      final market = await widget.plugins.market(refresh: true);
      if (mounted) setState(() => _market = market);
    } catch (_) {
      if (mounted) setState(() => _marketFailed = '没能取到');
    }
    if (mounted) setState(() => _fetching = false);
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() {
      _busy.add(id);
      _errors.remove(id);
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _errors[id] = callFailure(e));
    }
    await _load();
    if (mounted) setState(() => _busy.remove(id));
  }

  Future<void> _invoke(UiPlugin p, UiPluginAction a) async {
    final key = '${p.id}/${a.id}';
    setState(() {
      _doing.add(key);
      _errors.remove(p.id);
      _answers.remove(p.id);
    });
    try {
      final r = await withDecisions(
          widget.plugins.calls, () => widget.plugins.invoke(p.id, a.id));
      if (r != null && mounted) {
        setState(() => _answers[p.id] =
            UiPluginResult.from(r) ?? const UiPluginResult(title: '完成'));
      }
    } catch (e) {
      if (mounted) setState(() => _errors[p.id] = callFailure(e));
    }
    if (mounted) setState(() => _doing.remove(key));
  }

  /// Opens a plugin, and runs one of its actions (debug).
  Future<void> debugInvoke(String id, String? actionId) async {
    setState(() => _open = id);
    if (actionId == null) return;
    final p = _installed!.firstWhere((p) => p.id == id);
    await _invoke(p, p.actions.firstWhere((a) => a.id == actionId));
  }

  Widget _answer(UiPluginResult r) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const StateDot(NextColors.mint),
            const SizedBox(width: 8),
            Text(r.title,
                style: NextText.sans(12.5,
                    weight: FontWeight.w600, color: NextColors.p2)),
          ]),
          if (r.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 6),
              child: Text(r.content,
                  style:
                      NextText.sans(12.5, color: NextColors.p3, height: 1.5)),
            ),
        ],
      );

  Future<void> _fromFile() async {
    final path = await widget.data.pickPath(directory: false);
    if (path == null) return;
    await _run('file', () => widget.plugins.install(path: path));
  }

  Widget _version(String? version) => version == null
      ? const SizedBox.shrink()
      : Text(version, style: NextText.num(11.5, color: NextColors.p4));

  Widget _row(UiPlugin p) {
    final update = _market?.updates[p.id];
    final busy = _busy.contains(p.id);
    final open = _open == p.id;
    final about = (p.description ?? '').isNotEmpty || !p.builtin;
    final details = about || p.actions.isNotEmpty;
    return SettingsRow(
      key: ValueKey(p.id),
      title: p.name,
      mark: Row(mainAxisSize: MainAxisSize.min, children: [
        _version(p.version),
        if (p.error != null || _errors.containsKey(p.id)) ...[
          const SizedBox(width: 8),
          const StateDot(NextColors.accent2),
        ],
      ]),
      subtitle: _errors[p.id] ?? (p.error != null ? '没能载入' : null),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (update != null) ...[
          PillButton(
            label: '更新到 $update',
            busy: busy,
            onTap: () => _run(p.id,
                () => widget.plugins.install(remoteId: p.id, updating: p.id)),
          ),
          const SizedBox(width: 14),
        ],
        NextToggle(
          value: _switched[p.id] ?? p.enabled,
          label: p.name,
          onChanged: busy
              ? null
              : (on) {
                  setState(() => _switched[p.id] = on);
                  _run(p.id, () => widget.plugins.setEnabled(p.id, on));
                },
        ),
      ]),
      onTap: details ? () => setState(() => _open = open ? null : p.id) : null,
      below: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: NextMotion.ease,
        alignment: Alignment.topCenter,
        child: !open
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (about)
                        Row(children: [
                          Expanded(
                            child: Text(p.description ?? '',
                                style: NextText.sans(12.5,
                                    color: NextColors.p3, height: 1.5)),
                          ),
                          if (!p.builtin) ...[
                            const SizedBox(width: 16),
                            ConfirmPill(
                              label: '删除',
                              confirm: '确定删除',
                              onConfirm: () =>
                                  _run(p.id, () => widget.plugins.delete(p.id)),
                            ),
                          ],
                        ]),
                      if (p.actions.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: about ? 12 : 0),
                          child: Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final a in p.actions)
                              PillButton(
                                label: a.title,
                                busy: _doing.contains('${p.id}/${a.id}'),
                                onTap: p.enabled ? () => _invoke(p, a) : null,
                              ),
                          ]),
                        ),
                      if (_answers[p.id] case final r?)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _answer(r),
                        ),
                    ]),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final installed = _installed;
    if (installed == null) {
      return _failed == null
          ? const SizedBox(height: 120)
          : Text(_failed!, style: NextText.sans(13, color: NextColors.p3));
    }
    final have = {for (final p in installed) p.id};
    final market = [
      for (final p in _market?.plugins ?? const <UiPlugin>[])
        if (!have.contains(p.id)) p
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (installed.isNotEmpty)
        SettingsCard(children: [for (final p in installed) _row(p)]),
      RegistryGroups(
        section: SettingsSection.plugins,
        model: widget.model,
        more: false,
        onMore: () {},
        highlight: widget.highlight,
        skipFolded: true,
      ),
      SettingsCard(title: '市场', children: [
        if (_fetching && market.isEmpty)
          const SettingsRow(title: '', trailing: BusyDots())
        else if (_marketFailed != null && market.isEmpty)
          SettingsRow(
            title: _marketFailed!,
            dim: true,
            trailing: PillButton(label: '再试', onTap: _fetch),
          ),
        for (final p in market)
          SettingsRow(
            key: ValueKey('market:${p.id}'),
            title: p.name,
            mark: _version(p.version),
            subtitle: _errors[p.id] ?? p.description,
            trailing: PillButton(
              label: '安装',
              busy: _busy.contains(p.id),
              onTap: () =>
                  _run(p.id, () => widget.plugins.install(remoteId: p.id)),
            ),
          ),
        SettingsRow(
          title: '从文件安装',
          subtitle: _errors['file'],
          trailing: PillButton(
              label: '选择', busy: _busy.contains('file'), onTap: _fromFile),
        ),
      ]),
    ]);
  }
}

/// Records kept alike on this computer and others, through a WebDAV
/// folder: where, what, how often; signing in, testing, syncing now.
class SyncSection extends StatefulWidget {
  const SyncSection({
    super.key,
    required this.sync,
    required this.model,
    required this.more,
    required this.onMore,
    this.highlight,
  });
  final NextSync sync;
  final SettingsModel model;
  final bool more;
  final VoidCallback onMore;
  final String? highlight;

  @override
  State<SyncSection> createState() => SyncSectionState();
}

class SyncSectionState extends State<SyncSection> {
  UiSync? _s;
  String? _failed;

  /// What the last change or command could not do.
  String? _note;
  bool? _tested;
  bool _testing = false;
  bool _logging = false;
  bool _running = false;
  bool? _enabling;
  Timer? _follow;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _follow?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.sync.status();
      if (!mounted) return;
      setState(() {
        _s = s;
        _failed = null;
        if (_enabling == s.enabled) _enabling = null;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = '没能读取');
    }
  }

  /// Reads the state again for a while: syncing, signing in and switching
  /// on end in the background.
  void _watch() {
    _follow?.cancel();
    var ticks = 0;
    _follow = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
      ticks++;
      await _load();
      if (ticks >= 3 && !(_s?.syncing ?? false) || ticks > 80) {
        t.cancel();
        if (mounted) setState(() => _enabling = null);
      }
    });
  }

  Future<bool> _do(Future<void> Function() action) async {
    setState(() => _note = null);
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) setState(() => _note = callFailure(e));
      return false;
    }
  }

  Future<void> _configure({
    String? url,
    String? username,
    String? folder,
    int? minutes,
    List<String>? kinds,
    bool? onChange,
  }) async {
    final s = _s!;
    // A new address or user takes the saved password with it.
    final account = url != null && url != s.url ||
        username != null && username != s.username;
    final done = await _do(() => widget.sync.configure(
        url: url,
        username: username,
        folder: folder,
        minutes: minutes,
        kinds: kinds,
        onChange: onChange));
    if (done && account && mounted) setState(() => _tested = null);
    await _load();
  }

  Future<void> _login() async {
    setState(() => _logging = true);
    final done = await _do(widget.sync.login);
    if (!mounted) return;
    setState(() {
      _logging = false;
      if (done) _tested = null;
    });
    _watch();
  }

  /// Whether the server answers with the saved account (debug).
  Future<void> test() async {
    setState(() {
      _testing = true;
      _tested = null;
    });
    final ok = await widget.sync.test();
    if (mounted) {
      setState(() {
        _testing = false;
        _tested = ok;
      });
    }
  }

  /// Syncs now, as 立即同步 does (debug).
  Future<void> run() async {
    setState(() => _running = true);
    await _do(widget.sync.run);
    if (mounted) setState(() => _running = false);
    await _load();
    _watch();
  }

  Future<void> _enable(bool on) async {
    setState(() => _enabling = on);
    if (!await _do(() => widget.sync.setEnabled(on)) && mounted) {
      setState(() => _enabling = null);
    }
    await _load();
    _watch();
  }

  Widget _state(Color color, String text, {Color? textColor}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        StateDot(color),
        const SizedBox(width: 8),
        Text(text,
            style: NextText.sans(12.5, color: textColor ?? NextColors.p2)),
      ]);

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return _failed == null
          ? const SizedBox(height: 120)
          : Text(_failed!, style: NextText.sans(13, color: NextColors.p3));
    }
    final enabled = _enabling ?? s.enabled;
    final problem = _note ?? (s.error != null ? '没同步上' : null);
    final relogin = s.configured && !s.hasPassword;
    final connection = switch (_tested) {
      true => _state(NextColors.mint, '连接正常'),
      false => _state(NextColors.accent, '连不上', textColor: NextColors.accent2),
      null when relogin => _state(NextColors.amber, '需要登录'),
      null when s.hasPassword => _state(NextColors.p4, '已登录'),
      null => null,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsCard(children: [
        SettingsRow(
          title: '多端同步',
          mark: problem == null
              ? null
              : _state(NextColors.accent, problem,
                  textColor: NextColors.accent2),
          subtitle: s.syncing
              ? '正在同步'
              : s.last == null
                  ? null
                  : '上次 ${whenText(s.last!)}',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            PillButton(
              label: '立即同步',
              busy: _running || s.syncing,
              onTap: enabled && s.configured ? run : null,
            ),
            const SizedBox(width: 14),
            NextToggle(
              value: enabled,
              label: '多端同步',
              onChanged: s.configured && _enabling == null ? _enable : null,
            ),
          ]),
        ),
      ]),
      SettingsCard(title: '服务器', children: [
        SettingsRow(
          title: '地址',
          trailing: FieldControl(
            value: s.url,
            hint: 'https://',
            width: 300,
            onCommit: (v) => _configure(url: v.trim()),
          ),
        ),
        SettingsRow(
          title: '用户名',
          trailing: FieldControl(
            value: s.username,
            width: 200,
            onCommit: (v) => _configure(username: v.trim()),
          ),
        ),
        SettingsRow(
          title: '连接',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (connection != null) ...[connection, const SizedBox(width: 14)],
            PillButton(
                label: '测试', busy: _testing, onTap: s.configured ? test : null),
            const SizedBox(width: 8),
            PillButton(
                label: s.hasPassword ? '重新登录' : '登录',
                primary: relogin,
                busy: _logging,
                onTap: s.configured ? _login : null),
          ]),
        ),
      ]),
      SettingsCard(title: '同步内容', children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (kind, name) in UiSync.allKinds)
                ChipToggle(
                  name: name,
                  on: s.kinds.contains(kind),
                  onTap: () => _configure(
                      kinds: s.kinds.contains(kind)
                          ? ([...s.kinds]..remove(kind))
                          : [...s.kinds, kind]),
                ),
            ]),
          ),
        ),
        SettingsRow(
          title: '记录变化时同步',
          trailing: NextToggle(
            value: s.onChange,
            onChanged: (on) => _configure(onChange: on),
          ),
        ),
      ]),
      SettingsCard(children: [
        SettingsRow(
          title: '远端文件夹',
          trailing: FieldControl(
            value: s.folder,
            hint: '/NipaPlay',
            width: 200,
            onCommit: (v) => _configure(folder: v.trim()),
          ),
        ),
        SettingsRow(
          title: '间隔',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            FieldControl(
              value: '${s.minutes}',
              width: 72,
              numeric: true,
              align: TextAlign.right,
              onCommit: (v) => _configure(minutes: int.tryParse(v.trim())),
            ),
            const SizedBox(width: 10),
            Text('分钟', style: NextText.sans(13, color: NextColors.p3)),
          ]),
        ),
      ]),
      RegistryGroups(
        section: SettingsSection.sync,
        model: widget.model,
        more: false,
        onMore: () {},
        highlight: widget.highlight,
        skipFolded: true,
      ),
    ]);
  }
}
