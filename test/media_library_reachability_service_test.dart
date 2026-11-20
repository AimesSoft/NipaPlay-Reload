import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/media_library_reachability_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebDAVService webdav;
  late SMBService smb;
  late bool lan;
  late bool wan;

  setUp(() {
    lan = true;
    wan = true;
    webdav = WebDAVService.forTesting(connectionValidator: (connection) async {
      final reachable = connection.url.contains('10.0.0.2') ? lan : wan;
      return reachable ? connection : null;
    });
    smb = SMBService.forTesting(
        connectionValidator: (connection) async =>
            connection.host == '10.0.0.2' ? lan : wan);
    SharedPreferences.setMockInitialValues({
      'webdav_connections': jsonEncode([
        WebDAVConnection(
                id: 'dav',
                name: 'DAV',
                url: 'http://10.0.0.2/dav/',
                wanUrl: 'https://nas.example.test/dav/',
                username: 'u',
                password: 'p')
            .toJson(),
      ]),
      'smb_connections': jsonEncode([
        SMBConnection(
                id: 'smb',
                name: 'SMB',
                host: '10.0.0.2',
                wanHost: 'nas.example.test',
                wanPort: 1445,
                username: 'u',
                password: 'p')
            .toJson(),
      ]),
    });
  });

  test(
      'startup publishes usable connection state with address results and persists it',
      () async {
    final startup =
        MediaLibraryReachabilityService.forTesting(webdav: webdav, smb: smb);
    addTearDown(startup.dispose);
    startup.addListener(() {
      for (final connection in webdav.connections) {
        final result = webdav.lastAddressReachability(connection.id);
        if (result != null) {
          expect(connection.isConnected, result.lan || result.wan);
        }
      }
      for (final connection in smb.connections) {
        final result = smb.lastAddressReachability(connection.id);
        if (result != null) {
          expect(connection.isConnected, result.lan || result.wan);
        }
      }
    });
    await startup.checkAll();
    expect(webdav.connections.single.isConnected, isTrue);
    expect(smb.connections.single.isConnected, isTrue);
    expect(webdav.lastAddressReachability('dav'), (lan: true, wan: true));
    expect(smb.lastAddressReachability('smb'), (lan: true, wan: true));
    // The management page initializes services again when opened.
    await webdav.initialize();
    await smb.initialize();
    expect(webdav.connections.single.isConnected, isTrue);
    expect(smb.connections.single.isConnected, isTrue);
  });

  test(
      'manual retest updates both address badges and preferred endpoint on every outcome',
      () async {
    await webdav.initialize();
    await smb.initialize();
    for (final outcome in [
      (lan: false, wan: true),
      (lan: true, wan: false),
      (lan: true, wan: true),
      (lan: false, wan: true),
      (lan: false, wan: false)
    ]) {
      lan = outcome.lan;
      wan = outcome.wan;
      await webdav.updateConnectionStatus('DAV');
      await smb.updateConnectionStatus('SMB');
      expect(webdav.lastAddressReachability('dav'), outcome);
      expect(smb.lastAddressReachability('smb'), outcome);
      expect(webdav.connections.single.isConnected, lan || wan);
      expect(smb.connections.single.isConnected, lan || wan);
      expect(
          webdav.effectiveUrl(webdav.connections.single),
          !lan && wan
              ? 'https://nas.example.test/dav/'
              : 'http://10.0.0.2/dav/');
      final effective = smb.effectiveConnection(smb.connections.single);
      expect(effective.host, !lan && wan ? 'nas.example.test' : '10.0.0.2');
      expect(effective.port, !lan && wan ? 1445 : 445);
    }
  });

  test('failed standalone WebDAV test clears a preceding WAN preference',
      () async {
    await webdav.initialize();
    final connection = webdav.connections.single;
    lan = false;
    expect(await webdav.testConnection(connection), isTrue);
    expect(webdav.effectiveUrl(connection), connection.wanUrl);
    wan = false;
    expect(await webdav.testConnection(connection), isFalse);
    expect(webdav.effectiveUrl(connection), connection.url);
  });

  test(
      'reloading persisted configuration cannot overwrite the latest probe state',
      () async {
    await webdav.initialize();
    await smb.initialize();
    expect(webdav.connections.single.isConnected, isFalse);
    expect(smb.connections.single.isConnected, isFalse);
    await webdav.testConnection(webdav.connections.single);
    await smb.testConnection(smb.connections.single);
    // Configuration reload can overlap with the probe's asynchronous save.
    await webdav.initialize();
    await smb.initialize();
    expect(webdav.connections.single.isConnected, isTrue);
    expect(smb.connections.single.isConnected, isTrue);
    lan = false;
    wan = false;
    await webdav.testConnection(webdav.connections.single);
    await smb.testConnection(smb.connections.single);
    await webdav.initialize();
    await smb.initialize();
    expect(webdav.connections.single.isConnected, isFalse);
    expect(smb.connections.single.isConnected, isFalse);
  });

  test(
      'startup WAN-only success and later complete failure use the same status update path',
      () async {
    final startup =
        MediaLibraryReachabilityService.forTesting(webdav: webdav, smb: smb);
    addTearDown(startup.dispose);
    lan = false;
    await startup.checkAll();
    expect(webdav.connections.single.isConnected, isTrue);
    expect(smb.connections.single.isConnected, isTrue);
    expect(webdav.effectiveUrl(webdav.connections.single),
        contains('nas.example.test'));
    wan = false;
    await startup.checkAll();
    expect(webdav.connections.single.isConnected, isFalse);
    expect(smb.connections.single.isConnected, isFalse);
    expect(webdav.lastAddressReachability('dav'), (lan: false, wan: false));
    expect(smb.lastAddressReachability('smb'), (lan: false, wan: false));
    expect(
        webdav.effectiveUrl(webdav.connections.single), 'http://10.0.0.2/dav/');
  });
}
