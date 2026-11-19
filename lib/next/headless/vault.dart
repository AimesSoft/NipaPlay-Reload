import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../../security/credential_vault.dart';
import '../../security/secret_redactor.dart';
import '../system/credential_changes.dart';

/// Host-only private credential files, never registered as an Action or setting.
final class HeadlessVault implements CredentialVault {
  HeadlessVault(this.directory);
  final Directory directory;
  Future<void>? _ready;
  Future<void> initialize() => _ready ??= _initialize();
  Future<void> _initialize() async {
    await directory.create(recursive: true);
    final ProcessResult result;
    if (Platform.isWindows) {
      final user = '${Platform.environment['USERDOMAIN']}\\${Platform.environment['USERNAME']}';
      result = await Process.run('icacls', [directory.path, '/inheritance:r', '/grant:r', '$user:(OI)(CI)F']);
    } else {
      result = await Process.run('chmod', ['700', directory.path]);
    }
    if (result.exitCode != 0) throw StateError('headless_vault_permissions_failed');
    await _rememberAll();
  }

  /// Every stored value is known to the redactor from the start, not only
  /// once read: what a tool prints of one is hidden even if NipaPlay has
  /// not used it in this run (#1119).
  Future<void> _rememberAll() async {
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final stored = jsonDecode(await entity.readAsString()) as Map;
        final ref = stored['ref'], secret = stored['secret'];
        if (ref is Map && secret is String) {
          SecretRedactor.remember(
              CredentialRef.fromJson(ref.cast<String, Object?>()), secret);
        }
      } on Object {
        // A damaged file holds nothing to hide; reading it stays an error.
      }
    }
  }
  File _file(CredentialRef ref) => File('${directory.path}/${sha256.convert(utf8.encode(jsonEncode(ref.toJson())))}.json');
  @override
  Future<String?> read(CredentialRef ref) async {
    await initialize();
    final file = _file(ref);
    if (!await file.exists()) return null;
    final secret = (jsonDecode(await file.readAsString()) as Map)['secret'] as String;
    SecretRedactor.remember(ref, secret);
    return secret;
  }
  @override
  Future<void> write(CredentialRef ref, String secret) async {
    await initialize();
    final file = _file(ref);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode({'ref': ref.toJson(), 'secret': secret}), flush: true);
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['600', pending.path]);
      if (result.exitCode != 0) throw StateError('headless_vault_permissions_failed');
    }
    await pending.rename(file.path);
    SecretRedactor.remember(ref, secret);
    CredentialChanges.committed(ref);
  }
  @override
  Future<void> delete(CredentialRef ref) async {
    await initialize();
    final file = _file(ref);
    if (await file.exists()) await file.delete();
    CredentialChanges.committed(ref);
  }
}
