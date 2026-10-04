import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const legacyName = 'nas';
  const legacyUrl = 'http://192.168.3.39:5244/dav/';
  const legacyUsername = 'admin';
  const legacyPassword = 'pw';

  String deriveLegacyId(String url, String username) => const Uuid().v5(
        '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
        'nipaplay:webdav:$url|$username',
      );

  test('加载无 id 的旧连接时按 url|username 派生稳定 id 并可直接解析', () async {
    SharedPreferences.setMockInitialValues({
      'webdav_connections': json.encode([
        {
          'name': legacyName,
          'url': legacyUrl,
          'username': legacyUsername,
          'password': legacyPassword,
        },
      ]),
    });
    final service = WebDAVService.forTesting();
    await service.initialize();

    final legacyId = deriveLegacyId(legacyUrl, legacyUsername);
    expect(service.connections.single.id, legacyId);
    expect(
      service.resolveMediaPath('webdav://$legacyId/D:/Qbit/show/01.mp4'),
      isNotNull,
    );
  });

  test('连接删除重建后，旧条目引用的派生 id 重绑到新连接', () async {
    final newId = const Uuid().v4();
    SharedPreferences.setMockInitialValues({
      'webdav_connections': json.encode([
        {
          'id': newId,
          'name': legacyName,
          'url': legacyUrl,
          'username': legacyUsername,
          'password': legacyPassword,
        },
      ]),
    });
    final service = WebDAVService.forTesting();
    await service.initialize();

    final legacyId = deriveLegacyId(legacyUrl, legacyUsername);
    final resolved =
        service.resolveMediaPath('webdav://$legacyId/D:/Qbit/show/01.mp4');
    expect(resolved, isNotNull);
    expect(resolved!.connection.id, newId);
  });

  test('URL 与用户名都对不上的旧 id 不做重绑', () async {
    final newId = const Uuid().v4();
    SharedPreferences.setMockInitialValues({
      'webdav_connections': json.encode([
        {
          'id': newId,
          'name': legacyName,
          'url': 'http://10.0.0.2:5005/dav/',
          'username': 'other',
          'password': legacyPassword,
        },
      ]),
    });
    final service = WebDAVService.forTesting();
    await service.initialize();

    final staleId = deriveLegacyId(legacyUrl, legacyUsername);
    expect(
      service.resolveMediaPath('webdav://$staleId/D:/Qbit/show/01.mp4'),
      isNull,
    );
  });
}
