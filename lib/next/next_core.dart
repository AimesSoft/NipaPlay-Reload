import 'capabilities/app_runtime_capability.dart';
import 'platform/lab_profile.dart';
import 'system/app_restart.dart';
import 'system/app_runtime.dart';
import '../services/desktop_exit_handler.dart';
import 'body/next_body.dart';
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
import 'danmaku/automatic.dart';
import 'danmaku/source.dart';
import 'downloads/download_backend.dart';
import 'downloads/download_runtime.dart';
import 'media/classic_projection.dart';
import 'media/library_arrivals.dart';
import 'media/startup_index.dart';
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
import 'mesh/presence.dart';
import 'mesh/runtime.dart';
import 'mesh/library.dart';
import 'mesh/library_capability.dart';
import 'mesh/delivery.dart';
import 'mesh/join_prompt.dart';
import 'mesh/delegation.dart';
import 'mesh/chat_guest_host.dart';
import 'mesh/delegation_host.dart';
import 'mesh/delegation_wiring.dart';
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
import 'chat/dsh_runtime.dart' show AgentRuntimeKind;
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
import 'tasks/nipa_gate.dart';
import 'events/capability.dart';
import 'events/signals.dart';
import 'network/capability.dart';
import 'network/observations.dart';
import 'settings/system_settings.dart';
import 'system/storage.dart';
import 'system/diagnostics.dart';
import 'system/desktop.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/services/classic_mode_policy.dart';
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
    void Function(String)? startupPhase,
  })  : _startupPhase = startupPhase,
        _downloadBackend = downloadBackend,
        _downloadLibrary = downloadLibrary,
        _isDownloaderEnabled = isDownloaderEnabled,
        _loadImportedKeys = loadImportedKeys,
        _downloadRefreshInterval = downloadRefreshInterval {
    stateSources = StateSources();
    ready = _initialize(root, databaseFactory, classic, authorizedRoots,
        mediaProviders, mediaDurationProbe, mediaSubtitleProbe, startupPhase);
  }

  late final Future<void> ready;
  final void Function(String)? _startupPhase;
  late final Directory root;
  late final String deviceId;
  late final TaskEngine engine;
  late final JobOrigins jobOrigins;
  late final DiskDeletion diskDeletion;
  late final SettingConsent settingConsent;
  late final AppRuntimeFacts appRuntime;
  late final AppRestart appRestart;
  late final HarnessHooks hooks;
  late final HarnessLocation harnessLocation;
  late final DownloadRuntime downloads;

  /// Waits for construction and download observation, so callers never touch
  /// the late [downloads] field before the core has assigned it.
  Future<DownloadRuntime> get downloadsReady async {
    await ready;
    return downloads;
  }

  final DownloadBackend _downloadBackend;
  final DownloadLibrary _downloadLibrary;
  final Future<bool> Function() _isDownloaderEnabled;
  final Future<Set<String>> Function() _loadImportedKeys;
  final Duration _downloadRefreshInterval;
  CredentialStore get credentials => CredentialStore.instance;
  CredentialVault get credentialVault => credentials.vault;
  late final MediaRuntime media;
  late final MediaSourcesService mediaSources;
  late final SyncService sync;
  late final AccountsService accounts;
  late final DanmakuRuntime danmaku;
  late final SubtitleLibrary subtitles;
  late final ProgramRuntime programs;
  late final ProgramRepository programRepository;
  late final SettingsRegistry settings;
  late final MeshRuntime mesh;
  late final MeshDelegations delegations;
  late final AgentDelegations delegationHost;
  late final ChatGuests chatGuests;

  /// Asks the person at this screen about a device that just joined
  /// (true: not theirs; null: not answered). Tests replace it.
  Future<bool?> Function(JsonMap device) meshJoinPrompt = (device) =>
      showMeshJoinPrompt(device['name'] as String? ?? '未命名设备',
          device['platform'] as String?);
  StreamSubscription<JsonMap>? _joinNotices;
  Future<void> _joinPrompts = Future.value();
  late final List<Capability> capabilities;
  late final StateSources stateSources;
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

  /// Open while Next's interface is: Nipa's own work waits for it (D1).
  late final NipaGate nipaGate;
  bool _nipa = false;
  bool _startupIndexed = false;
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
  late final StreamController<void> activityChanges;

  /// Each recorded settings change ({key, value, origin…}), for what
  /// applies a shared setting as it changes (the player).
  late final StreamController<JsonMap> settingChanges;
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
      Future<JsonMap> Function(String) mediaSubtitleProbe,
      void Function(String)? onStartupPhase) async {
    final startupWatch = Stopwatch()..start();
    void phase(String name) {
      onStartupPhase?.call('startup: $name');
      if (Platform.environment['NIPAPLAY_STARTUP_PROFILE'] == '1') {
        stderr.writeln('[startup] $name ${startupWatch.elapsedMicroseconds}us');
      }
      startupWatch.reset();
    }

    phase('initialize entered');
    await Future<void>.delayed(Duration.zero);
    jobOrigins = JobOrigins();
    diskDeletion = DiskDeletion();
    phase('core: task state');
    await Future<void>.delayed(Duration.zero);
    hooks = HarnessHooks();
    harnessLocation = HarnessLocation();
    accounts = AccountsService();
    phase('core: services');
    await Future<void>.delayed(Duration.zero);
    nipaGate = NipaGate();
    activityChanges = StreamController<void>.broadcast(sync: true);
    settingChanges = StreamController<JsonMap>.broadcast(sync: true);
    phase('core: streams');
    await Future<void>.delayed(Duration.zero);
    downloads = DownloadRuntime(
        backend: _downloadBackend,
        library: _downloadLibrary,
        isEnabled: _isDownloaderEnabled,
        loadImportedKeys: _loadImportedKeys,
        refreshInterval: _downloadRefreshInterval);
    phase('downloads runtime');
    await debugDandanplayClaimNames(credentialVault);
    phase('debug claims');
    root = suppliedRoot ??
        Directory(
            '${(await StorageService.getAppStorageDirectory()).path}/next');
    phase('root');
    deviceId = await loadDeviceIdentity(root);
    phase('device identity');
    final database = await openNextDatabase(root, factory: databaseFactory);
    phase('database open');
    final jobs = SqliteJobStore.fromDatabase(database);
    changeHistory = ChangeHistory(database);
    BodyChanges.attached = changeHistory;
    activityInvocations = ActivityInvocations(
        database, File('${root.path}/journal.jsonl'),
        changed: activityChanged);
    phase('database wiring');
    await Future<void>.delayed(Duration.zero);
    media = await MediaRuntime.create(root, jobs.database, deviceId,
        classic: classic,
        authorizedRoots: authorizedRoots,
        providers: mediaProviders,
        durationProbe: mediaDurationProbe);
    phase('media runtime');
    await Future<void>.delayed(Duration.zero);
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
    delegations = createMeshDelegations(mesh);
    _joinNotices = mesh.joinNotices.listen((device) {
      _joinPrompts = _joinPrompts.then((_) => _askAboutJoin(device)).catchError(
          (Object _) {});
    });
    final nextUiEntry = NextUiPreference.setting();
    phase('settings entries: next ui');
    await Future<void>.delayed(Duration.zero);
    final applicationEntries = await ApplicationSettings.entriesChunked();
    phase('settings entries: application');
    await Future<void>.delayed(Duration.zero);
    final classicEntries = ClassicSettings.entries();
    phase('settings entries: classic');
    await Future<void>.delayed(Duration.zero);
    final downloadEntries = DownloadSettings.entries();
    phase('settings entries: download');
    await Future<void>.delayed(Duration.zero);
    final syncEntries = sync.settings();
    phase('settings entries: sync');
    await Future<void>.delayed(Duration.zero);
    final meshEntry = meshAddressSetting(mesh);
    final harnessEntry = harnessLocation.setting;
    phase('settings entries: mesh harness');
    settings = SettingsRegistry(database, const []);
    await settings.registerChunked([
      nextUiEntry,
      ...applicationEntries,
      ...classicEntries,
      ...downloadEntries,
      ...syncEntries,
      meshEntry,
      harnessEntry
    ]);
    phase('settings registry');
    await Future<void>.delayed(Duration.zero);
    SettingsAccess.registry = settings;
    settingConsent = SettingConsent(settings);
    ApplicationSettings.authorizePath = (path, {directory = false}) =>
        media.service.authorizedPath(path, directory: directory);
    danmaku = await DanmakuRuntime.create(media.service.store,
        authorizeLocalFile: media.service.authorizedPath);
    danmaku.automatic = AutomaticDanmaku(danmaku.service, matchHash: (path) async {
      final result = await media.service.matchHashes([{'path': path}]);
      final files = result['files'] as List;
      final found = files.single as JsonMap;
      if (found['error'] != null) return [];
      return [
        for (final candidate in found['candidates'] as List)
          for (final episode in (candidate as JsonMap)['episodes'] as List)
            DanmakuVideo(
                sourceId: 'dandanplay',
                videoId: ((episode as JsonMap)['ref'] as JsonMap)['externalId'] as String,
                title: '${candidate['title']} · ${episode['title']}',
                durationMs: 0,
                objectType: 'episode')
      ];
    });
    danmaku.service.exporter = DanmakuExporter(danmaku.service.store,
        (path) => media.service.authorizedPath(path, directory: true));
    subtitles = SubtitleLibrary(media.service, root, probe: mediaSubtitleProbe);
    programs = ProgramRuntime(
        enabled: await loadProgramPermission(root), location: harnessLocation);
    programRepository = ProgramRepository(programs);
    phase('danmaku subtitles programs');
    await Future<void>.delayed(Duration.zero);
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
      delegations,
    ];
    engine = TaskEngine(
        store: jobs,
        ownerDeviceId: deviceId,
        originOf: jobOrigins.of,
        executors: [
          for (final executor in executors)
            OriginExecutor(
                nipaTaskTypes.contains(executor.type)
                    ? NipaGatedExecutor(executor, nipaGate)
                    : executor,
                database)
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
    delegationHost = attachMeshDelegation(mesh, delegations, engine, followups);
    chatGuests = attachMeshChatGuests(mesh, followups);
    mesh.describeSelf = () async {
      await harnessLocation.ready;
      final chat = followups.chatHost;
      final running = chat != null && chat.available;
      return {
        'host': 'gui',
        'conversationHost': true,
        // Live: whether Nipa runs on this device now (Next's interface is
        // open, the agent is on and her runtime and model are in place).
        'agent': {
          'runs': running,
          if (!running)
            'reason': NextBody.bodyOnly
                ? 'This device does not run Nipa; it speaks with the Nipa of another device.'
                : followups.unavailableReason ??
                    'Nipa is not running on this device.',
          if (running) ...{
            'model': chat.model,
            'provider': chat.provider,
            'busy': chat.threadLiveness.keys.any(chat.busyFor),
            if (await chat.conversationCount() case final count?)
              'conversations': count,
          },
        },
        'mediaRoots': media.service.authorizedRoots().toList(),
        'programExecution': {
          'enabled': programs.enabled,
          'workingDirectory': harnessLocation.path,
          'defaultShell': Platform.isWindows ? 'cmd' : 'sh'
        }
      };
    };
    helpers.engine = engine;
    helpers.followups = followups;
    followups.helpers = helpers;
    sessions = SessionStore(database);
    hooks.scheduleError = (error) async {
      await followups.discover({
        'title': '定时配置无效',
        'source': 'hooks/schedules.json',
        'facts': {'error': error}
      }, Invocation(origin: 'application'));
    };
    downloads.attach(engine, root, vault: credentialVault);
    resources = TaskResources(engine, downloads.downloads, helpers);
    await resources.load();
    phase('engine resources');
    await Future<void>.delayed(Duration.zero);
    classicScan.matchingConcurrency = () => resources.metadataConcurrency;
    automatic = SystemSettings(danmaku.sidecars, subtitles);
    settings.register([...resources.settings(), ...automatic.entries()]);
    await automatic.load();
    phase('automatic settings');
    await Future<void>.delayed(Duration.zero);
    followups.libraryEnabled = () => automatic.libraryNotifyEnabled;
    followups.describeLibraryFiles =
        (entries) => describeLibraryArrivals(media.service.store, entries);
    ScanService.startupRefreshAllowed = ClassicModePolicy.allowsImplicitWork;

    events = BodyEvents(database);
    followups.eventCommitted = events.changed;
    settings.onChanged = (facts) async {
      if (!settingChanges.isClosed) settingChanges.add(facts);
      activityChanged();
      await hooks.emit('settings.changed', facts['key'] as String, facts);
    };
    changeHistory.onRecorded = activityChanged;
    _followupEvents = events.committed.stream.listen((_) => activityChanged());
    changeHistory.onChanged = (collection, id, facts) async {
      final domain = collection.split(':').first;
      if (domain == 'subtitle') {
        await hooks
            .emit('media.assets.changed', id, {'kind': 'subtitle', ...facts});
      }
      if (domain == 'source' || domain == 'source_sort') {
        await hooks.emit('media.sources.state_changed', id, facts);
      }
    };
    _networkEvents = NetworkObservations.changes.stream.listen((facts) {
      unawaited(
          hooks.emit('network.state_changed', facts['id'] as String, facts));
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
    phase('event wiring');
    await Future<void>.delayed(Duration.zero);
    storage = SystemStorage(root, database, hooks);
    desktopSystem = DesktopSystem(media.service, root, hooks);
    diagnostics = SystemDiagnostics(
        database, media.service, storage, automatic, settings);
    downloads.downloads.returnTarget = followups.downloadReturnTarget;
    media.attach(engine);
    mediaSources.engine = engine;
    accounts.attach(engine);
    danmaku.attach(engine);
    final activityView = ActivityView(media.service, settings,
        activityInvocations, harnessLocation, changeHistory);
    final publicViews = publicStateViews(
        media: media.service,
        settings: settings,
        danmaku: danmaku.service,
        mesh: mesh,
        sources: stateSources);
    phase('state: public views');
    await Future<void>.delayed(Duration.zero);
    state = StateCapability([...publicViews, activityView.view, followups.view])
      ..prepareActivity = activityView.prepare;
    phase('state: capability');
    await Future<void>.delayed(Duration.zero);
    uiData = UiDataService(
        media.service, engine, state, stateSources, root, credentialVault);
    uiData.subtitles = subtitles;
    phase('state: ui data');
    await Future<void>.delayed(Duration.zero);
    libraryData = LibraryDataService(uiData,
        port: ClassicLibrarySources(mediaSources, root));
    phase('state: library data');
    await Future<void>.delayed(Duration.zero);
    final sourceImages = libraryData.port! as ClassicLibrarySources;
    mediaSources.cachedPoster =
        (id, item) => sourceImages.cachedImage(id, item, 'Primary');
    mediaSources.loadPoster = (id, itemId) async =>
        sourceImages.image(id, await sourceImages.item(id, itemId), 'Primary');
    mediaSources.cachedArtwork = uiData.artwork.cached;
    uiData.libraryData = libraryData;
    libraryData.register(state);
    storage.libraryRoots = media.service.authorizedRoots;
    storage.artworkBusy = () => uiData.artwork.busy;
    uiData.meshLibrary = MeshLibrary(uiData, mesh,
        subtitleProbe: mediaSubtitleProbe, startupPhase: _startupPhase,
        prepareDanmaku: (path, fileId, episodeId) async {
          await danmaku.automatic!.prepare(path, fileId: fileId, episodeId: episodeId);
        });
    memory.redact = uiData.meshLibrary!.worker.redactText;
    hooks.redact = uiData.meshLibrary!.worker.redactJson;
    phase('state: mesh library');
    await Future<void>.delayed(Duration.zero);
    activityView.workerRead = uiData.meshLibrary!.worker.activityRows;
    activityView.workerReadPage = uiData.meshLibrary!.worker.activityRowsPage;
    resources.queuedJobs = uiData.meshLibrary!.worker.countQueuedJobs;
    phase('state ui mesh');
    await Future<void>.delayed(Duration.zero);
    mediaSources.canonicalEntityId = (id) async {
      await uiData.meshLibrary!.prepareIndex();
      return await uiData.meshLibrary!.resolvedId(id);
    };
    stateSources.canonicalEntityId =
        (id) async => await uiData.meshLibrary!.resolvedId(id);
    stateSources.cachedArtwork = uiData.artwork.cached;
    registerMergedLibrary(state, uiData.meshLibrary!);
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
        defaultRuntime: LabProfile.active &&
                File('${LabProfile.root}/codex-home/config.toml').existsSync()
            ? AgentRuntimeKind.codex
            : AgentRuntimeKind.dsh,
        managedModelByDefault: !LabProfile.active &&
            (Platform.isMacOS || Platform.isWindows || Platform.isLinux));
    appRestart = AppRestart(
        quit: () => DesktopExitHandler.instance.quit(),
        beforeQuit: settings.drain,
        profileName: LabProfile.name);
    final rawCapabilities = <Capability>[
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
    ];
    phase('capabilities: first group');
    await Future<void>.delayed(Duration.zero);
    rawCapabilities.addAll([
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
    ]);
    phase('capabilities: second group');
    await Future<void>.delayed(Duration.zero);
    rawCapabilities.addAll([
      SubtitleCapability(subtitles),
      SettingsCapability(settings),
      PrefsCapability(PrefsService(settings)),
      MemoryCapability(memory),
      ClassicOperations(settings),
      AppRuntimeCapability(appRuntime, appRestart),
      MeshCapability(mesh),
      MeshDelegationCapability(delegations),
      state,
    ]);
    phase('capabilities: values');
    await Future<void>.delayed(Duration.zero);
    final consentCapabilities = settingConsent.protect(rawCapabilities);
    phase('capabilities: setting consent');
    await Future<void>.delayed(Duration.zero);
    final protectedCapabilities = diskDeletion.protect(consentCapabilities);
    phase('capabilities: deletion consent');
    await Future<void>.delayed(Duration.zero);
    capabilities = List.unmodifiable(
        protectedCapabilities.map(InvocationScopeCapability.new));
    phase('capabilities');
    await Future<void>.delayed(Duration.zero);
    final statusReader = Harness(capabilities);
    await Future<void>.delayed(Duration.zero);
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
            return LocalLibraryOperations.scanState(scan, engine: engine);
          })
          ..update = (() => readStatus('app.update.status'))
          ..hooks = hooks.status
          ..downloadEngines = downloads.engineStatus
          ..downloadTorrents = downloads.qbittorrentTorrents);
    phase('system views');
    await Future<void>.delayed(Duration.zero);
    await engine.start();
    phase('engine start');
    await Future<void>.delayed(Duration.zero);
    await downloads.start();
    phase('downloads start');
    await Future<void>.delayed(Duration.zero);
    await media.start();
    phase('media start');
    mesh.attach(statusReader);
    // Once, after an upgrade: the old journal into 动态's tables, off the
    // main isolate and after startup.
    unawaited(activityInvocations.backfill());
  }

  /// Nipa's services run only while Next's interface is open (D1): what
  /// keeps her interface's data fresh, her followups, the indexing of
  /// sidecar danmaku and subtitles, the mesh, the events her hooks and
  /// followups take, and her own tasks. The data layer Classic shares
  /// (database, downloads, media, settings, tasks) runs regardless.
  Future<void> startNipa() async {
    void phaseNipa(String name) => _startupPhase?.call(name);
    await ready;
    if (_nipa) return;
    _nipa = true;
    if (!_startupIndexed) {
      await classicScan.scan?.foldersReady;
      _startupIndexed = true;
      automatic.startupScanStatus = await submitStartupIndex(
        enabled: automatic.startupScanEnabled,
        roots: media.service.authorizedRoots(),
        submit: (root) async {
          final path =
              await media.service.authorizedPath(root, directory: true);
          await media.service.submit('media.scan', {'root': path});
        },
      );
    }
    hooks.observeEvent = followups.hookEvent;
    BodySignals.emit = (event, id, facts) async {
      await hooks.emit(event, id, facts);
    };
    await uiData.meshLibrary!.start(background: false);
    phaseNipa('startup: Nipa mesh library');
    // The first pass over every local file is one library-worker request.
    // Directory walks, candidate matching, parsing and the final writes all
    // stay off the UI isolate; this turn only submits the pass, receives two
    // small summaries and publishes one change.
    final indexer = uiData.meshLibrary!.worker;
    danmaku.sidecars.watch();
    subtitles.watch();
    danmaku.sidecars.beginBulk();
    subtitles.beginBulk();
    try {
      final preferences = await subtitles.indexPreferences();
      final indexed = await indexer.reconcileIndexers(
        danmaku: danmaku.sidecars.enabled,
        subtitles: subtitles.enabled,
        subtitlePreferences: preferences,
      );
      final sidecars = indexed['sidecars'] as JsonMap?;
      final subtitleFacts = indexed['subtitles'] as JsonMap?;
      danmaku.sidecars.finishBulk(sidecars);
      subtitles.finishBulk(subtitleFacts);
      if ((sidecars?['changed'] as int? ?? 0) +
              (subtitleFacts?['changed'] as int? ?? 0) >
          0) {
        uiData.notifyLibraryChanged();
      }
    } catch (error) {
      danmaku.sidecars.finishBulk(null, error: error);
      subtitles.finishBulk(null, error: error);
      rethrow;
    }
    phaseNipa('startup: Nipa indexers');
    await mesh.startConfigured();
    phaseNipa('startup: Nipa mesh configured');
    // One worker round now sees the complete startup input, including the
    // account and peers chosen while joining Mesh. Polls and the full followup
    // sweep stay behind it: both read the shared database on this isolate and
    // otherwise make the worker wait look like main-thread catalogue work.
    await uiData.meshLibrary!.prepareIndex();
    phaseNipa('startup: Nipa mesh prepared');
    await uiData.start();
    phaseNipa('startup: Nipa ui data');
    followups.start();
    phaseNipa('startup: Nipa followups');
    uiData.meshLibrary!.startPolling();
    nipaGate.set(true);
  }

  /// A device joined that this one had not seen. The person is asked once
  /// they are at a screen: theirs, or removed on the spot. No answer leaves it
  /// to be asked again the next time.
  Future<void> _askAboutJoin(JsonMap device) => answerJoin(device,
      prompt: meshJoinPrompt,
      remove: mesh.revoke,
      acknowledge: mesh.acknowledgeJoin);

  /// Whether Nipa's services run, for lab observation.
  bool get nipaRunning => _nipa;

  /// Next's interface closed: Nipa's services stop until [startNipa].
  Future<void> stopNipa() async {
    await ready;
    if (!_nipa) return;
    _nipa = false;
    nipaGate.set(false);
    // The programs she runs end with her, not later in Classic.
    await programs.cancelRunning(reason: 'next_interface_closed');
    hooks.observeEvent = null;
    BodySignals.emit = null;
    await followups.pause();
    await uiData.pause();
    await uiData.meshLibrary?.pause();
    await danmaku.pauseIndexing();
    await subtitles.pause();
    // The others hear that this device now shows the other interface, so a
    // call to it fails at once and says why, instead of waiting for a refusal.
    await mesh.announcePresence(PresenceState.classic);
    await mesh.stop();
    // The disk space watches she asked for end with her.
    await storage.close();
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
    if (identical(BodyChanges.attached, changeHistory)) {
      BodyChanges.attached = null;
    }
    await changeHistory.drain();
    await activityInvocations.close();
    await followups.close();
    followups.eventCommitted = null;
    await events.committed.close();
    await activityChanges.close();
    await settingChanges.close();
    await uiData.close();
    await stateSources.close();
    hooks.observeEvent = null;
    await hooks.disable();
    harnessLocation.dispose();
    await _joinNotices?.cancel();
    await _joinPrompts;
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
