import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'credential_store.dart';
import 'credential_vault.dart';

/// URL credentials sometimes survive in historical playback paths and caches.
/// Keep their string shape for existing backup codecs, but persist only a ref.
Future<Map<String, dynamic>> sealPortableCredentials(
    Map<String, dynamic> data, CredentialStore store) async {
  Future<Object?> visit(Object? value, String path) async {
    if (credentialReference(value) != null) return value;
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key as String;
        final item = entry.value;
        if (item is String &&
            (CredentialStore.isSecretKey(key) ||
                RegExp(r'^(password|secret|token|access_?token|api_?key|apiToken|webToken|authorization)$',
                        caseSensitive: false)
                    .hasMatch(key))) {
          // Historical remote values must not overwrite an active local login.
          final ref = CredentialRef('portable-legacy',
              sha256.convert(utf8.encode('$path/$key\u0000$item')).toString());
          await store.verifiedWrite(ref, item);
          result[key] = ref.placeholder;
        } else {
          result[key] = await visit(item, '$path/$key');
        }
      }
      return result;
    }
    if (value is List) {
      return [
        for (var i = 0; i < value.length; i++) await visit(value[i], '$path/$i')
      ];
    }
    if (value is String &&
        RegExp(r'(?:[?&](?:token|api_?key|access_?token)=|\w+://[^/\s]+:[^/\s]+@)',
                caseSensitive: false)
            .hasMatch(value)) {
      final ref = CredentialRef(
          'backup-url', sha256.convert(utf8.encode(value)).toString());
      await store.verifiedWrite(ref, value);
      return jsonEncode(ref.placeholder);
    }
    return value;
  }

  return await visit(data, '') as Map<String, dynamic>;
}

/// Hydrates only on the receiving host; the transport sees references exclusively.
Future<Map<String, dynamic>> hydratePortableCredentials(
    Map<String, dynamic> data, CredentialStore store,
    {void Function(CredentialRef ref, String reason)? onUnresolved}) async {
  var missing = false;
  Future<Object?> visit(Object? value, {String? field}) async {
    if (value is String && value.startsWith('{"credentialRef":')) {
      return visit(jsonDecode(value), field: field);
    }
    final ref = credentialReference(value);
    if (ref != null) {
      String? secret;
      try {
        secret = await store.vault.read(ref);
      } catch (error) {
        if (onUnresolved == null) rethrow;
        onUnresolved(ref, store.failures[ref] ?? error.runtimeType.toString());
        missing = true;
        return field == 'password' ? '' : null;
      }
      if (secret == null) {
        missing = true;
        onUnresolved?.call(ref, 'credential_missing');
        return field == 'password' ? '' : null;
      }
      return secret;
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        result[entry.key as String] =
            await visit(entry.value, field: entry.key as String);
      }
      if ((result.containsKey('token') && result['token'] == null) ||
          (result.containsKey('accessToken') &&
              result['accessToken'] == null)) {
        if (result.containsKey('isLoggedIn')) result['isLoggedIn'] = false;
      }
      return result;
    }
    if (value is List) return [for (final item in value) await visit(item)];
    // A few preferences encode composite payloads as JSON strings.
    if (field != null &&
        CredentialStore.compositeKeys.containsKey(field) &&
        value is String) {
      return jsonEncode(await visit(jsonDecode(value)));
    }
    return value;
  }

  final result = await visit(data) as Map<String, dynamic>;
  if (missing) {
    store.notices.value = {
      ...store.notices.value,
      '备份/同步只包含凭据引用。这台设备没有对应凭据，请重新登录账号或输入连接密码。'
    }.toList();
  }
  return result;
}
