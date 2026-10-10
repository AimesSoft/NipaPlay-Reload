import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> writeEndpointFile(File file, Uri url, String token) async {
  await file.parent.create(recursive: true);
  final staging = await file.parent.createTemp('.endpoint-');
  try {
    final pending = File(p.join(staging.path, 'endpoint.json'));
    await pending.writeAsString('');
    final ProcessResult permissions;
    if (Platform.isWindows) {
      permissions = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''$ErrorActionPreference = 'Stop';
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User;
$acl = [System.Security.AccessControl.FileSecurity]::new();
$acl.SetOwner($sid);
$acl.SetAccessRuleProtection($true, $false);
$acl.SetAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'Allow'));
Set-Acl -LiteralPath $env:NIPAPLAY_ENDPOINT_FILE -AclObject $acl;'''
      ], environment: {
        'NIPAPLAY_ENDPOINT_FILE': pending.path
      });
    } else {
      permissions = await Process.run('chmod', ['600', pending.path]);
    }
    if (permissions.exitCode != 0) {
      throw StateError(
          'Cannot restrict endpoint credentials to the current user.');
    }
    await pending.writeAsString(
        jsonEncode({'url': url.toString(), 'token': token}),
        flush: true);
    await pending.rename(file.path);
  } finally {
    await staging.delete(recursive: true);
  }
}
