import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'credential_vault.dart';
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
  final ValueNotifier<List<String>> notices = ValueNotifier(const []);
  final Map<CredentialRef, String> failures = {};
  static const scalarKeys = {
    'dandanplay_token',
    'dandanplay_app_secret',
    'bangumi_access_token',
    'dandanplay_remote_api_token',
    'incremental_sync_webdav_password',
    'emby_access_token',
    'jellyfin_access_token',
    'spoiler_ai_api_key',
  };
  static const compositeKeys = {
    'webdav_connections': 'password',
    'smb_connections': 'password',
    'server_profiles': 'accessToken',
  };
  static bool isSecretKey(String key) =>
      scalarKeys.contains(key) ||
      key.startsWith('plugin_text_setting_') ||
      (key.startsWith('plugin_') &&
          !key.startsWith('plugin_switch_setting_')) ||
      key.startsWith('credential_vault_');
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
    failures[ref] =
        codes.contains(reason) ? reason : error.runtimeType.toString();
    debugPrint('[CredentialVault] $ref: ${failures[ref]}');
    _refreshNotices();
  }

  void _recovered(CredentialRef ref) {
    if (failures.remove(ref) != null) _refreshNotices();
  }

  void _refreshNotices() {
    final guidance = switch (platform) {
      TargetPlatform.macOS => '请在 macOS 钥匙串访问中检查此条目的访问权限。',
      TargetPlatform.linux => '请启动并解锁 Secret Service（GNOME Keyring/KWallet）。',
      TargetPlatform.windows => '请检查 Windows 凭据管理器的访问权限。',
      _ => '请检查系统凭据存储的访问权限。',
    };
    notices.value = [
      if (failures.isNotEmpty) '凭据访问或迁移失败。$guidance 现有凭据已保留；未回落到明文存储。',
      for (final entry in failures.entries)
        vault.blocked.containsKey(entry.key)
            ? '${entry.key}: ${switch (entry.value) {
                'storage_authorization_cancelled' => '授权已取消',
                'storage_interaction_required' => '系统禁止授权交互',
                _ => '访问被拒绝',
              }}；本次运行已停止自动重试，可主动重试。'
            : '${entry.key}: ${entry.value}',
    ];
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
    if (!isSecretKey(key)) return raw;
    final ref = _decodeRef(raw);
    if (ref == preferenceRef(key)) return _readRef(ref!);
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
      return prefs.setString(key, value);
    }
    try {
      final retired = <CredentialRef>{};
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
      } else if (isSecretKey(key)) {
        final ref = preferenceRef(key);
        await verifiedWrite(ref, value);
        value = jsonEncode(ref.placeholder);
      }
      if (!await prefs.setString(key, value)) {
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
      return await prefs.remove(key);
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

  /// Portable export never resolves a reference, including failed migrations.
  Object? exportPreference(String key, Object? value) {
    if (value == null) return null;
    if (isSecretKey(key)) return preferenceRef(key).placeholder;
    if (compositeKeys.containsKey(key) && value is String) {
      return jsonEncode(exportItems(key, jsonDecode(value) as List));
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
