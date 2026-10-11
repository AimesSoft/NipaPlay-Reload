import 'credential_vault.dart';
import 'secret_redactor.dart';

/// One authorization refusal applies to the whole process, including callers
/// that use the vault directly rather than the preferences adapter.
final class SessionCredentialVault implements CredentialVault {
  SessionCredentialVault(this.backend, this.failed, this.recovered);
  final CredentialVault backend;
  final void Function(CredentialRef, Object) failed;
  final void Function(CredentialRef) recovered;
  final Map<CredentialRef, String> blocked = {};
  final Map<CredentialRef, Future<String?>> _reads = {};

  void allowRetry(CredentialRef ref) => blocked.remove(ref);

  Future<T> _call<T>(CredentialRef ref, Future<T> Function() operation) async {
    final reason = blocked[ref];
    if (reason != null) throw StateError(reason);
    try {
      return await operation();
    } catch (error) {
      if (error is StateError &&
          const {
            'storage_access_denied',
            'storage_authorization_cancelled',
            'storage_interaction_required'
          }.contains(error.message)) {
        blocked[ref] = error.message.toString();
      }
      failed(ref, error);
      rethrow;
    }
  }

  @override
  Future<String?> read(CredentialRef ref) {
    return _reads.putIfAbsent(ref, () async {
      try {
        final value = await _call(ref, () => backend.read(ref));
        if (value != null) SecretRedactor.remember(ref, value);
        recovered(ref);
        return value;
      } finally {
        _reads.remove(ref);
      }
    });
  }

  @override
  Future<void> write(CredentialRef ref, String secret) =>
      _call(ref, () => backend.write(ref, secret));

  @override
  Future<void> delete(CredentialRef ref) async {
    await _call(ref, () => backend.delete(ref));
    recovered(ref);
  }
}
