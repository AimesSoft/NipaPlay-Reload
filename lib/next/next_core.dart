import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_capability.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'danmaku/export.dart';
import 'danmaku/runtime.dart';
import 'downloads/download_backend.dart';
import 'downloads/download_runtime.dart';
import 'media/classic_projection.dart';
import 'media/media_runtime.dart';
import 'media/media_probe.dart';
import 'media_sources/service.dart';
import 'media_sources/capability.dart';
import 'accounts/service.dart';
import 'accounts/capability.dart';
import 'media/metadata_provider.dart';
import 'next_database.dart';
import 'tasks/device_identity.dart';
import 'tasks/sqlite_job_store.dart';
import 'settings/application_settings.dart';
import 'settings/download_settings.dart';
import 'settings/registry.dart';
import 'settings/capability.dart';
import 'settings/classic_settings.dart';
import 'settings/operations.dart';
import 'mesh/runtime.dart';
import 'mesh/capability.dart';
import 'mesh/debug_claim_names.dart';
import 'state/query.dart';
import 'state/views.dart';
import 'harness_hooks.dart';
import 'harness_location.dart';

/// Application-owned task and capability composition, independent of Labs.
final class NextCore {
  NextCore({
    required DownloadBackend downloadBackend,
    required DownloadLibrary downloadLibrary,
    required Future<bool> Function() isDownloaderEnabled,
    required Future<Set<String>> Function() loadImportedKeys,
    required ClassicMetadataPort classic,
    required Iterable<String> Function() authorizedRoots,
    Directory? root,
    DatabaseFactory? databaseFactory,
    Iterable<MetadataProvider>? mediaProviders,
    Future<int?> Function(String) mediaDurationProbe = probeMediaDuration,
    Duration downloadRefreshInterval = const Duration(seconds: 5),
  }) : downloads = DownloadRuntime(
            backend: downloadBackend,
            library: downloadLibrary,
            isEnabled: isDownloaderEnabled,
            loadImportedKeys: loadImportedKeys,
            refreshInterval: downloadRefreshInterval) {
    ready = _initialize(root, databaseFactory, classic, authorizedRoots,
        mediaProviders, mediaDurationProbe);
  }

  late final Future<void> ready;
  late final Directory root;
  late final String deviceId;
  late final TaskEngine engine;
  final hooks = HarnessHooks();
  final harnessLocation = HarnessLocation();
  final DownloadRuntime downloads;
  CredentialStore get credentials => CredentialStore.instance;
  CredentialVault get credentialVault => credentials.vault;
  late final MediaRuntime media;
  late final MediaSourcesService mediaSources;
  final accounts = AccountsService();
  late final DanmakuRuntime danmaku;
  late final SettingsRegistry settings;
  late final MeshRuntime mesh;
  late final List<Capability> capabilities;
  final StateSources stateSources = StateSources();
  late final StateCapability state;

  Future<void> _initialize(
      Directory? suppliedRoot,
      DatabaseFactory? databaseFactory,
      ClassicMetadataPort classic,
      Iterable<String> Function() authorizedRoots,
      Iterable<MetadataProvider>? mediaProviders,
      Future<int?> Function(String) mediaDurationProbe) async {
    await debugDandanplayClaimNames(credentialVault);
    root = suppliedRoot ??
        Directory(
            '${(await StorageService.getAppStorageDirectory()).path}/next');
    deviceId = await loadDeviceIdentity(root);
    final database = await openNextDatabase(root, factory: databaseFactory);
    final jobs = SqliteJobStore.fromDatabase(database);
    media = await MediaRuntime.create(root, jobs.database, deviceId,
        classic: classic,
        authorizedRoots: authorizedRoots,
        providers: mediaProviders,
        durationProbe: mediaDurationProbe);
    mediaSources = MediaSourcesService(media.service.store);
    mesh = MeshRuntime(
        root: root,
        vault: credentialVault,
        token: () async => credentials.read(
            await SharedPreferences.getInstance(), 'dandanplay_token'));
    settings = SettingsRegistry(database, [
      ...ApplicationSettings.entries(),
      ...ClassicSettings.entries(),
      ...DownloadSettings.entries(),
      meshAddressSetting(mesh),
      harnessLocation.setting
    ]);
    SettingsAccess.registry = settings;
    ApplicationSettings.authorizePath = (path, {directory = false}) =>
        media.service.authorizedPath(path, directory: directory);
    danmaku = await DanmakuRuntime.create(media.service.store,
        authorizeLocalFile: media.service.authorizedPath);
    danmaku.service.exporter = DanmakuExporter(danmaku.service.store,
        (path) => media.service.authorizedPath(path, directory: true));
    engine = TaskEngine(store: jobs, ownerDeviceId: deviceId, executors: [
      downloads.executor,
      ...media.executors,
      ...mediaSourcesExecutors(mediaSources),
      ...accountExecutors(accounts),
      ...danmaku.executors,
      hooks,
    ]);
    hooks.engine = engine;
    downloads.attach(engine, root);
    media.attach(engine);
    mediaSources.engine = engine;
    accounts.attach(engine);
    danmaku.attach(engine);
    state = StateCapability(publicStateViews(
        media: media.service,
        settings: settings,
        danmaku: danmaku.service,
        mesh: mesh,
        sources: stateSources));
    capabilities = List.unmodifiable([
      CredentialCapability(credentials),
      TaskCapability(engine),
      downloads.capability,
      downloads.metadataCapability,
      media.capability,
      MediaSourcesCapability(mediaSources),
      AccountsCapability(accounts),
      danmaku.capability,
      SettingsCapability(settings),
      ClassicOperations(settings),
      MeshCapability(mesh),
      state,
    ]);
    await engine.start();
    await downloads.start();
    await media.start();
    mesh.attach(Harness(capabilities));
    await mesh.startConfigured();
  }

  void attachHarness(Harness harness) => mesh.attach(harness);

  Future<void> close() async {
    await ready;
    if (identical(SettingsAccess.registry, settings)) {
      SettingsAccess.registry = null;
      ApplicationSettings.authorizePath = null;
    }
    await settings.drain();
    await hooks.disable();
    harnessLocation.dispose();
    await mesh.close();
    await downloads.stop();
    await danmaku.stopRestoring();
    final jobs = await engine.list(type: 'download');
    await media.quiesce();
    await engine.close();
    await mediaSources.close();
    await accounts.close();
    await downloads.quiesce(jobs);
    downloads.dispose();
    danmaku.close();
    media.close();
  }
}
