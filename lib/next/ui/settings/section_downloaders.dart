import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart' show Failure, FailureCode;

import '../data/downloaders.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import 'controls.dart';
import 'section_accounts.dart' show ConfirmPill, ServiceMark;

/// 设置 › 下载 › qBittorrent: the ones the person uses, here or on another
/// machine. Each has a name and an address; the login is typed here and kept
/// in the vault, never shown again.
class DownloadersSection extends StatefulWidget {
  const DownloadersSection({super.key, required this.downloaders});
  final NextDownloaders downloaders;

  @override
  State<DownloadersSection> createState() => DownloadersSectionState();
}

class DownloadersSectionState extends State<DownloadersSection> {
  List<UiDownloader>? _items;
  String? _open;
  bool _adding = false;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = widget.downloaders.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await widget.downloaders.list();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items ??= const []);
    }
  }

  /// Adds one as the form would (debug driver): `name`, `address`, `local`,
  /// `username`, and the password read from the file `passwordFile`.
  Future<void> debugAdd(Map<String, String> p) async {
    final file = p['passwordFile'];
    final password = file == null ? null : (await File(file).readAsString()).trim();
    await widget.downloaders.save(
        name: p['name'] ?? '',
        address: p['address'] ?? '',
        local: p['local'] == 'true',
        username: p['username'],
        password: password);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const SizedBox(height: 60);
    return SettingsCard(title: 'qBittorrent', children: [
      for (final item in items)
        _DownloaderRow(
          key: ValueKey(item.id),
          item: item,
          downloaders: widget.downloaders,
          open: _open == item.id,
          onTap: () => setState(() {
            _open = _open == item.id ? null : item.id;
            _adding = false;
          }),
          onChanged: _load,
        ),
      SettingsRow(
        leading: const _PlusMark(),
        title: '添加',
        dim: !_adding,
        onTap: () => setState(() {
          _adding = !_adding;
          _open = null;
        }),
        below: _adding
            ? _DownloaderEditor(
                downloaders: widget.downloaders,
                onSaved: () async {
                  setState(() => _adding = false);
                  await _load();
                })
            : null,
      ),
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

const _blue = Color(0xFF3F8AD6);

class _DownloaderRow extends StatefulWidget {
  const _DownloaderRow({
    super.key,
    required this.item,
    required this.downloaders,
    required this.open,
    required this.onTap,
    required this.onChanged,
  });
  final UiDownloader item;
  final NextDownloaders downloaders;
  final bool open;
  final VoidCallback onTap;
  final Future<void> Function() onChanged;

  @override
  State<_DownloaderRow> createState() => _DownloaderRowState();
}

class _DownloaderRowState extends State<_DownloaderRow> {
  bool _checking = false;
  String? _status;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    await widget.onChanged();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = widget.item.online == true ? '连接正常' : '连不上';
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return SettingsRow(
      leading: const ServiceMark('q', _blue, square: true),
      title: item.name,
      subtitle: [
        item.place,
        item.local ? '本机' : '远端',
        if (item.version != null) item.version!.replaceFirst('v', ''),
      ].join(' · '),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        StateDot(
            switch (item.online) {
              true => NextColors.mint,
              false => NextColors.accent,
              null => NextColors.p4,
            },
            glow: item.online != null),
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
                _DownloaderEditor(
                  item: item,
                  downloaders: widget.downloaders,
                  onSaved: widget.onChanged,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(64, 10, 18, 16),
                  child: Row(children: [
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
                        await widget.downloaders.remove(item.id);
                        await widget.onChanged();
                      },
                    ),
                  ]),
                ),
              ]),
      ),
    );
  }
}

class _DownloaderEditor extends StatefulWidget {
  const _DownloaderEditor(
      {this.item, required this.downloaders, required this.onSaved});
  final UiDownloader? item;
  final NextDownloaders downloaders;
  final Future<void> Function() onSaved;

  @override
  State<_DownloaderEditor> createState() => _DownloaderEditorState();
}

class _DownloaderEditorState extends State<_DownloaderEditor> {
  late String _name = widget.item?.name ?? '';
  late String _address = widget.item?.address ?? '';
  String _user = '';
  String _savedUser = '';
  String _password = '';
  late bool _local = widget.item?.local ?? false;

  /// The person chose where it runs; the address no longer decides.
  late bool _chosen = widget.item != null;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null && item.hasLogin) {
      widget.downloaders.username(item.id).then((name) {
        if (mounted) {
          setState(() {
            _user = _savedUser = name;
          });
        }
      }).catchError((_) {});
    }
  }

  bool get _changed {
    final item = widget.item;
    if (item == null) {
      return _name.trim().isNotEmpty && _address.trim().isNotEmpty;
    }
    return _name != item.name ||
        _address != item.address ||
        _local != item.local ||
        _user != _savedUser ||
        _password.isNotEmpty;
  }

  void _typedAddress(String value) {
    _address = value;
    if (!_chosen) {
      final uri = Uri.tryParse(value.trim());
      _local = uri != null &&
          (uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1');
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final item = widget.item;
    try {
      final clearing = item != null &&
          item.hasLogin &&
          _user.trim().isEmpty &&
          _password.isEmpty;
      String? username, password;
      if (clearing) {
        username = '';
        password = '';
      } else if (_password.isNotEmpty) {
        username = _user.trim();
        password = _password;
      } else if (item != null && item.hasLogin && _user != _savedUser) {
        username = _user.trim();
      }
      await widget.downloaders.save(
        id: item?.id,
        name: _name.trim(),
        address: _address.trim(),
        local: _local,
        username: username,
        password: password,
      );
      _password = '';
      await widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e is Failure && e.code == FailureCode.invalidInput ? '名称或地址不对' : '没能保存');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, String value, ValueChanged<String> set,
          {String? hint, double width = 320, bool obscure = false}) =>
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
              obscure: obscure,
              width: width),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final fresh = widget.item == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 2, 18, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _field('名称', _name, (v) => _name = v, hint: '家里、seedbox'),
        _field('地址', _address, _typedAddress, hint: 'http://192.168.1.5:8080'),
        _field('用户名', _user, (v) => _user = v),
        _field('密码', _password, (v) => _password = v,
            obscure: true,
            hint: !fresh && widget.item!.hasLogin ? '未更改' : null),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(
              width: 64,
              child: Text('位置',
                  style: NextText.sans(12.5, color: NextColors.p3)),
            ),
            ChoiceControl<bool>(
              value: _local,
              options: const [(true, '本机'), (false, '远端')],
              onChanged: (v) => setState(() {
                _local = v;
                _chosen = true;
              }),
            ),
          ]),
        ),
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
