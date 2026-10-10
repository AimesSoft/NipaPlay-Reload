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
import 'media/metadata_provider.dart';
import 'next_database.dart';
import 'tasks/device_identity.dart';
import 'tasks/sqlite_job_store.dart';
import 'settings/application_settings.dart';
import 'settings/registry.dart';
import 'settings/capability.dart';
import 'mesh/runtime.dart';
import 'mesh/capability.dart';
import 'mesh/debug_claim_names.dart';
import 'sessions/capability.dart';
import 'sessions/platform_session.dart';
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
  late final DanmakuRuntime danmaku;
  late final SettingsRegistry settings;
  late final MeshRuntime mesh;
  late final PlatformSessions sessions;
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
    mesh = MeshRuntime(
        root: root,
        vault: credentialVault,
        token: () async => credentials.read(
            await SharedPreferences.getInstance(), 'dandanplay_token'));
    settings = SettingsRegistry(database, [
      ...ApplicationSettings.entries(),
      meshAddressSetting(mesh),
      harnessLocation.setting
    ]);
    SettingsAccess.registry = settings;
    ApplicationSettings.authorizePath = (path, {directory = false}) =>
        media.service.authorizedPath(path, directory: directory);
    final login = MacOSPlatformLogin();
    sessions = PlatformSessions(credentialVault, login);
    login.bind(sessions);
    await sessions.restore();
    danmaku = await DanmakuRuntime.create(media.service.store,
        sessions: sessions, authorizeLocalFile: media.service.authorizedPath);
    danmaku.service.exporter = DanmakuExporter(danmaku.service.store,
        (path) => media.service.authorizedPath(path, directory: true));
    engine = TaskEngine(store: jobs, ownerDeviceId: deviceId, executors: [
      downloads.executor,
      ...media.executors,
      ...danmaku.executors,
      hooks,
    ]);
    hooks.engine = engine;
    downloads.attach(engine, root);
    media.attach(engine);
    danmaku.attach(engine);
    state = StateCapability(publicStateViews(
        media: media.service,
        settings: settings,
        danmaku: danmaku.service,
        mesh: mesh,
        sources: stateSources));
    capabilities = List.unmodifiable([
      CredentialCapability(credentials),
      PlatformSessionCapability(sessions),
      TaskCapability(engine),
      downloads.capability,
      media.capability,
      danmaku.capability,
      SettingsCapability(settings),
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
    await downloads.quiesce(jobs);
    downloads.dispose();
    danmaku.close();
    await sessions.close();
    sessions.dispose();
    media.close();
  }
}
