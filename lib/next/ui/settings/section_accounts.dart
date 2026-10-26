import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart' show Failure, FailureCode;

import '../data/gui_calls.dart';
import '../data/settings_data.dart';
import '../data/upkeep.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/service_icon.dart';
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
  const ServiceMark(this.text, this.color,
      {super.key, this.square = false, this.provider});
  final String text;
  final Color color;
  final bool square;
  final String? provider;

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
        child: provider != null
            ? ServiceIcon(provider!, color: color)
            : Text(text,
                style:
                    NextText.sans(13.5, weight: FontWeight.w700, color: color)),
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
              child: ServiceMark(mark, color, provider: account.provider)),
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
/// log in, check, choose its libraries or remove; adding one, NipaPlay
/// shares nearby among them; and the folders on this computer.
class SourcesSection extends StatefulWidget {
  const SourcesSection(
      {super.key, required this.data, required this.folders, this.open});
  final NextSettingsData data;
  final NextFolders folders;

  /// `openSettings(section: sources, key: addKey)`: the page opens with a
  /// new source being added (the 片库's “添加来源”).
  static const addKey = '+source';

  /// A source to show opened, or `new` for one being added.
  final String? open;

  @override
  State<SourcesSection> createState() => SourcesSectionState();
}

class SourcesSectionState extends State<SourcesSection> {
  List<UiMediaSource>? _sources;
  String? _open;
  late bool _adding = widget.open == 'new';
  String _newType = 'jellyfin';
  final _addRow = GlobalKey();
  final _folders = GlobalKey<_FoldersState>();
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _open = _adding ? null : widget.open;
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
    if (!mounted) return;
    final first = _sources == null;
    setState(() => _sources = sources);
    if (first && _adding) _reveal();
  }

  /// Opens one source, or a new one (`new`, of [type] when given), or
  /// none.
  void show(String? which, {String? type}) {
    setState(() {
      _adding = which == 'new';
      _open = _adding ? null : which;
      if (type != null) _newType = type;
    });
    if (_adding) _reveal();
  }

  /// Scans every folder, as 全部扫描 does (debug).
  Future<void> debugScan() async => _folders.currentState?._scan(null);

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _addRow.currentContext;
        if (row != null && row.mounted) {
          Scrollable.ensureVisible(row,
              alignment: 0.2,
              duration: const Duration(milliseconds: 420),
              curve: NextMotion.ease);
        }
      });

  /// A new source; it opens, its login a tap away.
  Future<void> _add(UiSourceDraft draft) async {
    final added = await widget.data.addSource(draft);
    if (!mounted) return;
    setState(() {
      _adding = false;
      _open = added.sourceId;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    if (sources == null) return const SizedBox(height: 120);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsCard(children: [
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
          key: _addRow,
          leading: const _PlusMark(),
          title: '添加',
          dim: !_adding,
          onTap: () => setState(() {
            _adding = !_adding;
            _open = null;
          }),
          below: _adding
              ? _SourceEditor(
                  key: ValueKey(_newType),
                  type: _newType,
                  nearby: () => _Nearby(
                    folders: widget.folders,
                    known: {
                      for (final s in sources) Uri.tryParse(s.url)?.authority
                    },
                    onAdd: (share) => _add(UiSourceDraft(
                        type: 'nipaplay',
                        name: share.name,
                        url: share.address)),
                  ),
                  onSave: _add,
                )
              : null,
        ),
      ]),
      _Folders(key: _folders, folders: widget.folders),
    ]);
  }
}

class _PlusMark extends StatelessWidget {
  const _PlusMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: NextColors.line2),
        ),
        child: const NextIcon(NextGlyph.plus, size: 14, color: NextColors.p2),
      );
}

/// NipaPlay shares answering on this network, each a tap from added.
class _Nearby extends StatefulWidget {
  const _Nearby(
      {required this.folders, required this.known, required this.onAdd});
  final NextFolders folders;

  /// Where the sources already added are (host and port).
  final Set<String?> known;
  final Future<void> Function(UiShare share) onAdd;

  @override
  State<_Nearby> createState() => _NearbyState();
}

class _NearbyState extends State<_Nearby> {
  List<UiShare>? _found;
  String? _failed;
  String? _adding;

  @override
  void initState() {
    super.initState();
    _look();
  }

  Future<void> _look() async {
    setState(() {
      _found = null;
      _failed = null;
    });
    try {
      final found = await widget.folders.nearby();
      if (mounted) setState(() => _found = found);
    } catch (e) {
      if (mounted) setState(() => _failed = callFailure(e));
    }
  }

  Future<void> _add(UiShare share) async {
    setState(() {
      _adding = share.address;
      _failed = null;
    });
    try {
      await widget.onAdd(share);
    } catch (e) {
      if (mounted) setState(() => _failed = callFailure(e));
    }
    if (mounted) setState(() => _adding = null);
  }

  @override
  Widget build(BuildContext context) {
    final found = [
      for (final s in _found ?? const <UiShare>[])
        if (!widget.known.contains(Uri.tryParse(s.address)?.authority)) s
    ];
    final quiet = NextText.sans(12.5, color: NextColors.p3);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 64,
          height: 30,
          child: Align(
              alignment: Alignment.centerLeft, child: Text('附近', style: quiet)),
        ),
        Expanded(
          child: _found == null && _failed == null
              ? const SizedBox(
                  height: 30,
                  child:
                      Align(alignment: Alignment.centerLeft, child: BusyDots()))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in found)
                      SizedBox(
                        height: 38,
                        child: Row(children: [
                          Flexible(
                            child: Text(s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NextText.sans(13.5)),
                          ),
                          const SizedBox(width: 10),
                          Text(Uri.tryParse(s.address)?.authority ?? s.address,
                              style: NextText.num(12, color: NextColors.p3)),
                          const SizedBox(width: 14),
                          PillButton(
                              label: '添加',
                              busy: _adding == s.address,
                              onTap: _adding == null ? () => _add(s) : null),
                        ]),
                      ),
                    if (found.isEmpty || _failed != null)
                      SizedBox(
                        height: 30,
                        child: Row(children: [
                          Text(_failed ?? '没有发现',
                              style: NextText.sans(12.5,
                                  color: _failed == null
                                      ? NextColors.p4
                                      : NextColors.accent2)),
                          const SizedBox(width: 12),
                          PillButton(label: '再找', onTap: _look),
                        ]),
                      ),
                  ],
                ),
        ),
      ]),
    );
  }
}

/// The folders on this computer NipaPlay looks through: each one scanned
/// or removed; a new one, scanned as soon as it is added.
class _Folders extends StatefulWidget {
  const _Folders({super.key, required this.folders});
  final NextFolders folders;

  @override
  State<_Folders> createState() => _FoldersState();
}

class _FoldersState extends State<_Folders> {
  UiFolders? _list;
  String? _failed;

  /// What the last change could not do.
  String? _note;

  /// Folders (`*` all of them, `+` a new one) being handed over, and
  /// those whose scan just began.
  final _busy = <String>{};
  final _started = <String>{};
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await widget.folders.list();
      if (mounted) {
        setState(() {
          _list = list;
          _failed = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = '没能读取');
    }
  }

  /// A scan holds the folders: changing them waits for it.
  String _failure(Object e) =>
      e is Failure && e.code == FailureCode.conflict ? '正在扫描' : callFailure(e);

  Future<void> _run(String key, Future<void> Function() action) async {
    setState(() {
      _busy.add(key);
      _note = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _note = _failure(e));
    }
    if (mounted) setState(() => _busy.remove(key));
    await _load();
  }

  /// The scan is under way (its progress is in the background panel):
  /// the button says so for a moment.
  void _began(Iterable<String> keys) {
    setState(() => _started.addAll(keys));
    _timers.add(Timer(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      setState(() => _started.removeAll(keys));
      _load();
    }));
  }

  Future<void> _scan(String? path) => _run(path ?? '*', () async {
        await widget.folders.scan(path == null ? null : [path]);
        _began([path ?? '*']);
      });

  Future<void> _add() => _run('+', () async {
        final added = await widget.folders.add();
        if (added.isEmpty) return;
        await widget.folders.scan(added);
        await _load();
        _began(added);
      });

  /// “番剧”, and where it is, home as ~.
  static (String, String) _place(String path) {
    final parts = path
        .replaceFirst(
            RegExp(r'^(/Users/[^/]+|/home/[^/]+|[A-Za-z]:\\Users\\[^\\]+)'),
            '~')
        .split(RegExp(r'[\\/]'));
    final name = parts.lastWhere((p) => p.isNotEmpty, orElse: () => path);
    final parent = parts.sublist(0, parts.lastIndexOf(name));
    final shown = parent.length > 4
        ? ['…', ...parent.sublist(parent.length - 2)]
        : parent;
    return (name, shown.join('/'));
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null) {
      return _failed == null
          ? const SizedBox.shrink()
          : SettingsCard(
              title: '本机文件夹',
              children: [SettingsRow(title: _failed!, dim: true)]);
    }
    return SettingsCard(title: '本机文件夹', children: [
      for (final path in list.paths)
        () {
          final (name, parent) = _place(path);
          final failed = list.failedIn(path);
          final started = _started.contains(path);
          return SettingsRow(
            key: ValueKey(path),
            leading: const _FolderMark(),
            title: name,
            subtitle: parent,
            mark: failed == 0
                ? null
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const StateDot(NextColors.accent2, glow: false),
                    const SizedBox(width: 6),
                    Text('$failed',
                        style: NextText.num(11.5, color: NextColors.accent2)),
                  ]),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              PillButton(
                label: started ? '已开始' : '扫描',
                busy: _busy.contains(path),
                onTap: started ? null : () => _scan(path),
              ),
              const SizedBox(width: 8),
              ConfirmPill(
                label: '移除',
                confirm: '确定移除',
                onConfirm: () => _run(path, () => widget.folders.remove(path)),
              ),
            ]),
          );
        }(),
      SettingsRow(
        leading: const _PlusMark(),
        title: '添加文件夹',
        dim: true,
        onTap: _busy.contains('+') ? null : _add,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_note != null) ...[
            Text(_note!, style: NextText.sans(12.5, color: NextColors.accent2)),
            const SizedBox(width: 12),
          ],
          if (_busy.contains('+')) ...[
            const BusyDots(),
            const SizedBox(width: 12),
          ],
          if (list.paths.isNotEmpty)
            PillButton(
              label: _started.contains('*') ? '已开始' : '全部扫描',
              busy: _busy.contains('*'),
              onTap: _started.contains('*') ? null : () => _scan(null),
            ),
        ]),
      ),
    ]);
  }
}

/// A folder, drawn small in a quiet square.
class _FolderMark extends StatelessWidget {
  const _FolderMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: NextColors.line),
        ),
        child: const CustomPaint(size: Size(14, 11), painter: _FolderPainter()),
      );
}

class _FolderPainter extends CustomPainter {
  const _FolderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final (w, h) = (size.width, size.height);
    final path = Path()
      ..moveTo(0, 1.5)
      ..quadraticBezierTo(0, 0, 1.5, 0)
      ..lineTo(w * 0.36, 0)
      ..lineTo(w * 0.47, h * 0.17)
      ..lineTo(w - 1.5, h * 0.17)
      ..quadraticBezierTo(w, h * 0.17, w, h * 0.17 + 1.5)
      ..lineTo(w, h - 1.5)
      ..quadraticBezierTo(w, h, w - 1.5, h)
      ..lineTo(1.5, h)
      ..quadraticBezierTo(0, h, 0, h - 1.5)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round
          ..color = NextColors.p2);
  }

  @override
  bool shouldRepaint(_FolderPainter old) => false;
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
    final dot = s.needsPassword ? NextColors.accent : state;
    return SettingsRow(
      leading: ServiceMark(mark, color, square: true, provider: s.type),
      title: s.name,
      subtitle: [
        UiMediaSource.typeName(s.type),
        if (s.place.isNotEmpty) s.place,
        if (s.needsPassword) '需要重新输入密码',
      ].join(' · '),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        StateDot(dot,
            glow: s.needsPassword || s.state != UiSourceState.unverified),
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
                                ChipToggle(
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
  const _SourceEditor(
      {super.key, this.source, this.type, this.nearby, required this.onSave});
  final UiMediaSource? source;

  /// A new one's kind to begin with.
  final String? type;

  /// NipaPlay shares nearby, when a new one is NipaPlay.
  final Widget Function()? nearby;
  final Future<void> Function(UiSourceDraft draft) onSave;

  @override
  State<_SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<_SourceEditor> {
  late String _type = widget.source?.type ?? widget.type ?? 'jellyfin';
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
        if (fresh && _type == 'nipaplay' && widget.nearby != null)
          widget.nearby!(),
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
