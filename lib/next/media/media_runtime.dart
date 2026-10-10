import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'classic_projection.dart';
import 'identity_store.dart';
import 'media_service.dart';
import 'media_capability.dart';
import 'media_executors.dart';
import 'media_probe.dart';
import 'metadata_provider.dart';
import 'provider_transport.dart';
import 'providers.dart';
import '../network/dandanplay_gateway.dart';

final class MediaRuntime {
  MediaRuntime._(this.service, this._clients)
      : executors = mediaExecutors(service),
        capability = MediaCapability(service);
  final MediaService service;
  final List<JobExecutor> executors;
  final MediaCapability capability;
  final List<http.Client> _clients;

  static Future<MediaRuntime> create(
      Directory root, Database db, String deviceId,
      {required ClassicMetadataPort classic,
      required Iterable<String> Function() authorizedRoots,
      Iterable<MetadataProvider>? providers,
      Future<int?> Function(String) durationProbe = probeMediaDuration}) async {
    final clients = <http.Client>[];
    if (providers == null) {
      final credentials = VaultCredentialResolver(root);
      await credentials.initialize();
      final tmdb = http.Client(),
          bangumi = http.Client(),
          dandanplay = DandanplayHttpClient();
      clients.addAll([tmdb, bangumi, dandanplay]);
      providers = [
        TmdbMetadataProvider(HttpMetadataTransport(
            provider: 'tmdb',
            baseUri: Uri.parse('https://api.themoviedb.org'),
            client: tmdb,
            privateQuery: () async => {
                  'api_key': await credentials
                      .resolve(const CredentialRef('metadata', 'tmdb'))
                })),
        BangumiMetadataProvider(HttpMetadataTransport(
            provider: 'bangumi',
            baseUri: Uri.parse('https://api.bgm.tv'),
            client: bangumi)),
        DandanplayMetadataProvider(HttpMetadataTransport.dandanplay(
            DandanplayGateway(client: dandanplay))),
      ];
    }
    final store = IdentityStore(db, deviceId);
    final service = MediaService(
        store: store,
        classic: classic,
        authorizedRoots: authorizedRoots,
        providers: providers,
        durationProbe: durationProbe);
    await service.mutate(() async {
      await store.importLegacy(await classic.history());
    });
    return MediaRuntime._(service, clients);
  }

  void attach(TaskEngine engine) => service.engine = engine;

  Future<void> start() => service.recoverProjections();

  void close() {
    for (final client in _clients) {
      client.close();
    }
  }
}
