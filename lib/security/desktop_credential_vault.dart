import 'package:nipaplay/src/rust/api/vault.dart' as native;
import 'package:nipaplay/src/rust/rust_init.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'credential_vault.dart';

final class DesktopCredentialVault implements CredentialVault {
  Future<T> _call<T>(Future<T> Function() operation) async {
    await ensureRustInitialized();
    try {
      return await operation();
    } on AnyhowException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<String?> read(CredentialRef ref) async {
    return _call(
        () => native.vaultRead(namespace: ref.namespace, key: ref.key));
  }

  @override
  Future<void> write(CredentialRef ref, String secret) async {
    await _call(() => native.vaultWrite(
        namespace: ref.namespace, key: ref.key, secret: secret));
  }

  @override
  Future<void> delete(CredentialRef ref) async {
    await _call(
        () => native.vaultDelete(namespace: ref.namespace, key: ref.key));
  }
}
