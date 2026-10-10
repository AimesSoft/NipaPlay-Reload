import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_capability.dart';

import 'danmaku/export.dart';
import 'danmaku/runtime.dart';
import 'downloads/download_backend.dart';
import 'downloads/download_runtime.dart';
import 'media/classic_projection.dart';
import 'media/media_runtime.dart';
import 'media/metadata_provider.dart';
import 'next_database.dart';
import 'tasks/device_identity.dart';
import 'tasks/sqlite_job_store.dart';
import 'settings/application_settings.dart';
import 'settings/registry.dart';
import 'settings/capability.dart';

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
    Duration downloadRefreshInterval = const Duration(seconds: 5),
  }) : downloads = DownloadRuntime(
            backend: downloadBackend,
            library: downloadLibrary,
            isEnabled: isDownloaderEnabled,
            loadImportedKeys: loadImportedKeys,
            refreshInterval: downloadRefreshInterval) {
    ready = _initialize(
        root, databaseFactory, classic, authorizedRoots, mediaProviders);
  }

  late final Future<void> ready;
  late final Directory root;
  late final String deviceId;
  late final TaskEngine engine;
  final DownloadRuntime downloads;
  CredentialStore get credentials => CredentialStore.instance;
  CredentialVault get credentialVault => credentials.vault;
  late final MediaRuntime media;
  late final DanmakuRuntime danmaku;
  late final SettingsRegistry settings;
  late final List<Capability> capabilities;

  Future<void> _initialize(
      Directory? suppliedRoot,
      DatabaseFactory? databaseFactory,
      ClassicMetadataPort classic,
      Iterable<String> Function() authorizedRoots,
      Iterable<MetadataProvider>? mediaProviders) async {
    root = suppliedRoot ??
        Directory(
            '${(await StorageService.getAppStorageDirectory()).path}/next');
    deviceId = await loadDeviceIdentity(root);
    final database = await openNextDatabase(root, factory: databaseFactory);
    final jobs = SqliteJobStore.fromDatabase(database);
    media = await MediaRuntime.create(root, jobs.database, deviceId,
        classic: classic,
        authorizedRoots: authorizedRoots,
        providers: mediaProviders);
    settings = SettingsRegistry(database, ApplicationSettings.entries());
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
      ...danmaku.executors
    ]);
    downloads.attach(engine, root);
    media.attach(engine);
    danmaku.attach(engine);
    capabilities = List.unmodifiable([
      CredentialCapability(credentials),
      TaskCapability(engine),
      downloads.capability,
      media.capability,
      danmaku.capability,
      SettingsCapability(settings),
    ]);
    await engine.start();
    await downloads.start();
    await media.start();
  }

  Future<void> close() async {
    await ready;
    if (identical(SettingsAccess.registry, settings)) {
      SettingsAccess.registry = null;
      ApplicationSettings.authorizePath = null;
    }
    await settings.drain();
    await downloads.stop();
    await danmaku.stopRestoring();
    final jobs = await engine.list(type: 'download');
    await engine.close();
    await downloads.quiesce(jobs);
    downloads.dispose();
    danmaku.close();
    media.close();
  }
}
