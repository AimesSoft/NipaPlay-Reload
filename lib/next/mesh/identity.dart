import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'native.dart';

final class MeshIdentity {
  MeshIdentity._(
      this.ref, this.publicKey, this.deviceId, this.vault, this.native);
  final CredentialRef ref;
  final String publicKey, deviceId;
  final CredentialVault vault;
  final MeshNative native;

  static Future<MeshIdentity> load(
      Directory root, CredentialVault vault, MeshNative native) async {
    await root.create(recursive: true);
    // A distinct installation directory also gets a distinct Keychain entry.
    final ref = CredentialRef(
        'mesh', sha256.convert(utf8.encode(root.absolute.path)).toString());
    var key = await vault.read(ref);
    if (key == null) {
      if (await File('${root.path}/mesh-identity.json').exists()) {
        throw StateError(
            'Mesh private key is missing; restore credentials before joining.');
      }
      key = await native.generateKey();
      await vault.write(ref, key);
      if (await vault.read(ref) != key) {
        throw StateError('Mesh identity vault verification failed.');
      }
    } else {
      // Initialize the native runtime even when the key already exists.
      await native.ready();
    }
    final public = await native.publicKey(key);
    final id = base64Url
        .encode(
            sha256.convert(base64Url.decode(base64Url.normalize(public))).bytes)
        .replaceAll('=', '');
    final file = File('${root.path}/mesh-identity.json');
    if (await file.exists()) {
      final previous = jsonDecode(await file.readAsString()) as Map;
      if (previous['deviceId'] != id) {
        throw StateError(
            'Mesh identity vault entry does not match installation.');
      }
    }
    await file.writeAsString(
        jsonEncode({
          'deviceId': id,
          'publicKey': public,
          'privateKey': ref.placeholder
        }),
        flush: true);
    return MeshIdentity._(ref, public, id, vault, native);
  }

  Future<String> privateKey() async {
    final value = await vault.read(ref);
    if (value == null) {
      throw StateError('Mesh private key is missing from vault.');
    }
    return value;
  }

  Future<Map<String, Object?>> proof(
      List<String> fields, String nonce, int timestamp) async {
    final message = jsonEncode([
      'nipaplay-mesh-possession-v1',
      timestamp.toString(),
      nonce,
      ...fields
    ]);
    return {
      'timestamp': timestamp,
      'nonce': nonce,
      'signature': await native.sign(await privateKey(), message)
    };
  }
}
