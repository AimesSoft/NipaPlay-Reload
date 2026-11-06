import 'dart:io';
import 'dart:convert';

import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/utils/platform_identity.dart' as platform;

/// Small installation records survive a tvOS cache purge. The database,
/// catalogues, routes, replay log and artwork remain disposable files.
/// No whole database, catalogue or media payload is stored in the Keychain.
abstract final class TelevisionStorage {
  /// iOS-family containers may move after an update. Rebase only our image
  /// caches; a purged image is absent and must not prevent catalogue reads.
  static Future<String?> cachedArtwork(Directory root, String path) async {
    if (await File(path).exists()) return path;
    for (final folder in ['source-artwork', 'artwork']) {
      final marker = '/$folder/';
      final at = path.lastIndexOf(marker);
      if (at < 0) continue;
      final name = path.substring(at + marker.length);
      if (name.isEmpty || name.contains('/') || name == '..') return null;
      final file = File('${root.path}/$folder/$name');
      return await file.exists() ? file.path : null;
    }
    return null;
  }

  static const records = {
    'mesh-install-id',
    'device.json',
    'mesh.json',
    'mesh-certificate.json',
    'mesh-dev-ca.pem',
    'nipa-peer.json',
  };

  static CredentialRef _ref(String name) =>
      CredentialRef('tvos-installation', name);

  static Future<void> restore(Directory root, CredentialVault vault,
      {bool? television}) async {
    if (!(television ?? platform.isTvOS)) return;
    await root.create(recursive: true);
    for (final name in records) {
      final file = File('${root.path}/$name');
      final content = await vault.read(_ref(name));
      if (content == '') {
        // A durable tombstone also covers a crash before the cached deletion.
        if (await file.exists()) await file.delete();
      } else if (content != null) {
        // The durable write commits first. A crash before the cache rename
        // must not let an older cached file roll the installation back.
        await file.writeAsString(content, flush: true);
      } else if (await file.exists()) {
        // First entry also enrolls deliberately seeded Debug configs.
        await save(name, await file.readAsString(), vault, television: true);
      }
    }
  }

  static Future<void> save(String name, String? content, CredentialVault vault,
      {bool? television}) async {
    if (!(television ?? platform.isTvOS) || !records.contains(name)) return;
    final value = content ?? '';
    // Configuration is bounded; accidentally passing a catalogue is an error.
    if (utf8.encode(value).length > 64 * 1024) {
      throw StateError('television_record_too_large');
    }
    await vault.write(_ref(name), value);
    if (await vault.read(_ref(name)) != value) {
      throw StateError('television_record_readback_failed');
    }
  }
}
