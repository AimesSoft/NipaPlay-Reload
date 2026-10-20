import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../security/built_in_credentials.dart';
import '../../ui_data/host_settings.dart';
import '../data/gui_calls.dart' show callFailure;
import 'controls.dart';
import 'section_accounts.dart' show ConfirmPill;
import 'settings_layout.dart';

/// The keys only the person at this device sets: whether each is set,
/// never the key itself. Nothing when the host keeps none.
class HostKeys extends ChangeNotifier {
  HostKeys(this.host) {
    _changes = host.changes.listen((_) => load());
  }
  final NextHostSettings host;
  late final StreamSubscription<void> _changes;
  bool _disposed = false;

  /// Null until read, and on a host that keeps no keys.
  UiHostKeys? value;

  Future<void> load() async {
    try {
      value = await host.deviceSettings.keys();
    } on UnsupportedError {
      value = null;
    }
    if (!_disposed) notifyListeners();
  }

  /// Null keeps a key; empty clears it.
  Future<void> set({String? spoilerAi, String? tmdb}) async {
    await host.deviceSettings.setKeys(spoilerAi: spoilerAi, tmdb: tmdb);
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    _changes.cancel();
    super.dispose();
  }
}

enum HostKey {
  spoilerAi('防剧透 AI API key', SettingsSection.danmaku, '防剧透 ai api key 密钥'),
  tmdb('TMDB API key', SettingsSection.accounts, 'tmdb api key 密钥 海报 元数据');

  const HostKey(this.title, this.section, this.words);
  final String title;
  final SettingsSection section;

  /// What a search finds it by.
  final String words;

  bool setIn(UiHostKeys keys) => switch (this) {
        spoilerAi => keys.spoilerAi,
        tmdb => keys.tmdb,
      };
}

/// One key: “已设置” when it is, a field to replace it, and 清除 (twice).
class HostKeyRow extends StatefulWidget {
  const HostKeyRow({super.key, required this.keys, required this.which});
  final HostKeys keys;
  final HostKey which;

  @override
  State<HostKeyRow> createState() => _HostKeyRowState();
}

class _HostKeyRowState extends State<HostKeyRow> {
  String? _error;

  Future<void> _set(String key) async {
    setState(() => _error = null);
    try {
      await switch (widget.which) {
        HostKey.spoilerAi => widget.keys.set(spoilerAi: key),
        HostKey.tmdb => widget.keys.set(tmdb: key),
      };
    } catch (e) {
      if (mounted) setState(() => _error = callFailure(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.keys,
        builder: (context, _) {
          final keys = widget.keys.value;
          final set = keys != null && widget.which.setIn(keys);
          return SettingsRow(
            title: widget.which.title,
            subtitle: _error,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              FieldControl(
                value: '',
                obscure: true,
                width: 220,
                hint: set
                    ? '已设置'
                    : widget.which == HostKey.tmdb && BuiltInCredentials.hasTmdb
                        ? '使用自带的'
                        : null,
                onCommit: (v) {
                  if (v.trim().isNotEmpty) _set(v.trim());
                },
              ),
              if (set) ...[
                const SizedBox(width: 8),
                ConfirmPill(
                    label: '清除', confirm: '确定清除', onConfirm: () => _set('')),
              ],
            ]),
          );
        },
      );
}
