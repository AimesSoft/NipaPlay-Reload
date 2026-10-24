import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'credential_vault.dart';

/// The iOS vault: the Keychain (`AfterFirstUnlockThisDeviceOnly`, not backed
/// up to another device, not synchronized to iCloud; see NipaKeychain.swift).
///
/// What the previous iOS vault kept as plain preferences moves here the first
/// time it is read: written to the Keychain, read back, and only then removed
/// from the preferences.
final class KeychainCredentialVault implements CredentialVault {
  KeychainCredentialVault({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('nipaplay/keychain');
  final MethodChannel _channel;

  static String legacyKey(CredentialRef ref) =>
      'credential_vault_${jsonEncode(ref.toJson())}';

  Map<String, Object?> _arguments(CredentialRef ref, [String? secret]) => {
        'namespace': ref.namespace,
        'key': ref.key,
        if (secret != null) 'secret': secret,
      };

  Future<T?> _call<T>(String method, CredentialRef ref, [String? secret]) async {
    try {
      return await _channel.invokeMethod<T>(method, _arguments(ref, secret));
    } on PlatformException catch (error) {
      throw StateError(error.code);
    } on MissingPluginException {
      throw StateError('system_vault_unavailable');
    }
  }

  @override
  Future<String?> read(CredentialRef ref) async {
    final stored = await _call<String>('read', ref);
    if (stored != null) return stored;
    final preferences = await SharedPreferences.getInstance();
    final legacy = preferences.getString(legacyKey(ref));
    if (legacy == null) return null;
    await _call<void>('write', ref, legacy);
    if (await _call<String>('read', ref) != legacy) {
      throw StateError('vault_readback_mismatch');
    }
    await preferences.remove(legacyKey(ref));
    return legacy;
  }

  @override
  Future<void> write(CredentialRef ref, String secret) async {
    await _call<void>('write', ref, secret);
    final preferences = await SharedPreferences.getInstance();
    if (preferences.containsKey(legacyKey(ref))) {
      await preferences.remove(legacyKey(ref));
    }
  }

  @override
  Future<void> delete(CredentialRef ref) async {
    await _call<void>('delete', ref);
    final preferences = await SharedPreferences.getInstance();
    if (preferences.containsKey(legacyKey(ref))) {
      await preferences.remove(legacyKey(ref));
    }
  }
}
