import '../../services/app_http_proxy.dart';
import 'dart:convert';
import 'dart:io';

/// Only the existing router's non-secret preferences, in the isolated host root.
/// This is not a replacement for application preferences or a credential store.
final class SharedPreferences {
  SharedPreferences._(this.file, this._values);
  final File file;
  final Map<String, Object?> _values;
  Future<void> _tail = Future.value();
  static SharedPreferences? _instance;
  static Future<void> configure(Directory root) async {
    final file = File('${root.path}/network.json');
    final values = await file.exists()
        ? Map<String, Object?>.from(
            jsonDecode(await file.readAsString()) as Map)
        : <String, Object?>{};
    const allowed = {
      'dandanplay_server_url',
      'dandanplay_server_mode',
      'bangumi_server_url',
      'nipaplay_auto_region',
      'nipaplay_auto_region_at',
      'nipaplay_failover_server',
      'nipaplay_failover_until',
      'player_http_proxy'
    };
    if (values.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException(
          'network.json only accepts routing preferences.');
    }
    final custom = values['dandanplay_server_url'];
    if (custom != null) {
      final uri = custom is String ? Uri.tryParse(custom) : null;
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const FormatException(
            'Gateway must be an origin/path without credentials.');
      }
    }
    final proxy = (values['player_http_proxy'] as String? ?? '').trim();
    AppHttpProxy.set(proxy);
    _instance = SharedPreferences._(file, values);
  }

  static Future<SharedPreferences> getInstance() async =>
      _instance ??
      (throw StateError('Headless routing root is not configured.'));
  String? getString(String key) => _values[key] as String?;
  int? getInt(String key) => _values[key] as int?;
  Set<String> getKeys() => _values.keys.toSet();
  Future<bool> setString(String key, String value) => _save(key, value);
  Future<bool> setInt(String key, int value) => _save(key, value);
  Future<bool> remove(String key) => _save(key, null);
  Future<bool> _save(String key, Object? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    final snapshot = jsonEncode(_values);
    final operation = _tail.then((_) async {
      final pending = File('${file.path}.pending');
      await pending.writeAsString(snapshot, flush: true);
      await pending.rename(file.path);
    });
    _tail = operation.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    await operation;
    return true;
  }
}
