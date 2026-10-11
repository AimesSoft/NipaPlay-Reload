import 'package:nipaplay/src/rust/api/vault.dart' as native;
import 'package:nipaplay/src/rust/rust_init.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'credential_vault.dart';
import 'package:nipaplay/utils/lab_profile.dart';
import 'package:flutter/services.dart';

final class DesktopCredentialVault implements CredentialVault {
  Future<T?> _labCall<T>(String operation, CredentialRef ref, [String? secret]) async {
    try {
      return await const MethodChannel('security_bookmark').invokeMethod<T>('labVault', {
        'operation': operation, 'namespace': ref.namespace, 'key': ref.key,
        if (secret != null) 'secret': secret,
      });
    } on PlatformException catch (error) {
      throw StateError(error.code);
    }
  }
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
    if (LabProfile.active) return _labCall<String>('read', ref);
    return _call(
        () => native.vaultRead(namespace: ref.namespace, key: ref.key));
  }

  @override
  Future<void> write(CredentialRef ref, String secret) async {
    if (LabProfile.active) {
      await _labCall<void>('write', ref, secret);
      return;
    }
    await _call(() => native.vaultWrite(
        namespace: ref.namespace, key: ref.key, secret: secret));
  }

  @override
  Future<void> delete(CredentialRef ref) async {
    if (LabProfile.active) {
      await _labCall<void>('delete', ref);
      return;
    }
    await _call(
        () => native.vaultDelete(namespace: ref.namespace, key: ref.key));
  }
}
