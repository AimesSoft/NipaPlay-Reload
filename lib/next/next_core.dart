import 'capabilities/app_runtime_capability.dart';
import 'platform/lab_profile.dart';
import 'system/app_restart.dart';
import 'system/app_runtime.dart';
import '../services/desktop_exit_handler.dart';
import 'mesh/files.dart';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/bangumi_sync_service.dart';
import 'package:nipaplay/security/credential_capability.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'danmaku/export.dart';
import 'danmaku/runtime.dart';
import 'downloads/download_backend.dart';
import 'downloads/download_runtime.dart';
import 'media/classic_projection.dart';
import 'media/library_arrivals.dart';
import 'media/media_runtime.dart';
import 'media/media_probe.dart';
import 'media_sources/service.dart';
import 'media_sources/capability.dart';
import 'media_sources/sync.dart';
import 'media_sources/remote_admin.dart';
import 'accounts/service.dart';
import 'accounts/capability.dart';
import 'media/metadata_provider.dart';
import 'next_database.dart';
import 'tasks/device_identity.dart';
import 'tasks/job_origin.dart';
import 'tasks/sqlite_job_store.dart';
import 'tasks/user_consent.dart';
import 'settings/application_settings.dart';
import 'settings/download_settings.dart';
import 'settings/consent.dart';
import 'settings/prefs.dart';
import 'settings/registry.dart';
import 'settings/capability.dart';
import 'settings/classic_settings.dart';
import 'settings/operations.dart';
import 'mesh/runtime.dart';
import 'mesh/library.dart';
import 'mesh/library_capability.dart';
import 'mesh/delivery.dart';
import 'mesh/capability.dart';
import 'mesh/debug_claim_names.dart';
import 'db/capability.dart';
import 'db/service.dart';
import 'db/wiring.dart';
import 'state/query.dart';
import 'state/views.dart';
import 'state/system_views.dart';
import 'state/change_history.dart';
import 'state/activity.dart';
import 'harness_hooks.dart';
import 'capabilities/local_library_operations.dart';
import 'harness_location.dart';
import 'followups/service.dart';
import 'followups/capability.dart';
import 'ui_data/service.dart';
import 'ui_data/library_service.dart';
import 'ui_data/library_sources.dart';
import 'ui_data/library_capability.dart';
import 'ui/shell/next_ui_preference.dart';
import 'ui_data/capability.dart';
import 'chat/session_store.dart';
import 'memory/service.dart';
import 'memory/capability_changes.dart';
import 'memory/capability.dart';
import 'chat/helpers.dart';
import 'subtitles/library.dart';
import 'subtitles/capability.dart';
import 'programs/runtime.dart';
import 'programs/repository.dart';
import 'tasks/resources.dart';
import 'tasks/classic_scan.dart';
import 'events/capability.dart';
import 'events/signals.dart';
import 'network/capability.dart';
import 'network/observations.dart';
import 'settings/system_settings.dart';
import 'system/storage.dart';
import 'system/diagnostics.dart';
import 'system/desktop.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'dart:async';

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
    Future<JsonMap> Function(String) mediaSubtitleProbe = probeMediaInfo,
    Duration downloadRefreshInterval = const Duration(seconds: 5),
  }) : downloads = DownloadRuntime(
            backend: downloadBackend,
            library: downloadLibrary,
            isEnabled: isDownloaderEnabled,
            loadImportedKeys: loadImportedKeys,
            refreshInterval: downloadRefreshInterval) {
    ready = _initialize(root, databaseFactory, classic, authorizedRoots,
        mediaProviders, mediaDurationProbe, mediaSubtitleProbe);
  }

  late final Future<void> ready;
  late final Directory root;
  late final String deviceId;
  late final TaskEngine engine;
  final jobOrigins = JobOrigins();
  final diskDeletion = DiskDeletion();
  late final SettingConsent settingConsent;
  late final AppRuntimeFacts appRuntime;
  late final AppRestart appRestart;
  final hooks = HarnessHooks();
  final harnessLocation = HarnessLocation();
  final DownloadRuntime downloads;
  CredentialStore get credentials => CredentialStore.instance;
  CredentialVault get credentialVault => credentials.vault;
  late final MediaRuntime media;
  late final MediaSourcesService mediaSources;
  late final SyncService sync;
  final accounts = AccountsService();
  late final DanmakuRuntime danmaku;
  late final SubtitleLibrary subtitles;
  late final ProgramRuntime programs;
  late final ProgramRepository programRepository;
  late final SettingsRegistry settings;
  late final MeshRuntime mesh;
  late final List<Capability> capabilities;
  final StateSources stateSources = StateSources();
  late final StateCapability state;
  late final ChangeHistory changeHistory;
  late final ActivityInvocations activityInvocations;
  late final Followups followups;
  late final SessionStore sessions;
  late final HarnessMemory memory;
  late final CapabilityCatalogChanges catalogChanges;
  late final UiDataService uiData;
  late final DbService db;
  late final LibraryDataService libraryData;
  LibraryDataService get libraryActions => libraryData;
  final classicScan = ClassicScanExecutor();
  late final TaskResources resources;
  late final BodyEvents events;
  late final SystemSettings automatic;
  late final SystemStorage storage;
  late final DesktopSystem desktopSystem;
  late final SystemDiagnostics diagnostics;
  StreamSubscription<JsonMap>? _networkEvents;
  StreamSubscription<Job>? _bodyTasks;
  final _taskStates = <String, String>{};
  StreamSubscription<void>? _followupEvents;

  /// Something that 动态 shows has just been recorded. Fires after the
  /// record is stored; the view itself stays the only reader of the facts.
  final activityChanges = StreamController<void>.broadcast(sync: true);
  void activityChanged() {
    if (!activityChanges.isClosed) activityChanges.add(null);
  }

  Future<void> _initialize(
      Directory? suppliedRoot,
      DatabaseFactory? databaseFactory,
      ClassicMetadataPort classic,
      Iterable<String> Function() authorizedRoots,
      Iterable<MetadataProvider>? mediaProviders,
      Future<int?> Function(String) mediaDurationProbe,
      Future<JsonMap> Function(String) mediaSubtitleProbe) async {
    await debugDandanplayClaimNames(credentialVault);
    root = suppliedRoot ??
        Directory(
            '${(await StorageService.getAppStorageDirectory()).path}/next');
    deviceId = await loadDeviceIdentity(root);
    final database = await openNextDatabase(root, factory: databaseFactory);
    final jobs = SqliteJobStore.fromDatabase(database);
    changeHistory = ChangeHistory(database);
    BodyChanges.attached = changeHistory;
    activityInvocations = ActivityInvocations(
        database, File('${root.path}/journal.jsonl'),
        changed: activityChanged);
    media = await MediaRuntime.create(root, jobs.database, deviceId,
        classic: classic,
        authorizedRoots: authorizedRoots,
        providers: mediaProviders,
        durationProbe: mediaDurationProbe);
    mediaSources = MediaSourcesService(media.service.store);
    sync = SyncService(mediaSources);
    for (final provider in ['dandanplay', 'bangumi']) {
      changeHistory.seed('account:$provider', [
        {'id': provider, ...accounts.status(provider)}..remove('provider')
      ]);
    }
    mesh = MeshRuntime(
        root: root,
        vault: credentialVault,
        token: () async => credentials.read(
            await SharedPreferences.getInstance(), 'dandanplay_token'));
    settings = SettingsRegistry(database, [
      NextUiPreference.setting(),
      ...ApplicationSettings.entries(),
      ...ClassicSettings.entries(),
      ...DownloadSettings.entries(),
      ...sync.settings(),
      meshAddressSetting(mesh),
      harnessLocation.setting
    ]);
    SettingsAccess.registry = settings;
    settingConsent = SettingConsent(settings);
    ApplicationSettings.authorizePath = (path, {directory = false}) =>
        media.service.authorizedPath(path, directory: directory);
    danmaku = await DanmakuRuntime.create(media.service.store,
        authorizeLocalFile: media.service.authorizedPath);
    danmaku.service.exporter = DanmakuExporter(danmaku.service.store,
        (path) => media.service.authorizedPath(path, directory: true));
    subtitles = SubtitleLibrary(media.service, root, probe: mediaSubtitleProbe);
    programs = ProgramRuntime(enabled: await loadProgramPermission(root),
        location: harnessLocation);
    programRepository = ProgramRepository(programs);
    final helpers = Helpers();
    final executors = [
      helpers,
      downloads.executor,
      ...media.executors,
      ...mediaSourcesExecutors(mediaSources),
      SyncExecutor(sync),
      RemoteConnectionExecutor(mediaSources),
      ...accountExecutors(accounts),
      ...danmaku.executors,
      hooks,
      programs,
      diskDeletion,
      settingConsent,
      classicScan,
    ];
    engine = TaskEngine(store: jobs, ownerDeviceId: deviceId,
        originOf: jobOrigins.of, executors: [
      for (final executor in executors) OriginExecutor(executor, database)
    ]);
    jobOrigins.lookup = engine.get;
    hooks.engine = engine;
    programs.engine = engine;
    diskDeletion.engine = engine;
    settingConsent.engine = engine;
    followups = Followups(database, engine, harnessLocation);
    memory = HarnessMemory(harnessLocation, settings, followups.discover);
    catalogChanges =
        CapabilityCatalogChanges(File('${root.path}/capability_catalog.json'));
    programs.returnTarget = followups.downloadReturnTarget;
    accounts.returnTarget = followups.downloadReturnTarget;
    diskDeletion.returnTarget = followups.downloadReturnTarget;
    settingConsent.returnTarget = followups.downloadReturnTarget;
    mediaSources.returnTarget = followups.downloadReturnTarget;
    attachMeshDelivery(mesh, followups);
    mesh.describeSelf = () async {
      await harnessLocation.ready;
      return {'host': 'gui', 'conversationHost': true,
        'mediaRoots': media.service.authorizedRoots().toList(),
        'programExecution': {'enabled': programs.enabled,
          'workingDirectory': harnessLocation.path,
          'defaultShell': Platform.isWindows ? 'cmd' : 'sh'}};
    };
    helpers.engine = engine;
    helpers.followups = followups;
    followups.helpers = helpers;
    sessions = SessionStore(database);
    hooks.scheduleError = (error) async {
      await followups.discover({'title': '定时配置无效',
        'source': 'hooks/schedules.json', 'facts': {'error': error}},
        Invocation(origin: 'application'));
    };
    hooks.observeEvent = followups.hookEvent;
    BodySignals.emit = (event, id, facts) async { await hooks.emit(event, id, facts); };
    downloads.attach(engine, root);
    resources = TaskResources(engine, downloads.downloads, helpers);
    await resources.load();
    classicScan.matchingConcurrency = () => resources.metadataConcurrency;
    automatic = SystemSettings(danmaku.sidecars, subtitles);
    settings.register([...resources.settings(), ...automatic.entries()]);
    await automatic.load();
    followups.libraryEnabled = () => automatic.libraryNotifyEnabled;
    followups.describeLibraryFiles =
        (entries) => describeLibraryArrivals(media.service.store, entries);
    ScanService.startupRefreshAllowed = () async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('labs_use_next_interface') != true || automatic.startupScanEnabled;
    };
    events = BodyEvents(database);
    followups.eventCommitted = events.changed;
    settings.onChanged = (facts) async {
      activityChanged();
      await hooks.emit('settings.changed', facts['key'] as String, facts);
    };
    changeHistory.onRecorded = activityChanged;
    _followupEvents = events.committed.stream.listen((_) => activityChanged());
    changeHistory.onChanged = (collection, id, facts) async {
      final domain = collection.split(':').first;
      if (domain == 'subtitle') await hooks.emit('media.assets.changed', id, {'kind': 'subtitle', ...facts});
      if (domain == 'source' || domain == 'source_sort') await hooks.emit('media.sources.state_changed', id, facts);
    };
    _networkEvents = NetworkObservations.changes.stream.listen((facts) {
      unawaited(hooks.emit('network.state_changed', facts['id'] as String, facts));
    });
    _bodyTasks = engine.changes.listen((job) {
      if (job.type == 'harness.hook') {
        activityChanged();
        return;
      }
      final state = '${job.state.wireName}:${job.phase}';
      if (_taskStates[job.jobId] == state) return;
      _taskStates[job.jobId] = state;
      activityChanged();
      unawaited(hooks.emit('task.state_changed', job.jobId, job.toJson()));
    });
    storage = SystemStorage(root, database, hooks);
    desktopSystem = DesktopSystem(media.service, root, hooks);
    diagnostics = SystemDiagnostics(database, media.service, storage, automatic, settings);
    downloads.downloads.returnTarget = followups.downloadReturnTarget;
    media.attach(engine);
    mediaSources.engine = engine;
    accounts.attach(engine);
    danmaku.attach(engine);
    state = StateCapability([...publicStateViews(
        media: media.service,
        settings: settings,
        danmaku: danmaku.service,
        mesh: mesh,
        sources: stateSources), ActivityView(media.service, settings,
            activityInvocations, harnessLocation,
            changeHistory).view, followups.view]);
    uiData = UiDataService(media.service, engine, state, stateSources, root, credentialVault);
    uiData.subtitles = subtitles;
    libraryData = LibraryDataService(uiData, port: ClassicLibrarySources(mediaSources, root));
    final sourceImages = libraryData.port! as ClassicLibrarySources;
    mediaSources.cachedPoster = (id, item) => sourceImages.cachedImage(id, item, 'Primary');
    mediaSources.loadPoster = (id, itemId) async =>
      sourceImages.image(id, await sourceImages.item(id, itemId), 'Primary');
    mediaSources.cachedArtwork = uiData.artwork.cached;
    uiData.libraryData = libraryData;
    libraryData.register(state);
    storage.libraryRoots = media.service.authorizedRoots;
    storage.artworkBusy = () => uiData.artwork.busy;
    uiData.meshLibrary = MeshLibrary(uiData, mesh);
    mediaSources.canonicalEntityId = (id) async {
      await uiData.meshLibrary!.prepareIndex();
      return uiData.meshLibrary!.resolvedId(id);
    };
    stateSources.canonicalEntityId = (id) async => uiData.meshLibrary!.resolvedId(id);
    stateSources.cachedArtwork = uiData.artwork.cached;
    registerMergedLibrary(state, uiData.meshLibrary!);
    await uiData.meshLibrary!.start();
    settings.register([uiData.openingSetting]);
    db = createDbService(
        database: database, media: media.service, uiData: uiData);
    appRuntime = AppRuntimeFacts(
        root: root,
        mesh: mesh,
        programs: programs,
        vault: credentialVault,
        chat: () => followups.chatHost,
        codexHome: Directory(LabProfile.active
            ? '${LabProfile.root}/codex-home'
            : '${Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']}/.codex'),
        managedModelByDefault: !LabProfile.active &&
            (Platform.isMacOS || Platform.isWindows || Platform.isLinux));
    appRestart = AppRestart(
        quit: () => DesktopExitHandler.instance.quit(),
        beforeQuit: settings.drain,
        profileName: LabProfile.name);
    capabilities = List.unmodifiable(diskDeletion.protect(settingConsent.protect([
      CredentialCapability(credentials),
      TaskCapability(engine),
      resources,
      events,
      NetworkCapability(mediaSources),
      storage,
      diagnostics,
      desktopSystem,
      programs.capability,
      programRepository,
      FollowupCapability(followups),
      UiDataCapability(uiData),
      LibraryCapability(libraryData),
      DbCapability(db),
      MeshLibraryCapability(uiData.meshLibrary!),
        MeshFilesCapability(uiData.meshLibrary!.files),
      downloads.capability,
      downloads.metadataCapability,
      media.capability,
      MediaSourcesCapability(mediaSources),
      SyncCapability(sync),
      RemoteAdminCapability(mediaSources),
      AccountsCapability(accounts),
      danmaku.capability,
      SubtitleCapability(subtitles),
      SettingsCapability(settings),
      PrefsCapability(PrefsService(settings)),
      MemoryCapability(memory),
      ClassicOperations(settings),
      AppRuntimeCapability(appRuntime, appRestart),
      MeshCapability(mesh),
      state,
    ])).map(InvocationScopeCapability.new));
    final statusReader = Harness(capabilities);
    Future<JsonMap> readStatus(String action) async {
      final outcome = await statusReader.invokeJson(
          action, {}, Invocation(origin: 'application'));
      if (outcome is Completed) return outcome.value.toJson();
      throw StateError('$action is unavailable');
    }

    registerSystemViews(
        state,
        SystemStatusSources()
          ..sources = () async {
            await mediaSources.ensureInitialized();
            return mediaSources.list(withFacts: true);
          }
          ..accounts = () async {
            return [
              for (final provider in ['dandanplay', 'bangumi'])
                {
                  ...accounts.status(provider),
                  if (provider == 'bangumi')
                    'lastSyncAt': await _bangumiSyncedAt(),
                }
            ];
          }
          ..network = (() => readStatus('network.status'))
          ..storage = (() => readStatus('storage.status'))
          ..scan = (() async {
            final scan = classicScan.scan;
            if (scan == null) {
              throw const Failure(FailureCode.unavailable,
                  'No Classic scan service is attached to this host.');
            }
            return LocalLibraryOperations.scanState(scan);
          })
          ..update = (() => readStatus('app.update.status'))
          ..hooks = hooks.status
          ..downloadEngines = downloads.engineStatus);
    await engine.start();
    await uiData.start();
    followups.start();
    await downloads.start();
    await media.start();
    danmaku.startIndexing();
    subtitles.start();
    mesh.attach(Harness(capabilities));
    await mesh.startConfigured();
    // Once, after an upgrade: the old journal into 动态's tables, off the
    // main isolate and after startup.
    unawaited(activityInvocations.backfill());
  }

  void attachHarness(Harness harness) => mesh.attach(harness);

  /// When Classic last synchronized watch history to Bangumi, if it did.
  static Future<String?> _bangumiSyncedAt() async {
    try {
      return (await BangumiSyncService.getLastSyncTime())
          ?.toUtc()
          .toIso8601String();
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async {
    await ready;
    if (identical(SettingsAccess.registry, settings)) {
      SettingsAccess.registry = null;
      ApplicationSettings.authorizePath = null;
    }
    await settings.drain();
    await storage.close();
    settings.onChanged = null;
    BodySignals.emit = null;
    ScanService.startupRefreshAllowed = null;
    await _networkEvents?.cancel();
    await _bodyTasks?.cancel();
    await _followupEvents?.cancel();
    changeHistory.onChanged = null;
    changeHistory.onRecorded = null;
    if (identical(BodyChanges.attached, changeHistory)) BodyChanges.attached = null;
    await changeHistory.drain();
    await activityInvocations.close();
    await followups.close();
    followups.eventCommitted = null;
    await events.committed.close();
    await activityChanges.close();
    await uiData.close();
    await stateSources.close();
    hooks.observeEvent = null;
    await hooks.disable();
    harnessLocation.dispose();
    await mesh.close();
    await downloads.stop();
    await danmaku.stopRestoring();
    await danmaku.stopIndexing();
    await subtitles.close();
    await programRepository.drain();
    await programs.close();
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
