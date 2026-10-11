import 'dart:convert';
import 'dart:io';
import 'credential_store.dart';
import 'credential_vault.dart';
import 'secret_redactor.dart';
import 'portable_credentials.dart';

/// Scrub host-owned diagnostics and cached sync state after legacy secrets have
/// been registered by migration. User-created backup archives stay untouched.
Future<void> migrateCredentialDiagnostics(
    Directory appRoot, Directory syncSupportRoot, CredentialStore store,
    {bool migrateCaches = true}) async {
  if (!store.desktop) return;
  final journal = File('${appRoot.path}/next/journal.jsonl');
  if (await journal.exists()) {
    try {
      final before = await journal.readAsString();
      final lines = const LineSplitter().convert(before);
      final after = [
        for (final line in lines)
          jsonEncode(SecretRedactor.json(jsonDecode(line)))
      ].join('\n');
      if ('$after\n' != before) await _replace(journal, '$after\n');
    } catch (error) {
      store.report(const CredentialRef('migration', 'journal'), error);
    }
  }
  final logs = Directory('${appRoot.path}/logs');
  if (await logs.exists()) {
    await for (final entity in logs.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.txt')) continue;
      try {
        final before = await entity.readAsString();
        final after = SecretRedactor.text(before);
        if (after != before) await _replace(entity, after);
      } catch (error) {
        store.report(const CredentialRef('migration', 'logs'), error);
      }
    }
  }
  if (!migrateCaches) return;
  final caches = Directory('${syncSupportRoot.path}/incremental_sync');
  if (await caches.exists()) {
    await for (final entity in caches.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.index.json')) continue;
      try {
        final before = Map<String, dynamic>.from(
            jsonDecode(await entity.readAsString()) as Map);
        final after = await sealPortableCredentials(before, store);
        if (jsonEncode(after) != jsonEncode(before)) {
          // Force the next sync to compare against the original remote snapshot.
          after['snapshotSha256'] = 'credential-migration-rebuild';
          await _replace(entity, jsonEncode(after));
        }
      } catch (error) {
        store.report(const CredentialRef('migration', 'sync-cache'), error);
      }
    }
  }
}

Future<void> _replace(File file, String contents) async {
  final pending = File('${file.path}.vault-tmp');
  try {
    await pending.writeAsString(contents, flush: true);
    await pending.rename(file.path);
  } finally {
    if (await pending.exists()) await pending.delete();
  }
}
