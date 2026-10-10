import 'package:nipaplay/security/credential_vault.dart';

final class MemoryVault implements CredentialVault {
  final values = <CredentialRef, String>{};
  CredentialRef? failWrite;
  CredentialRef? mismatch;
  bool unavailable = false;
  @override
  Future<String?> read(CredentialRef ref) async {
    if (unavailable) throw StateError('system_vault_unavailable');
    if (ref == mismatch) return 'mismatch';
    return values[ref];
  }

  @override
  Future<void> write(CredentialRef ref, String secret) async {
    if (unavailable || ref == failWrite) {
      throw StateError('system_vault_unavailable');
    }
    values[ref] = secret;
  }

  @override
  Future<void> delete(CredentialRef ref) async {
    if (unavailable) throw StateError('system_vault_unavailable');
    values.remove(ref);
  }
}
