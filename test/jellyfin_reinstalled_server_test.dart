import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/multi_address_server_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalOverrides = HttpOverrides.current;
  HttpOverrides.global = null;
  tearDownAll(() => HttpOverrides.global = originalOverrides);
  PackageInfo.setMockInitialValues(
      appName: 'NipaPlay',
      packageName: 'nipaplay',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '');

  late HttpServer server;
  late String baseUrl;
  late bool allowAuthentication;
  late SharedPreferences prefs;
  late ServerProfile oldProfile;
  final service = JellyfinService.instance;
  final registry = MultiAddressServerService.instance;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    allowAuthentication = true;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/System/Info/Public' ||
          request.uri.path == '/System/Info') {
        request.response.write(
            jsonEncode({'Id': 'new-server', 'ServerName': 'Reinstalled'}));
      } else if (request.uri.path == '/Users/AuthenticateByName') {
        await utf8.decoder.bind(request).join();
        if (allowAuthentication) {
          request.response.write(jsonEncode({
            'AccessToken': 'new-token',
            'User': {'Id': 'new-user'}
          }));
        } else {
          request.response.statusCode = HttpStatus.unauthorized;
        }
      } else if (request.uri.path == '/UserViews') {
        request.response.write(jsonEncode({'Items': []}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    oldProfile = ServerProfile(
      id: 'old-profile',
      serverName: 'Original',
      serverType: 'jellyfin',
      addresses: [
        ServerAddress(id: 'reused', url: baseUrl, name: 'Home'),
        ServerAddress(
            id: 'untouched',
            url: 'http://old-server.example:8096',
            name: 'Remote'),
      ],
      username: 'old-user',
      serverId: 'old-server',
      accessToken: 'old-token',
      userId: 'old-user-id',
      lastSuccessfulAddressId: 'reused',
    );
    SharedPreferences.setMockInitialValues({
      'server_profiles': jsonEncode([oldProfile.toJson()]),
      'jellyfin_current_profile_id': 'old-profile',
      'jellyfin_selected_libraries': ['old-library'],
      'watch_history': 'untouched historical playback',
      'media_server_device_id_generated_v1': 'fixture-device',
    });
    prefs = await SharedPreferences.getInstance();
    service
      ..currentProfile = oldProfile
      ..accessToken = 'old-token'
      ..userId = 'old-user-id'
      ..serverUrl = baseUrl
      ..selectedLibraryIds = ['old-library'];
  });

  tearDown(() async {
    await server.close(force: true);
    service
      ..currentProfile = null
      ..serverUrl = null
      ..accessToken = null
      ..userId = null
      ..isConnected = false
      ..isReady = false;
  });

  test('login to a reinstalled server reassigns only its reused URL', () async {
    final unrelated = ServerProfile(
      id: 'unrelated',
      serverName: 'Other',
      serverType: 'jellyfin',
      addresses: [
        ServerAddress(
            id: 'other-address', url: 'http://other.example', name: 'Other')
      ],
      username: 'other-user',
      serverId: 'other-server',
      accessToken: 'other-token',
    );
    await prefs.setString(
        'server_profiles',
        jsonEncode([
          oldProfile.toJson(),
          unrelated.toJson(),
        ]));
    expect(await service.connect('$baseUrl/', 'viewer', 'password'), isTrue);
    final old = registry.getProfileById('old-profile')!;
    final current = service.currentProfile!;
    expect(old.serverId, 'old-server');
    expect(old.addresses.single.id, 'untouched');
    expect(old.accessToken, 'old-token');
    expect(old.userId, 'old-user-id');
    expect(old.lastSuccessfulAddressId, isNull);
    expect(registry.getProfileById('unrelated')!.toJson(), unrelated.toJson());
    expect(current.id, isNot(old.id));
    expect(current.serverId, 'new-server');
    expect(current.addresses.single.normalizedUrl, baseUrl);
    expect(current.accessToken, 'new-token');
    expect(
        registry.profiles
            .expand((p) => p.addresses)
            .where((a) => a.normalizedUrl == baseUrl),
        hasLength(1));
    expect(prefs.getString('jellyfin_current_profile_id'), current.id);
    expect(prefs.getString('watch_history'), 'untouched historical playback');
    expect(service.selectedLibraryIds, isEmpty);
    expect(prefs.getStringList('jellyfin_selected_libraries'), isNull);
    await registry.loadProfiles();
    expect(registry.getProfileById('old-profile')!.addresses.single.id,
        'untouched');
    expect(registry.getProfileById(current.id)!.serverId, 'new-server');
  });

  test('failed authentication preserves the complete persisted config',
      () async {
    allowAuthentication = false;
    final before = prefs.getKeys().map((key) => MapEntry(key, prefs.get(key)));
    final snapshot = Map<String, Object?>.fromEntries(before);
    await expectLater(
        service.connect(baseUrl, 'viewer', 'wrong'), throwsException);
    expect(
        Map<String, Object?>.fromEntries(
            prefs.getKeys().map((key) => MapEntry(key, prefs.get(key)))),
        snapshot);
    expect(registry.profiles.single.toJson(), oldProfile.toJson());
  });

  test('a server with one address reconnects without leaving an active ghost',
      () async {
    oldProfile = oldProfile.copyWith(addresses: [oldProfile.addresses.first]);
    await prefs.setString('server_profiles', jsonEncode([oldProfile.toJson()]));
    expect(await service.connect(baseUrl, 'viewer', 'password'), isTrue);
    final archived = registry.getProfileById('old-profile')!;
    expect(archived.addresses, isEmpty);
    expect(archived.currentAddress, isNull);
    expect(archived.serverId, 'old-server');
    final currentId = prefs.getString('jellyfin_current_profile_id');
    expect(currentId, isNot('old-profile'));
    expect(registry.getProfileById(currentId!)!.currentAddress!.normalizedUrl,
        baseUrl);
    final ready = Completer<void>();
    void onReady() {
      if (service.isConnected &&
          service.currentProfile?.id == currentId &&
          !ready.isCompleted) {
        ready.complete();
      }
    }

    service.addReadyListener(onReady);
    addTearDown(() => service.removeReadyListener(onReady));
    service
      ..currentProfile = null
      ..serverUrl = null
      ..accessToken = null
      ..userId = null
      ..isConnected = false;
    await service.loadSavedSettings();
    await ready.future.timeout(const Duration(seconds: 5));
    expect(service.currentProfile!.id, currentId);
    expect(service.isConnected, isTrue);
    expect(prefs.getString('watch_history'), 'untouched historical playback');
    // The archived identity can still be identified if the old server returns
    // at another address, rather than changing old history to the new identity.
    final oldIdentity = await registry.identifyServer(
        url: 'http://old.example',
        serverType: 'jellyfin',
        getServerId: (_) async => 'old-server');
    expect(oldIdentity.existingProfile!.id, 'old-profile');
  });
}
