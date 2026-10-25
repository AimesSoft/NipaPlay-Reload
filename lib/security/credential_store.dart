import 'package:nipa_harness/nipa_harness.dart' show JsonMap;
import 'package:nipaplay/next/settings/registry.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/lab_profile.dart';
import 'credential_vault.dart';
import 'credential_key_policy.dart';
import 'secret_redactor.dart';
import 'vault_backend.dart';
import 'session_credential_vault.dart';

/// Adapts verified legacy storage keys without exposing secrets to serializers.
final class CredentialStore {
  CredentialStore(CredentialVault backend,
      {required this.desktop, TargetPlatform? platform})
      : platform = platform ?? defaultTargetPlatform {
    vault = SessionCredentialVault(backend, report, _recovered);
  }
  static var instance =
      CredentialStore(createCredentialVault(), desktop: usesSystemVault);
  late final SessionCredentialVault vault;
  final bool desktop;
  final TargetPlatform platform;
  /// Lines of the app-wide banner. Only the vault as a whole belongs here; an
  /// entry that is simply gone is [missing] and shows where it is used.
  final ValueNotifier<List<String>> notices = ValueNotifier(const []);

  /// Banner lines the user closed during this run.
  final ValueNotifier<Set<String>> dismissed = ValueNotifier(const {});

  /// Entries a reference points at that the vault no longer holds. Each belongs
  /// to one connection or account, which asks for the secret again.
  final ValueNotifier<Set<CredentialRef>> missing = ValueNotifier(const {});
  final Map<CredentialRef, String> failures = {};

  /// Failures that mean the vault cannot be used at all, not one entry.
  static const _vaultWide = {
    'system_vault_unavailable',
    'unsupported_platform',
    'file_permissions_failed',
    'vault_operation_failed',
    'storage_access_denied',
    'storage_authorization_cancelled',
    'storage_interaction_required',
  };
  static const scalarKeys = CredentialKeyPolicy.scalarKeys;
  static const compositeKeys = CredentialKeyPolicy.compositeKeys;
  static bool isSecretKey(String key) => CredentialKeyPolicy.isSecretKey(key);
  static CredentialRef preferenceRef(String key) =>
      key.startsWith('credential_vault_')
          ? CredentialRef.fromJson(Map<String, Object?>.from(
              jsonDecode(key.substring('credential_vault_'.length)) as Map))
          : CredentialRef('preferences', key);
  static CredentialRef itemRef(String key, Map item) => CredentialRef(
      key,
      item['id'] as String? ??
          sha256
              .convert(utf8.encode(jsonEncode([
                item['host'] ?? item['url'],
                item['username'],
                item['domain'],
                item['port']
              ])))
              .toString());

  void report(CredentialRef ref, Object error) {
    // Exception text from external backends must never be persisted verbatim.
    const codes = {
      'invalid_reference',
      'storage_access_denied',
      'storage_authorization_cancelled',
      'storage_interaction_required',
      'credential_missing',
      'system_vault_unavailable',
      'ambiguous_reference',
      'vault_operation_failed',
      'unsupported_platform',
      'vault_readback_mismatch',
      'preferences_write_failed',
      'file_permissions_failed'
    };
    final reason =
        error is StateError ? error.message.toString() : error.toString();
    if (reason == 'credential_missing') {
      if (missing.value.contains(ref)) return;
      missing.value = {...missing.value, ref};
      debugPrint('[CredentialVault] $ref: credential_missing');
      _refreshNotices();
      return;
    }
    failures[ref] =
        codes.contains(reason) ? reason : error.runtimeType.toString();
    debugPrint('[CredentialVault] $ref: ${failures[ref]}');
    _refreshNotices();
  }

  void _recovered(CredentialRef ref) {
    final hadMissing = missing.value.contains(ref);
    if (hadMissing) missing.value = {...missing.value}..remove(ref);
    if (failures.remove(ref) != null || hadMissing) _refreshNotices();
  }

  /// Closes the banner as it reads now; a different problem shows it again.
  void dismiss() => dismissed.value = {...dismissed.value, ...notices.value};

  /// Asks again for every entry the vault refused or could not reach.
  Future<void> retryVault() async {
    for (final entry in failures.entries.toList()) {
      if (!_vaultWide.contains(entry.value) && entry.key.namespace != 'vault') {
        continue;
      }
      try {
        await retry(entry.key);
      } catch (_) {
        // The store publishes the new outcome.
      }
    }
  }

  void _refreshNotices() {
    final wide = failures.entries.any((entry) =>
        _vaultWide.contains(entry.value) || entry.key.namespace == 'vault');
    notices.value = [
      if (wide)
        if (LabProfile.active)
          '无法访问实验凭据文件。'
        else
          switch (platform) {
            TargetPlatform.macOS => '无法访问钥匙串，已保存的密码暂时不能使用。',
            TargetPlatform.linux => '系统密钥环未解锁，已保存的密码暂时不能使用。',
            TargetPlatform.windows => '无法访问 Windows 凭据管理器，已保存的密码暂时不能使用。',
            _ => '无法访问系统凭据存储，已保存的密码暂时不能使用。',
          },
    ];
  }

  static String _kindLabel(CredentialRef ref, Map? item) =>
      switch (ref.namespace) {
        'smb_connections' => 'SMB 连接',
        'webdav_connections' => 'WebDAV 连接',
        'server_profiles' =>
          item?['serverType'] == 'emby' ? 'Emby 服务器' : 'Jellyfin 服务器',
        'shared_remote_hosts' => '共享媒体库',
        _ => '账号',
      };

  /// What is missing, in words and with the owner's name; never a secret.
  Future<List<JsonMap>> missingEntries(SharedPreferences prefs) async {
    final result = <JsonMap>[];
    for (final ref in missing.value) {
      Map? owner;
      if (compositeKeys.containsKey(ref.namespace)) {
        final raw = prefs.getString(ref.namespace);
        if (raw != null) {
          try {
            for (final item in (jsonDecode(raw) as List).cast<Map>()) {
              if (itemRef(ref.namespace, item) == ref) owner = item;
            }
          } on FormatException {
            // An unreadable list has no owner to name.
          }
        }
      }
      final name = owner?['name'] as String?;
      final kind = _kindLabel(ref, owner);
      result.add({
        'reference': ref.toJson(),
        'kind': kind,
        'name': name,
        'notice': name == null || name.isEmpty
            ? '$kind需要重新输入密码'
            : '$kind「$name」需要重新输入密码',
      });
    }
    return result;
  }

  /// Explicit UI/Agent operation; it never exports the resolved secret.
  Future<bool> retry(CredentialRef ref) async {
    vault.allowRetry(ref);
    return await _readRef(ref) != null;
  }

  Future<void> verifiedWrite(CredentialRef ref, String secret) async {
    SecretRedactor.remember(ref, secret);
    await vault.write(ref, secret);
    if (await vault.read(ref) != secret) {
      throw StateError('vault_readback_mismatch');
    }
    _recovered(ref);
  }

  Future<void> checkAvailability() async {
    if (!desktop) return;
    const ref = CredentialRef('vault', 'availability');
    try {
      await vault.read(ref);
    } catch (error) {
      report(ref, error);
    }
  }

  Future<String?> read(SharedPreferences prefs, String key) async {
    final raw = prefs.getString(key);
    if (raw == null) return null;
    if (compositeKeys.containsKey(key)) {
      final items = jsonDecode(raw) as List;
      for (final item in items.cast<Map>()) {
        final field = compositeKeys[key]!;
        final ref = credentialReference(item[field]);
        if (desktop && ref != null) {
          if (ref != itemRef(key, item)) throw StateError('invalid_reference');
          item[field] =
              await _readRef(ref) ?? (field == 'password' ? '' : null);
        } else if (item[field] is String) {
          SecretRedactor.remember(itemRef(key, item), item[field] as String);
        }
      }
      return jsonEncode(items);
    }
    final ref = _decodeRef(raw);
    if (ref == preferenceRef(key)) return _readRef(ref!);
    if (!isSecretKey(key)) return raw;
    if (desktop) {
      try {
        await write(prefs, key, raw);
      } catch (error) {
        if (vault.blocked.containsKey(preferenceRef(key))) rethrow;
        // Keep the existing legacy value until a verified migration succeeds.
      }
    }
    SecretRedactor.remember(preferenceRef(key), raw);
    return raw; // A failed migration retains the working legacy value.
  }

  Future<String?> _readRef(CredentialRef ref) async {
    try {
      final value = await vault.read(ref);
      if (value != null) SecretRedactor.remember(ref, value);
      return value;
    } catch (error) {
      report(ref, error);
      rethrow;
    }
  }

  static CredentialRef? _decodeRef(String raw) {
    if (!raw.startsWith('{')) return null;
    try {
      return credentialReference(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<bool> write(SharedPreferences prefs, String key, String value) async {
    if (!desktop) {
      if (isSecretKey(key)) SecretRedactor.remember(preferenceRef(key), value);
      return SettingsAccess.persist(key, () => prefs.setString(key, value));
    }
    try {
      final retired = <CredentialRef>{};
      final previousValue = prefs.get(key);
      final storedRef = previousValue is String ? _decodeRef(previousValue) : null;
      if (compositeKeys.containsKey(key)) {
        final previous = prefs.getString(key);
        if (previous != null) {
          for (final item in (jsonDecode(previous) as List).cast<Map>()) {
            final ref = credentialReference(item[compositeKeys[key]]);
            if (ref != null && ref == itemRef(key, item)) retired.add(ref);
          }
        }
        final items = jsonDecode(value) as List;
        final field = compositeKeys[key]!;
        for (final item in items.cast<Map>()) {
          if (item[field] == null || credentialReference(item[field]) != null) {
            continue;
          }
          final ref = itemRef(key, item);
          await verifiedWrite(ref, item[field] as String);
          item[field] = ref.placeholder;
        }
        for (final item in items.cast<Map>()) {
          final ref = credentialReference(item[field]);
          if (ref != null) retired.remove(ref);
        }
        value = jsonEncode(items);
      } else if (isSecretKey(key) || storedRef == preferenceRef(key)) {
        final ref = preferenceRef(key);
        await verifiedWrite(ref, value);
        value = storedRef == ref
            ? previousValue as String
            : jsonEncode(ref.placeholder);
      }
      if (!await SettingsAccess.persist(key, () => prefs.setString(key, value))) {
        throw StateError('preferences_write_failed');
      }
      for (final ref in retired) {
        await vault.delete(ref);
      }
      return true;
    } catch (error) {
      report(preferenceRef(key), error);
      rethrow;
    }
  }

  Future<bool> delete(SharedPreferences prefs, String key) async {
    try {
      if (desktop && isSecretKey(key)) await vault.delete(preferenceRef(key));
      return await SettingsAccess.persist(key, () => prefs.remove(key));
    } catch (error) {
      report(preferenceRef(key), error);
      rethrow;
    }
  }

  Future<void> migrate(SharedPreferences prefs, {Set<String>? keys}) async {
    if (!desktop) return;
    for (final key in prefs.getKeys().toList()) {
      if (keys != null && !keys.contains(key)) continue;
      if (compositeKeys.containsKey(key)) {
        await _migrateItems(prefs, key);
      } else if (isSecretKey(key)) {
        final raw = prefs.get(key);
        if (raw is! String || _decodeRef(raw) == preferenceRef(key)) continue;
        try {
          await write(prefs, key, raw);
        } catch (error) {
          report(preferenceRef(key), error);
        }
      }
    }
    await prefs.setString(
        'vault_migration_failures_v1',
        jsonEncode([
          for (final entry in failures.entries)
            {'reference': entry.key.toJson(), 'reason': entry.value},
        ]));
  }

  Future<void> _migrateItems(SharedPreferences prefs, String key) async {
    try {
      final items = jsonDecode(prefs.getString(key)!) as List;
      final field = compositeKeys[key]!;
      for (final item in items.cast<Map>()) {
        final secret = item[field];
        if (secret is! String) continue;
        final ref = itemRef(key, item);
        try {
          await verifiedWrite(ref, secret);
          item[field] = ref.placeholder;
          if (!await prefs.setString(key, jsonEncode(items))) {
            item[field] = secret;
            throw StateError('preferences_write_failed');
          }
        } catch (error) {
          report(ref, error);
        }
      }
    } catch (error) {
      report(preferenceRef(key), error);
    }
  }

  /// Secrets travel as references; previously vaulted public text travels by value.
  Future<Object?> exportPreference(String key, Object? value) async {
    if (value == null) return null;
    if (isSecretKey(key)) return preferenceRef(key).placeholder;
    if (compositeKeys.containsKey(key) && value is String) {
      return jsonEncode(exportItems(key, jsonDecode(value) as List));
    }
    if (value is String) {
      final ref = _decodeRef(value);
      if (ref == preferenceRef(key)) {
        final resolved = await _readRef(ref!);
        if (resolved == null) throw StateError('credential_missing');
        return resolved;
      }
    }
    return value;
  }

  List<Map<String, dynamic>> exportItems(String key, List items) => [
        for (final source in items)
          <String, dynamic>{
            ...Map<String, dynamic>.from(source as Map),
            compositeKeys[key]!: source[compositeKeys[key]] == null
                ? null
                : itemRef(key, source).placeholder
          }
      ];
}
