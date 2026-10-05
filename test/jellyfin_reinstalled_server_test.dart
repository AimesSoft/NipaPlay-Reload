import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
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

  for (final serverType in ['jellyfin', 'emby']) {
    group(serverType, () {
      late HttpServer server;
      late String baseUrl;
      late bool allowAuthentication;
      late Map<String, dynamic> authenticationResponse;
      late int authenticationRequests;
      late SharedPreferences prefs;
      late ServerProfile oldProfile;
      final MediaServerServiceBase service = serverType == 'jellyfin'
          ? JellyfinService.instance
          : EmbyService.instance;
      final registry = MultiAddressServerService.instance;

      setUp(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        baseUrl = 'http://127.0.0.1:${server.port}';
        allowAuthentication = true;
        authenticationRequests = 0;
        authenticationResponse = {
          'AccessToken': 'new-token',
          'User': {'Id': 'new-user'}
        };
        server.listen((request) async {
          request.response.headers.contentType = ContentType.json;
          final path = request.uri.path.replaceFirst(RegExp(r'^/emby'), '');
          if (path == '/System/Info/Public' || path == '/System/Info') {
            request.response.write(
                jsonEncode({'Id': 'new-server', 'ServerName': 'Reinstalled'}));
          } else if (path == '/Users/AuthenticateByName') {
            authenticationRequests++;
            await utf8.decoder.bind(request).join();
            if (allowAuthentication) {
              request.response.write(jsonEncode(authenticationResponse));
            } else {
              request.response.statusCode = HttpStatus.unauthorized;
            }
          } else if (path == '/UserViews' || path == '/Users/new-user/Views') {
            request.response.write(jsonEncode({'Items': []}));
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        });
        oldProfile = ServerProfile(
          id: 'old-profile',
          serverName: 'Original',
          serverType: serverType,
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
          '${serverType}_current_profile_id': 'old-profile',
          '${serverType}_selected_libraries': ['old-library'],
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

      test('login to a reinstalled server reassigns only its reused URL',
          () async {
        final unrelated = ServerProfile(
          id: 'unrelated',
          serverName: 'Other',
          serverType: serverType,
          addresses: [
            ServerAddress(
                id: 'other-address', url: 'http://other.example', name: 'Other')
          ],
          username: 'other-user',
          serverId: 'other-server',
          accessToken: 'other-token',
        );
        final otherType = serverType == 'jellyfin' ? 'emby' : 'jellyfin';
        final otherServiceProfile = unrelated.copyWith(
          id: 'other-service',
          serverType: otherType,
        );
        await prefs.setString(
            '${otherType}_current_profile_id', 'other-service');
        await prefs.setStringList(
            '${otherType}_selected_libraries', ['other-library']);
        await prefs.setString(
            'server_profiles',
            jsonEncode([
              oldProfile.toJson(),
              unrelated.toJson(),
              otherServiceProfile.toJson(),
            ]));
        expect(
            await service.connect('$baseUrl/', 'viewer', 'password'), isTrue);
        final old = registry.getProfileById('old-profile')!;
        final current = service.currentProfile!;
        expect(old.serverId, 'old-server');
        expect(old.addresses.single.id, 'untouched');
        expect(
            old.addresses.single.toJson(), oldProfile.addresses.last.toJson());
        expect(old.accessToken, 'old-token');
        expect(old.userId, 'old-user-id');
        expect(old.lastSuccessfulAddressId, isNull);
        expect(
            registry.getProfileById('unrelated')!.toJson(), unrelated.toJson());
        expect(registry.getProfileById('other-service')!.toJson(),
            otherServiceProfile.toJson());
        expect(prefs.getString('${otherType}_current_profile_id'),
            'other-service');
        expect(prefs.getStringList('${otherType}_selected_libraries'),
            ['other-library']);
        expect(current.id, isNot(old.id));
        expect(current.serverId, 'new-server');
        expect(current.addresses.single.normalizedUrl, baseUrl);
        expect(current.accessToken, 'new-token');
        expect(authenticationRequests, 1);
        expect(
            registry.profiles
                .expand((p) => p.addresses)
                .where((a) => a.normalizedUrl == baseUrl),
            hasLength(1));
        expect(prefs.getString('${serverType}_current_profile_id'), current.id);
        expect(
            prefs.getString('watch_history'), 'untouched historical playback');
        expect(service.selectedLibraryIds, isEmpty);
        expect(prefs.getStringList('${serverType}_selected_libraries'), isNull);
        await registry.loadProfiles();
        expect(registry.getProfileById('old-profile')!.addresses.single.id,
            'untouched');
        expect(registry.getProfileById(current.id)!.serverId, 'new-server');
      });

      test('failed authentication preserves the complete persisted config',
          () async {
        allowAuthentication = false;
        final before =
            prefs.getKeys().map((key) => MapEntry(key, prefs.get(key)));
        final snapshot = Map<String, Object?>.fromEntries(before);
        await expectLater(
            service.connect(baseUrl, 'viewer', 'wrong'), throwsException);
        expect(
            Map<String, Object?>.fromEntries(
                prefs.getKeys().map((key) => MapEntry(key, prefs.get(key)))),
            snapshot);
        expect(registry.profiles.single.toJson(), oldProfile.toJson());
      });

      for (final missingField in ['token', 'userId']) {
        test(
            'successful HTTP authentication with empty $missingField does not save replacement',
            () async {
          authenticationResponse = {
            'AccessToken': missingField == 'token' ? '' : 'new-token',
            'User': {'Id': missingField == 'userId' ? '' : 'new-user'},
          };
          final snapshot = Map<String, Object?>.fromEntries(
            prefs.getKeys().map((key) => MapEntry(key, prefs.get(key))),
          );
          await expectLater(
              service.connect(baseUrl, 'viewer', 'password'), throwsException);
          expect(
              Map<String, Object?>.fromEntries(
                prefs.getKeys().map((key) => MapEntry(key, prefs.get(key))),
              ),
              snapshot);
          expect(registry.profiles.single.toJson(), oldProfile.toJson());
          expect(service.currentProfile!.toJson(), oldProfile.toJson());
          expect(authenticationRequests, 1);
        });
      }

      test(
          'a server with one address reconnects without leaving an active ghost',
          () async {
        oldProfile =
            oldProfile.copyWith(addresses: [oldProfile.addresses.first]);
        await prefs.setString(
            'server_profiles', jsonEncode([oldProfile.toJson()]));
        expect(await service.connect(baseUrl, 'viewer', 'password'), isTrue);
        final archived = registry.getProfileById('old-profile')!;
        expect(archived.addresses, isEmpty);
        expect(archived.currentAddress, isNull);
        expect(archived.serverId, 'old-server');
        final currentId = prefs.getString('${serverType}_current_profile_id');
        expect(currentId, isNot('old-profile'));
        expect(
            registry.getProfileById(currentId!)!.currentAddress!.normalizedUrl,
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
        expect(
            prefs.getString('watch_history'), 'untouched historical playback');
        // The archived identity can still be identified if the old server returns
        // at another address, rather than changing old history to the new identity.
        final oldIdentity = await registry.identifyServer(
            url: 'http://old.example',
            serverType: serverType,
            getServerId: (_) async => 'old-server');
        expect(oldIdentity.existingProfile!.id, 'old-profile');
      });
    });
  }
}
