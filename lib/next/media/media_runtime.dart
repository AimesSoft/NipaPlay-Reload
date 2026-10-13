import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

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
import 'online_providers.dart';
import '../network/dandanplay_gateway.dart';

final class MediaRuntime {
  MediaRuntime._(this.service, this._clients)
      : executors = mediaExecutors(service),
        capability = MediaCapability(service);
  final MediaService service;
  final List<JobExecutor> executors;
  final MediaCapability capability;
  final List<http.Client> _clients;
  Listenable? _historyChanges;
  Timer? _historyTimer;

  void _classicChanged() {
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(service
          .syncClassicHistory()
          .catchError((Object error, StackTrace stack) {
        FlutterError.reportError(FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'Next media library',
            context: ErrorDescription('synchronizing Classic matches')));
        return 0;
      }));
    });
  }

  static Future<MediaRuntime> create(
      Directory root, Database db, String deviceId,
      {required ClassicMetadataPort classic,
      required Iterable<String> Function() authorizedRoots,
      Iterable<MetadataProvider>? providers,
      Future<int?> Function(String) durationProbe = probeMediaDuration}) async {
    final clients = <http.Client>[];
    if (providers == null) {
      final credentials = VaultCredentialResolver(root);
      final tmdb = http.Client(),
          bangumi = http.Client(),
          dandanplay = DandanplayHttpClient();
      clients.addAll([tmdb, bangumi, dandanplay]);
      providers = onlineMetadataProviders(credentials: credentials,
          tmdb: tmdb, bangumi: bangumi,
          dandanplay: DandanplayGateway(client: dandanplay));
    }
    final store = IdentityStore(db, deviceId);
    final service = MediaService(
        store: store,
        classic: classic,
        authorizedRoots: authorizedRoots,
        providers: providers,
        durationProbe: durationProbe);
    final runtime = MediaRuntime._(service, clients);
    if (classic is WatchHistoryMetadataPort) {
      runtime._historyChanges = classic.historyChanges;
      runtime._historyChanges?.addListener(runtime._classicChanged);
    }
    await service.syncClassicHistory();
    return runtime;
  }

  void attach(TaskEngine engine) => service.engine = engine;

  Future<void> start() => service.recoverProjections();

  void _stopObservingClassic() {
    _historyTimer?.cancel();
    _historyChanges?.removeListener(_classicChanged);
  }

  Future<void> quiesce() async {
    _stopObservingClassic();
    await service.mutate(() async {});
  }

  void close() {
    _stopObservingClassic();
    for (final client in _clients) {
      client.close();
    }
  }
}
