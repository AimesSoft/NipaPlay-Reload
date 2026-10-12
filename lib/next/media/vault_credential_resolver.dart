import 'dart:convert';
import 'dart:io';
import 'metadata_provider.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_file_migration.dart';
import 'package:nipaplay/security/secret_redactor.dart';

final class VaultCredentialResolver implements CredentialResolver {
  VaultCredentialResolver(this.root, {CredentialStore? store})
      : store = store ?? CredentialStore.instance;
  final Directory root;
  final CredentialStore store;
  @override
  Future<String> resolve(CredentialRef ref) async {
    await migrateCredentialFiles(root, store, only: ref);
    if (store.vault.blocked.containsKey(ref)) {
      throw StateError(store.vault.blocked[ref]!);
    }
    String? secret;
    final file = File('${root.path}/credentials.json');
    if (await file.exists()) {
      final values = jsonDecode(await file.readAsString()) as Map;
      // Keep using the old value if migration failed, including non-desktop.
      if (values[ref.key] is String) secret = values[ref.key] as String;
    }
    secret ??= await store.vault.read(ref);
    if (secret == null || secret.isEmpty) {
      throw Failure(FailureCode.unavailable, '$ref is not configured.');
    }
    SecretRedactor.remember(ref, secret);
    return secret;
  }
}
