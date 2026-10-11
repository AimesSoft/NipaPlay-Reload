import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media_sources/capability.dart';
import 'package:nipaplay/next/media_sources/service.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/smb2_native_service_ffi.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('X20 live remote metadata through the Agent actions', () async {
    final credentials =
        jsonDecode(File('/tmp/nipa-next/testservers.json').readAsStringSync())
            as Map;
    final oldVault = CredentialStore.instance;
    final oldHttp = HttpOverrides.current;
    CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
    HttpOverrides.global = _DirectHttp();
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({
      'server_profiles': '[]',
      'smb_connections': '[]',
      'webdav_connections': '[]',
    });
    PackageInfo.setMockInitialValues(
        appName: 'NipaPlay',
        packageName: 'nipaplay',
        version: 'X20',
        buildNumber: '1',
        buildSignature: '');
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('nipa-x20-');
    final jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    final store = IdentityStore(jobs.database, 'x20-experiment');
    final sources = MediaSourcesService(store);
    await sources.ensureInitialized();
    final harness = Harness([MediaSourcesCapability(sources)]);
    addTearDown(() async {
      await sources.close();
      await store.closeEvents();
      await jobs.database.close();
      Smb2NativeService.instance.dispose();
      await root.delete(recursive: true);
      CredentialStore.instance = oldVault;
      HttpOverrides.global = oldHttp;
      debugDefaultTargetPlatformOverride = null;
    });
    final observations = <String, Object?>{};
    Future<JsonMap> call(String action, JsonMap input) async {
      final outcome = await harness.invokeJson(
          action, input, Invocation(origin: 'x20-experiment'));
      expect(outcome, isA<Completed>(),
          reason: jsonEncode(outcome.toEnvelope()));
      final result = (outcome as Completed).value.toJson();
      expect(harness.lookup(action)!.spec.output.validate(result), isEmpty);
      return result;
    }

    for (final type in ['jellyfin', 'emby']) {
      final c = credentials[type] as Map;
      final url = c['base_url'] as String;
      expect(Uri.parse(url).host, '127.0.0.1');
      final added = await call('media.sources.add', {
        'type': type,
        'name': 'X20 $type',
        'url': url,
        'username': c['user_name'],
      });
      final id = (added['source'] as Map)['sourceId'] as String;
      await sources.server(type).acceptSession(
          sources.profiles.getProfileById(sources.key(id))!,
          token: c['access_token'] as String,
          authenticatedUserId: c['user_id'] as String,
          authenticatedUsername: c['user_name'] as String);
      final libraries = await call('media.sources.libraries', {'sourceId': id});
      final parent = (libraries['libraries'] as List)
          .cast<Map>()
          .singleWhere((l) => l['name'] == '番剧')['id'] as String;
      final browse = await call('media.sources.browse', {
        'sourceId': id,
        'parentId': parent,
        'recursive': true,
      });
      final entries = (browse['entries'] as List).cast<Map>();
      expect(entries, hasLength(6));
      for (final e in entries) {
        final facts = e['metadata'] as Map;
        expect(facts['Path'], contains('/莉可丽丝/'));
        expect(facts['RunTimeTicks'], greaterThan(0));
        expect(facts['MediaSources'], isNotEmpty);
        expect(facts['MediaStreams'], isNotEmpty);
        expect(facts.containsKey('ProviderIds'), isTrue);
        expect((e['provenance'] as Map)['url'], url);
        expect((e['provenance'] as Map)['sourceId'], id);
      }
      final queryIds = entries.map((e) => e['id'] as String).toList();
      final locationsBefore = await jobs.database.query('media_locations');
      final query = await call('media.sources.query', {
        'sourceId': id,
        'itemIds': queryIds,
      });
      expect(query['missingItemIds'], isEmpty);
      for (final e in (query['entries'] as List).cast<Map>()) {
        expect(e['fileId'], isNull);
        expect(
            e['metadata'],
            entries.singleWhere(
                (original) => original['id'] == e['id'])['metadata']);
      }
      expect(await jobs.database.query('media_locations'), locationsBefore);
      expect(await jobs.database.query('media_bindings'), isEmpty);
      observations['$type.browse'] = browse;
      observations['$type.query'] = query;
      print('X20 $type episodes: ${jsonEncode(entries.map((e) => {
            'id': e['id'],
            'number': e['number'],
            'seasonNumber': e['seasonNumber'],
            'metadata': {
              for (final k in [
                'SeriesName',
                'ProductionYear',
                'OriginalTitle',
                'Container',
                'RunTimeTicks',
                'ProviderIds'
              ])
                if ((e['metadata'] as Map).containsKey(k))
                  k: (e['metadata'] as Map)[k]
            },
          }).toList())}');
      print('X20 $type first complete entry: ${jsonEncode(entries.first)}');
      print(
          'X20 $type query: total=${query['total']}, missing=${query['missingItemIds']}, indexUnchanged=true, bindings=0');
    }

    for (final type in ['webdav', 'smb']) {
      final c = credentials[type] as Map;
      if (type == 'smb') {
        expect(c['host'], '127.0.0.1');
      } else {
        expect(Uri.parse(c['url'] as String).host, '127.0.0.1');
      }
      final added = await call('media.sources.add', {
        'type': type,
        'name': 'X20 $type',
        'username': c['user_name'],
        if (type == 'smb') ...{'host': c['host'], 'port': c['port']} else
          'url': c['url'],
      });
      final id = (added['source'] as Map)['sourceId'] as String;
      if (type == 'smb') {
        final connection =
            sources.smb.getConnectionByIdOrName(sources.key(id))!;
        await sources.smb.configureConnection(connection.copyWith(
            password: c['password'] as String,
            credentialOrigin: connection.credentialAuthority));
      } else {
        final connection =
            sources.webdav.getConnectionByIdOrName(sources.key(id))!;
        await sources.webdav.configureConnection(connection.copyWith(
            password: c['password'] as String,
            credentialOrigin: connection.credentialAuthority));
      }
      final browse = await call('media.sources.browse', {
        'sourceId': id,
        'parentId': '/anime/',
      });
      final files = (browse['entries'] as List)
          .cast<Map>()
          .where((e) => e['isDirectory'] == false)
          .toList();
      expect(files, hasLength(6));
      for (final file in files) {
        final metadata = file['metadata'] as Map;
        expect(metadata['Size'], greaterThan(0));
        expect(metadata['LastModified'], isNotNull);
      }
      final query = await call('media.sources.query', {
        'sourceId': id,
        'itemIds': [files.first['id']],
      });
      expect(query['total'], 1);
      observations['$type.browse'] = browse;
      observations['$type.query'] = query;
      print('X20 $type first complete entry: ${jsonEncode(files.first)}');
    }
    final json = const JsonEncoder.withIndent('  ').convert(observations);
    for (final c in credentials.values.cast<Map>()) {
      for (final key in ['password', 'access_token']) {
        if (c[key] is String) expect(json.contains(c[key] as String), isFalse);
      }
    }
    await File('/tmp/nipa-next/x20-observations.json').writeAsString(json);
    print(
        'X20 output contains no supplied password/token; all stores and preferences isolated');
  },
      skip: !const bool.fromEnvironment('NIPA_X20_REAL'),
      timeout: const Timeout(Duration(minutes: 3)));
}

class _DirectHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}
