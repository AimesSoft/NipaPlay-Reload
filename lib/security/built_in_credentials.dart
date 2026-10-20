import 'credential_vault.dart';
import 'secret_redactor.dart';

/// Credentials NipaPlay itself holds, so a fresh install works without setup.
/// They are injected when the app is built and are never in the source; a
/// user's own key in the vault always wins.
abstract final class BuiltInCredentials {
  static const _tmdb = String.fromEnvironment('NIPAPLAY_TMDB_TOKEN');
  static const _tmdbRef = CredentialRef('metadata', 'tmdb');

  static bool get hasTmdb => _tmdb.isNotEmpty;

  static String? of(CredentialRef ref) {
    if (ref.namespace != _tmdbRef.namespace || ref.key != _tmdbRef.key) {
      return null;
    }
    if (_tmdb.isEmpty) return null;
    SecretRedactor.remember(const CredentialRef('builtin', 'tmdb'), _tmdb);
    return _tmdb;
  }
}
