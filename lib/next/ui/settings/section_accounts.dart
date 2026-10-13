import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/settings_data.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import 'controls.dart';
import 'registry_rows.dart';

/// A tap that asks once more before it does something that cannot be
/// undone here: the second tap within three seconds does it.
class ConfirmPill extends StatefulWidget {
  const ConfirmPill(
      {super.key,
      required this.label,
      required this.confirm,
      required this.onConfirm});
  final String label;
  final String confirm;
  final VoidCallback onConfirm;

  @override
  State<ConfirmPill> createState() => _ConfirmPillState();
}

class _ConfirmPillState extends State<ConfirmPill> {
  Timer? _armed;

  @override
  void dispose() {
    _armed?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PillButton(
        label: _armed == null ? widget.label : widget.confirm,
        danger: _armed != null,
        onTap: () {
          if (_armed != null) {
            _armed!.cancel();
            setState(() => _armed = null);
            widget.onConfirm();
            return;
          }
          setState(() => _armed = Timer(const Duration(seconds: 3), () {
                if (mounted) setState(() => _armed = null);
              }));
        },
      );
}

/// A round mark for a service, in its colour.
class ServiceMark extends StatelessWidget {
  const ServiceMark(this.text, this.color, {super.key, this.square = false});
  final String text;
  final Color color;
  final bool square;

  static (String, Color) of(String kind) => switch (kind) {
        'dandanplay' => ('弹', const Color(0xFFFF2E55)),
        'bangumi' => ('B', const Color(0xFFF09199)),
        'jellyfin' => ('J', const Color(0xFF8A6CF0)),
        'emby' => ('E', const Color(0xFF52B54B)),
        'smb' => ('S', const Color(0xFF4A90D9)),
        'webdav' => ('W', const Color(0xFFE0A33A)),
        'nipaplay' => ('N', const Color(0xFFFF6F8A)),
        'dandanplay_remote' => ('弹', const Color(0xFFFF2E55)),
        _ => ('·', NextColors.p3),
      };

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(square ? 9 : 16),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(text,
            style: NextText.sans(13.5, weight: FontWeight.w700, color: color)),
      );
}

/// 弹弹play and Bangumi: who is signed in, signing in and out, and
/// Bangumi's watch history sync.
class AccountsSection extends StatefulWidget {
  const AccountsSection({super.key, required this.data});
  final NextSettingsData data;

  @override
  State<AccountsSection> createState() => _AccountsSectionState();
}

class _AccountsSectionState extends State<AccountsSection> {
  List<UiAccount>? _accounts;
  UiBangumiSync? _sync;
  final _busy = <String>{};
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = widget.data.changes.listen((_) => _load(settle: true));
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load({bool settle = false}) async {
    final accounts = await widget.data.accounts();
    final bangumi =
        accounts.where((a) => a.provider == 'bangumi').firstOrNull?.loggedIn ??
            false;
    UiBangumiSync? sync;
    if (bangumi) {
      try {
        sync = await widget.data.bangumiSync();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _sync = sync;
      if (settle) _busy.clear();
    });
  }

  Future<void> _run(String what, Future<void> Function() action,
      {bool waits = false}) async {
    setState(() => _busy.add(what));
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _busy.remove(what));
      return;
    }
    // A login or sync ends later; the page hears it as a change.
    if (!waits && mounted) {
      setState(() => _busy.remove(what));
      await _load();
    } else {
      Timer(const Duration(minutes: 2), () {
        if (mounted && _busy.remove(what)) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    if (accounts == null) return const SizedBox(height: 120);
    final bangumi =
        accounts.where((a) => a.provider == 'bangumi' && a.loggedIn).isNotEmpty;
    final sync = _sync;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Row(children: [
          for (final (i, a) in accounts.indexed) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(
              child: _AccountTile(
                account: a,
                busy: _busy.contains(a.provider),
                onLogin: () => _run(
                    a.provider, () => widget.data.login(a.provider),
                    waits: true),
                onLogout: () =>
                    _run(a.provider, () => widget.data.logout(a.provider)),
              ),
            ),
          ],
        ]),
      ),
      if (bangumi)
        SettingsCard(title: 'Bangumi 同步', children: [
          SettingsRow(
            title: '观看记录',
            subtitle: sync?.last == null
                ? null
                : [
                    whenText(sync!.last!),
                    if (sync.works > 0) '${sync.works} 部',
                    if (sync.failed > 0) '${sync.failed} 部没同步上',
                  ].join(' · '),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              PillButton(
                  label: '全部重新同步',
                  busy: _busy.contains('full'),
                  onTap: _busy.contains('sync')
                      ? null
                      : () => _run(
                          'full', () => widget.data.syncBangumi(full: true),
                          waits: true)),
              const SizedBox(width: 8),
              PillButton(
                  label: '同步',
                  primary: true,
                  busy: _busy.contains('sync'),
                  onTap: _busy.contains('full')
                      ? null
                      : () => _run('sync', () => widget.data.syncBangumi(),
                          waits: true)),
            ]),
          ),
        ]),
    ]);
  }
}

/// An account as a tile: the service, who is signed in, the way in or out.
class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.busy,
    required this.onLogin,
    required this.onLogout,
  });
  final UiAccount account;
  final bool busy;
  final VoidCallback onLogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final (mark, color) = ServiceMark.of(account.provider);
    final a = account;
    return Container(
      height: 156,
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NextColors.line),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: a.loggedIn ? 0.16 : 0.07),
            const Color(0x05FFFFFF),
          ],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Transform.scale(
              scale: 1.25,
              alignment: Alignment.topLeft,
              child: ServiceMark(mark, color)),
          const Spacer(),
          if (a.loggedIn) const StateDot(NextColors.mint),
        ]),
        const Spacer(),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(a.name,
                      style: NextText.sans(16, weight: FontWeight.w600)),
                  if (a.loggedIn && (a.username ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(a.username!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NextText.sans(12.5, color: NextColors.p3)),
                    ),
                ]),
          ),
          if (a.loggedIn)
            ConfirmPill(label: '退出', confirm: '确定退出', onConfirm: onLogout)
          else
            PillButton(label: '登录', primary: true, busy: busy, onTap: onLogin),
        ]),
      ]),
    );
  }
}

/// Media servers and shares: each one's place and state, opened to change,
/// log in, check, choose its libraries or remove; and adding one.
class SourcesSection extends StatefulWidget {
  const SourcesSection({super.key, required this.data, this.open});
  final NextSettingsData data;

  /// A source to show opened (debug).
  final String? open;

  @override
  State<SourcesSection> createState() => SourcesSectionState();
}

class SourcesSectionState extends State<SourcesSection> {
  List<UiMediaSource>? _sources;
  String? _open;
  bool _adding = false;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _open = widget.open;
    _load();
    _changes = widget.data.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final sources = await widget.data.sources();
    if (mounted) setState(() => _sources = sources);
  }

  /// Opens one source, or the new one (`new`), or none (debug).
  void debugOpen(String? which) => setState(() {
        _adding = which == 'new';
        _open = which == 'new' ? null : which;
      });

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    if (sources == null) return const SizedBox(height: 120);
    return SettingsCard(children: [
      for (final s in sources)
        _SourceRow(
          key: ValueKey(s.sourceId),
          source: s,
          data: widget.data,
          open: _open == s.sourceId,
          onTap: () => setState(() {
            _open = _open == s.sourceId ? null : s.sourceId;
            _adding = false;
          }),
          onChanged: _load,
        ),
      SettingsRow(
        leading: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: NextColors.line2),
          ),
          child: const NextIcon(NextGlyph.plus, size: 14, color: NextColors.p2),
        ),
        title: '添加',
        dim: !_adding,
        onTap: () => setState(() {
          _adding = !_adding;
          _open = null;
        }),
        below: _adding
            ? _SourceEditor(
                onSave: (draft) async {
                  final added = await widget.data.addSource(draft);
                  if (!mounted) return;
                  setState(() {
                    _adding = false;
                    _open = added.sourceId;
                  });
                  await _load();
                },
              )
            : null,
      ),
    ]);
  }
}

class _SourceRow extends StatefulWidget {
  const _SourceRow({
    super.key,
    required this.source,
    required this.data,
    required this.open,
    required this.onTap,
    required this.onChanged,
  });
  final UiMediaSource source;
  final NextSettingsData data;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback onChanged;

  @override
  State<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<_SourceRow> {
  List<UiSourceLibrary>? _libraries;
  late List<String> _selected = [...widget.source.selected];
  String? _code;
  String? _status;
  bool _checking = false;
  bool _logging = false;

  @override
  void didUpdateWidget(_SourceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !oldWidget.open) _loadLibraries();
    if (widget.source.state == UiSourceState.connected && _code != null) {
      _code = null;
    }
    if (oldWidget.source.selected.join() != widget.source.selected.join()) {
      _selected = [...widget.source.selected];
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.open) _loadLibraries();
  }

  Future<void> _loadLibraries() async {
    try {
      final libraries = await widget.data.libraries(widget.source.sourceId);
      if (mounted) setState(() => _libraries = libraries);
    } catch (_) {
      if (mounted) setState(() => _libraries = const []);
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    final r = await widget.data.checkSource(widget.source.sourceId);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = r.ok ? '连接正常' : r.message ?? '连不上';
    });
    widget.onChanged();
    if (r.ok) _loadLibraries();
  }

  Future<void> _login() async {
    setState(() {
      _logging = true;
      _status = null;
    });
    try {
      final r = await widget.data.loginSource(widget.source.sourceId);
      if (!mounted) return;
      setState(() => _code = r.code);
    } catch (_) {
      if (mounted) setState(() => _status = '没能登录');
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  Future<void> _toggle(String id) async {
    final next = _selected.contains(id)
        ? ([..._selected]..remove(id))
        : [..._selected, id];
    setState(() => _selected = next);
    try {
      await widget.data.selectLibraries(widget.source.sourceId, next);
    } catch (_) {
      if (mounted) setState(() => _selected = [...widget.source.selected]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final (mark, color) = ServiceMark.of(s.type);
    final state = switch (s.state) {
      UiSourceState.connected => NextColors.mint,
      UiSourceState.unverified => NextColors.p4,
      UiSourceState.failed => NextColors.accent,
    };
    return SettingsRow(
      leading: ServiceMark(mark, color, square: true),
      title: s.name,
      subtitle: [
        UiMediaSource.typeName(s.type),
        if (s.place.isNotEmpty) s.place
      ].join(' · '),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        StateDot(state, glow: s.state != UiSourceState.unverified),
        const SizedBox(width: 14),
        AnimatedRotation(
          turns: widget.open ? 0.25 : 0,
          duration: const Duration(milliseconds: 200),
          curve: NextMotion.ease,
          child: const NextIcon(NextGlyph.chevronRight,
              size: 14, color: NextColors.p3),
        ),
      ]),
      onTap: widget.onTap,
      below: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: NextMotion.ease,
        alignment: Alignment.topCenter,
        child: !widget.open
            ? const SizedBox(width: double.infinity)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _SourceEditor(
                  source: s,
                  onSave: (draft) async {
                    await widget.data.updateSource(s.sourceId, draft);
                    widget.onChanged();
                  },
                ),
                if (_code != null) _QuickConnect(code: _code!),
                if (_libraries case final libraries? when libraries.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(64, 6, 18, 6),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 64,
                            height: 30,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('显示',
                                  style: NextText.sans(12.5,
                                      color: NextColors.p3)),
                            ),
                          ),
                          Expanded(
                            child: Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final l in libraries)
                                _LibraryChip(
                                  name: l.name,
                                  on: _selected.contains(l.id),
                                  onTap: () => _toggle(l.id),
                                ),
                            ]),
                          ),
                        ]),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(64, 10, 18, 16),
                  child: Row(children: [
                    PillButton(
                        label: '登录',
                        primary: s.state != UiSourceState.connected,
                        busy: _logging,
                        onTap: _login),
                    const SizedBox(width: 8),
                    PillButton(label: '检查', busy: _checking, onTap: _check),
                    if (_status != null) ...[
                      const SizedBox(width: 12),
                      Text(_status!,
                          style: NextText.sans(12.5,
                              color: _status == '连接正常'
                                  ? NextColors.mint
                                  : NextColors.accent2)),
                    ],
                    const Spacer(),
                    ConfirmPill(
                      label: '移除',
                      confirm: '确定移除',
                      onConfirm: () async {
                        await widget.data.removeSource(s.sourceId);
                        widget.onChanged();
                      },
                    ),
                  ]),
                ),
              ]),
      ),
    );
  }
}

class _LibraryChip extends StatelessWidget {
  const _LibraryChip(
      {required this.name, required this.on, required this.onTap});
  final String name;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: name,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on
                ? NextColors.accentSoft
                : hovered
                    ? const Color(0x14FFFFFF)
                    : const Color(0x08FFFFFF),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
                color: on ? const Color(0x80FF2E55) : NextColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (on) ...[
              const NextIcon(NextGlyph.check,
                  size: 12, color: NextColors.accent2),
              const SizedBox(width: 6),
            ],
            Text(name,
                style: NextText.sans(12.5,
                    color: on ? NextColors.paper : NextColors.p2)),
          ]),
        ),
      );
}

class _QuickConnect extends StatelessWidget {
  const _QuickConnect({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(64, 6, 18, 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: NextColors.accentSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Text('在服务器上批准', style: NextText.sans(12.5, color: NextColors.p2)),
            const Spacer(),
            Text(code,
                style: NextText.num(22,
                    weight: FontWeight.w600, letterSpacing: 4)),
          ]),
        ),
      );
}

/// A source's place and account; a new one starts with its kind.
class _SourceEditor extends StatefulWidget {
  const _SourceEditor({this.source, required this.onSave});
  final UiMediaSource? source;
  final Future<void> Function(UiSourceDraft draft) onSave;

  @override
  State<_SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<_SourceEditor> {
  late String _type = widget.source?.type ?? 'jellyfin';
  late String _name = widget.source?.name ?? '';
  late String _url = widget.source?.url ?? '';
  late String _user = widget.source?.username ?? '';
  late String _host = _smbHost(widget.source?.url);
  late String _port = _smbPort(widget.source?.url);
  bool _saving = false;
  String? _error;

  static String _smbHost(String? url) => Uri.tryParse(url ?? '')?.host ?? '';
  static String _smbPort(String? url) {
    final uri = Uri.tryParse(url ?? '');
    return uri != null && uri.hasPort ? '${uri.port}' : '';
  }

  bool get _changed {
    final s = widget.source;
    if (s == null) return _name.trim().isNotEmpty;
    return _name != s.name ||
        _user != s.username ||
        (UiMediaSource.byHost(_type)
            ? _host != _smbHost(s.url) || _port != _smbPort(s.url)
            : _url != s.url);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(UiSourceDraft(
        type: _type,
        name: _name.trim(),
        url: UiMediaSource.byHost(_type) ? null : _url.trim(),
        username: _user.trim(),
        host: UiMediaSource.byHost(_type) ? _host.trim() : null,
        port: int.tryParse(_port.trim()),
      ));
    } catch (_) {
      if (mounted) setState(() => _error = '没能保存');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, String value, ValueChanged<String> set,
          {String? hint, double width = 320}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(
            width: 64,
            child:
                Text(label, style: NextText.sans(12.5, color: NextColors.p3)),
          ),
          LiveTextField(
              value: value,
              onChanged: (v) => setState(() => set(v)),
              hint: hint,
              width: width),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final fresh = widget.source == null;
    final byHost = UiMediaSource.byHost(_type);
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 2, 18, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (fresh)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ChoiceControl<String>(
              value: _type,
              options: [
                for (final t in UiMediaSource.types)
                  (t, UiMediaSource.typeName(t))
              ],
              onChanged: (t) => setState(() => _type = t),
            ),
          ),
        _field('名称', _name, (v) => _name = v),
        if (byHost) ...[
          _field('主机', _host, (v) => _host = v, hint: '192.168.1.2'),
          _field('端口', _port, (v) => _port = v, hint: '445', width: 96),
        ] else
          _field('地址', _url, (v) => _url = v, hint: 'http://'),
        if (_type != 'dandanplay_remote')
          _field('用户名', _user, (v) => _user = v),
        if (_changed || _error != null)
          Padding(
            padding: const EdgeInsets.only(left: 64, top: 4),
            child: Row(children: [
              PillButton(
                  label: fresh ? '添加' : '保存',
                  primary: true,
                  busy: _saving,
                  onTap: _changed ? _save : null),
              if (_error != null) ...[
                const SizedBox(width: 12),
                Text(_error!,
                    style: NextText.sans(12.5, color: NextColors.accent2)),
              ],
            ]),
          ),
      ]),
    );
  }
}
