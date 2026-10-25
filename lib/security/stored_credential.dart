import 'credential_store.dart';
import 'credential_vault.dart';

/// Metadata can be loaded and saved while its credential remains unresolved.
final class StoredCredential {
  StoredCredential(String? value)
      : _value = value,
        ref = null;
  StoredCredential.fromJson(Object? json, CredentialRef expected)
      : ref = credentialReference(json),
        _value = json is String ? json : null {
    if ((json != null && json is! String && ref == null) ||
        (ref != null && ref != expected)) {
      throw StateError('invalid_reference');
    }
  }
  final CredentialRef? ref;
  String? _value;
  String? get value => _value;
  Object? toJson() => ref?.placeholder ?? _value;

  /// The reference points at an entry the vault turned out not to hold; the
  /// owner has to be given the secret again.
  bool get missing =>
      ref != null &&
      _value == null &&
      CredentialStore.instance.missing.value.contains(ref);

  /// Whether a secret is on record, by value or by reference. The vault is
  /// not read: a reference whose entry has gone shows up once it is used.
  Future<bool> exists() async {
    final held = _value;
    if (held != null) return held.isNotEmpty;
    return ref != null && !missing;
  }

  Future<String?> resolve() async {
    if (ref != null && _value == null) {
      _value = await CredentialStore.instance.vault.read(ref!);
      if (_value == null) {
        final error = StateError('credential_missing');
        CredentialStore.instance.report(ref!, error);
        throw error;
      }
    }
    return _value;
  }
}
