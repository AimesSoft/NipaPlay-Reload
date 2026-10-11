import 'dart:convert';
import 'dart:io';
import 'credential_store.dart';
import 'credential_vault.dart';

Future<void> migrateCredentialFiles(
    Directory root, CredentialStore store, {CredentialRef? only}) async {
  if (!store.desktop) return;
  for (final name in ['credentials.json', 'endpoint.json']) {
    final file = File('${root.path}/$name');
    if (!await file.exists()) continue;
    try {
      final values = Map<String, dynamic>.from(
          jsonDecode(await file.readAsString()) as Map);
      for (final key in values.keys.toList()) {
        final secret = values[key];
        if (secret is! String) continue;
        final ref =
            CredentialRef(name == 'endpoint.json' ? 'agent' : 'metadata', key);
        if (only != null && ref != only) continue;
        try {
          await store.verifiedWrite(ref, secret);
          values[key] = ref.placeholder;
          final pending = File('${file.path}.vault-tmp');
          // The temporary file may still contain entries whose migration failed.
          await pending.writeAsString('');
          if (!Platform.isWindows) {
            final result = await Process.run('chmod', ['600', pending.path]);
            if (result.exitCode != 0) {
              throw StateError('file_permissions_failed');
            }
          } else {
            final result = await Process.run('powershell.exe', [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              r'''$ErrorActionPreference = 'Stop';
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User;
$acl = [System.Security.AccessControl.FileSecurity]::new();
$acl.SetOwner($sid);
$acl.SetAccessRuleProtection($true, $false);
$acl.SetAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'Allow'));
Set-Acl -LiteralPath $env:NIPAPLAY_CREDENTIAL_PATH -AclObject $acl;'''
            ], environment: {
              'NIPAPLAY_CREDENTIAL_PATH': pending.path
            });
            if (result.exitCode != 0) {
              throw StateError('file_permissions_failed');
            }
          }
          await pending.writeAsString(jsonEncode(values), flush: true);
          await pending.rename(file.path);
        } catch (error) {
          values[key] = secret;
          final pending = File('${file.path}.vault-tmp');
          if (await pending.exists()) await pending.delete();
          store.report(ref, error);
        }
      }
    } catch (error) {
      store.report(CredentialRef('migration', name), error);
    }
  }
}
