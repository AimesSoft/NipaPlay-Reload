import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'classic_projection.dart';
import 'identity_store.dart';
import 'media_service.dart';
import 'metadata_provider.dart';
import 'provider_transport.dart';
import 'providers.dart';

final class MediaRuntime {
  MediaRuntime._(this.service, this._clients);
  final MediaService service;
  final List<http.Client> _clients;

  static Future<MediaRuntime> create(
      Directory root, Database db, String deviceId) async {
    final credentials = FileCredentialResolver(root);
    await credentials.initialize();
    final tmdb = http.Client(),
        bangumi = http.Client(),
        dandanplay = DandanplayHttpClient();
    final classic = WatchHistoryMetadataPort(
        changed: ServiceProvider.watchHistoryProvider.refresh);
    final store = IdentityStore(db, deviceId);
    final service = MediaService(
        store: store,
        classic: classic,
        authorizedRoots: () => ServiceProvider.scanService.scannedFolders,
        providers: [
          TmdbMetadataProvider(HttpMetadataTransport(
              provider: 'tmdb',
              baseUri: Uri.parse('https://api.themoviedb.org'),
              client: tmdb,
              privateQuery: () async => {
                    'api_key':
                        await credentials.resolve(const CredentialRef('tmdb'))
                  })),
          BangumiMetadataProvider(HttpMetadataTransport(
              provider: 'bangumi',
              baseUri: Uri.parse('https://api.bgm.tv'),
              client: bangumi)),
          DandanplayMetadataProvider(HttpMetadataTransport(
              provider: 'dandanplay',
              baseUri: Uri.parse(await DandanplayService.getApiBaseUrl()),
              client: dandanplay,
              headers: (path) async {
                if (!await DandanplayService.canAccessCurrentServer()) {
                  throw const Failure(
                      FailureCode.unavailable, 'Dandanplay login is required.');
                }
                final secret = await DandanplayService.getAppSecret();
                final timestamp =
                    DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
                return {
                  'X-AppId': DandanplayService.appId,
                  'X-Timestamp': '$timestamp',
                  'X-Signature': DandanplayService.generateSignature(
                      DandanplayService.appId, timestamp, path, secret)
                };
              })),
        ]);
    await service.mutate(() async {
      await store.importLegacy(await classic.history());
    });
    return MediaRuntime._(service, [tmdb, bangumi, dandanplay]);
  }

  void close() {
    for (final client in _clients) {
      client.close();
    }
  }
}
