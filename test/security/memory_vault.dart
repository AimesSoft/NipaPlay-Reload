import 'package:nipaplay/security/credential_vault.dart';

final class MemoryVault implements CredentialVault {
  final values = <CredentialRef, String>{};
  CredentialRef? failWrite;
  CredentialRef? mismatch;
  bool unavailable = false;
  CredentialRef? denied;
  String refusal = 'storage_access_denied';
  final reads = <CredentialRef, int>{};
  final writes = <CredentialRef, int>{};
  @override
  Future<String?> read(CredentialRef ref) async {
    reads.update(ref, (count) => count + 1, ifAbsent: () => 1);
    if (ref == denied) throw StateError(refusal);
    if (unavailable) throw StateError('system_vault_unavailable');
    if (ref == mismatch) return 'mismatch';
    return values[ref];
  }

  @override
  Future<void> write(CredentialRef ref, String secret) async {
    writes.update(ref, (count) => count + 1, ifAbsent: () => 1);
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
