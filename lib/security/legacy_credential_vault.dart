import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'credential_vault.dart';

/// Backend slot for mobile, TV, HarmonyOS and Web until their native migration.
final class LegacyCredentialVault implements CredentialVault {
  String _key(CredentialRef ref) =>
      'credential_vault_${jsonEncode(ref.toJson())}';
  @override
  Future<String?> read(CredentialRef ref) async =>
      (await SharedPreferences.getInstance()).getString(_key(ref));
  @override
  Future<void> write(CredentialRef ref, String secret) async {
    if (!await (await SharedPreferences.getInstance())
        .setString(_key(ref), secret)) {
      throw StateError('legacy_vault_write_failed');
    }
  }

  @override
  Future<void> delete(CredentialRef ref) async {
    if (!await (await SharedPreferences.getInstance()).remove(_key(ref))) {
      throw StateError('legacy_vault_delete_failed');
    }
  }
}
