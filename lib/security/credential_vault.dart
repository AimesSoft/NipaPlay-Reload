import 'package:nipa_harness/nipa_harness.dart';

/// Safe to persist, log and back up. The secret is owned by the backend.
final class CredentialRef implements JsonEncodable {
  const CredentialRef(this.namespace, this.key);
  final String namespace;
  final String key;

  factory CredentialRef.fromJson(Map<String, Object?> json) =>
      CredentialRef(json['namespace'] as String, json['key'] as String);
  @override
  JsonMap toJson() => {'namespace': namespace, 'key': key};
  JsonMap get placeholder => {'credentialRef': toJson()};
  @override
  String toString() => 'CredentialRef($namespace, $key)';
  @override
  bool operator ==(Object other) =>
      other is CredentialRef &&
      namespace == other.namespace &&
      key == other.key;
  @override
  int get hashCode => Object.hash(namespace, key);
}

abstract interface class CredentialVault {
  Future<String?> read(CredentialRef ref);
  Future<void> write(CredentialRef ref, String secret);
  Future<void> delete(CredentialRef ref);
}

CredentialRef? credentialReference(Object? value) {
  if (value is! Map || value.length != 1 || value['credentialRef'] is! Map) {
    return null;
  }
  final ref = value['credentialRef'] as Map;
  if (ref['namespace'] is! String || ref['key'] is! String) return null;
  return CredentialRef(ref['namespace'] as String, ref['key'] as String);
}
