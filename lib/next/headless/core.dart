import '../mesh/files.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../agent_endpoint.dart';
import '../instance_facts.dart';
import '../app_capabilities.dart';
import '../events/capability.dart';
import '../events/signals.dart';
import '../next_database.dart';
import '../tasks/device_identity.dart';
import '../tasks/job_origin.dart';
import '../tasks/sqlite_job_store.dart';
import '../state/change_history.dart';
import '../db/capability.dart';
import '../db/wiring.dart';
import '../state/query.dart';
import '../state/views.dart';
import '../state/activity.dart';
import '../programs/runtime.dart';
import '../programs/repository.dart';
import '../subtitles/library_io.dart';
import '../subtitles/capability.dart';
import '../capabilities/family_descriptions.dart';
import '../settings/registry.dart';
import '../settings/capability.dart';
import '../media/identity_store.dart';
import '../media/media_service.dart';
import '../media/media_capability.dart';
import '../media/media_executors.dart';
import '../media/media_probe_io.dart' show headlessFfprobe;
import '../media/online_providers.dart';
import '../network/dandanplay_gateway.dart';
import '../../services/dandanplay_http_client.dart';
import '../../utils/network_settings.dart';
import 'routing_preferences.dart' as routing;
import '../danmaku/host.dart';
import '../danmaku/sources.dart';
import '../danmaku/service.dart';
import '../danmaku/store.dart';
import '../danmaku/local_source.dart';
import '../danmaku/executors.dart';
import '../danmaku/capability.dart';
import '../danmaku/export.dart';
import '../danmaku/sidecar.dart';
import '../harness_hooks.dart';
import '../state/system_views.dart';
import '../followups/service.dart';
import '../followups/capability.dart';
import '../ui_data/service.dart';
import '../ui_data/library_service.dart';
import '../ui_data/library_capability.dart';
import '../ui_data/capability.dart';
import '../capabilities/download_capability.dart';
import '../downloads/download_backend.dart';
import '../downloads/download_executor.dart';
import '../downloads/download_service.dart';
import '../downloads/download_source.dart';
import 'ports.dart';
import 'downloads.dart';
import 'job_lifecycle.dart';
import 'native.dart';
import 'vault.dart';
import '../downloads/qbittorrent_hub.dart';
import 'library_roots.dart';
import '../mesh/runtime.dart';
import '../mesh/library.dart';
import '../mesh/library_capability.dart';
import '../mesh/capability.dart';
import '../mesh/delivery.dart';
import '../mesh/chat_guest_host.dart';
import '../mesh/delegation.dart';
import '../mesh/delegation_host.dart';
import '../mesh/delegation_wiring.dart';
import '../mesh/native.dart';
import '../../security/credential_vault.dart';
import '../chat/helpers.dart';
import '../chat/session_store.dart';
import '../memory/capability.dart';
import '../memory/service.dart';
import 'chat_capability.dart';
import 'model.dart';
import 'nipa.dart';
import 'package_layout.dart';

/// Composes the same domain services without attaching Classic or a widget tree.
final class HeadlessCore {
  HeadlessCore(
      {required this.root,
      required this.repository,
      required this.mediaRoots,
      required this.seed,
      required this.agentAssets,
      this.nativeLibrary,
      this.environment,
      this.port = 0});
  final Directory root, repository;

  /// `assets/next/agent`: the DSH manifest and NipaPlay's plugins for Nipa.
  final Directory agentAssets;

  /// What selects the runtime Nipa runs on (`NIPAPLAY_AGENT_RUNTIME`,
  /// `NIPAPLAY_DSH_NODE`, `NIPAPLAY_DSH_ROOT`); the process environment unless
  /// given.
  final Map<String, String>? environment;
  final List<String> mediaRoots;
  final Map<String, List<int>> seed;
  final int port;
  final String? nativeLibrary;
  late final MeshRuntime mesh;
  late final MeshDelegations delegations;
  late final AgentDelegations delegationHost;
  late final ChatGuests chatGuests;
  late final HeadlessVault vault;
  late final TaskEngine engine;
  late final MediaService media;
  late final AgentEndpoint endpoint;
  late final Followups followups;
  late final SettingsRegistry settings;
  late final ChangeHistory history;
  late final UiDataService uiData;
  late final LibraryDataService libraryData;
  late final SidecarIndexer sidecars;
  late final DownloadExecutor downloadExecutor;
  late final DownloadService downloads;
  late final HeadlessDownloadBackend backend;
  late final ProgramRuntime programs;
  late final ProgramRepository programRepository;
  late final SubtitleLibrary subtitles;
  late final BodyEvents bodyEvents;
  late final HeadlessModel model;
  late final HeadlessNipa nipa;
  late final HarnessMemory memory;
  final hooks = HarnessHooks();
  final _client = http.Client();
  DandanplayHttpClient? _dandanplay;
  DandanplayHttpClient? _danmakuClient;
  StreamSubscription<Job>? _jobs;
  StreamSubscription<JsonMap>? _files;
  Future<void> _events = Future.value();
  Database? _database;
  bool _resourcesReady = false, _closed = false;
  final _executors = <HeadlessExecutor>[];

  Future<AgentEndpointRunning> start() async {
    try {
      return await _start();
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<AgentEndpointRunning> _start() async {
    final database = _database = await openNextDatabase(root);
    history = ChangeHistory(database);
    BodyChanges.attached = history;
    final identity = await loadDeviceIdentity(root);
    await Directory(p.join(root.path, 'downloads')).create(recursive: true);
    await routing.SharedPreferences.configure(root);
    vault = HeadlessVault(Directory(p.join(root.path, 'vault')));
    Future<Map<String, String>> authorization() async {
      final token = await vault.read(const CredentialRef('preferences', 'dandanplay_token'));
      return token == null || token.isEmpty ? {} : {'Authorization': 'Bearer $token'};
    }
    final ddp = _dandanplay = DandanplayHttpClient(authorization: authorization);
    final gateway = DandanplayGateway(client: ddp);
    media = MediaService(
        store: IdentityStore(database, identity),
        providers: onlineMetadataProviders(credentials: HostVaultResolver(vault),
            tmdb: _client, bangumi: _client, dandanplay: gateway),
        classic: NoClassic(),
        authorizedRoots: () => [...mediaRoots, '${root.path}/downloads']);
    final native =
        HeadlessNative(nativeLibrary ?? HeadlessNative.defaultLibrary());
    // Listens on the LAN like any other device (mutual TLS guards it);
    // `loopbackOnly` in mesh.json keeps it to this machine.
    mesh = MeshRuntime(
        root: root,
        vault: vault,
        token: () =>
            vault.read(const CredentialRef('preferences', 'dandanplay_token')),
        authorize: (_, __) async => null,
        native: MeshNative(bridge: native));
    delegations = createMeshDelegations(mesh);
    mesh.describeSelf = () async => {
          'host': 'headless',
          // Live: whether Nipa runs on this host now (the agent switch is on
          // and the model, its key and the runtime are in place).
          'conversationHost': nipa.host != null,
          'agent': {
            ...nipa.facts(),
            if (await nipa.host?.conversationCount() case final count?)
              'conversations': count,
          },
          'mediaRoots': mediaRoots.toList(),
          'mediaReadOnlyScope': ['indexing', 'downloadDestination'],
          'fileOperations': 'processPermissions',
          'downloadDirectory': p.join(root.path, 'downloads'),
          'storageFacts': [
            {
              'role': 'download',
              'readOnly': false,
              ...await native
                      .call('storage', {'path': p.join(root.path, 'downloads')})
                  as JsonMap
            },
            for (final path in mediaRoots)
              {
                'role': 'library',
                'readOnly': true,
                ...await native.call('storage', {'path': path}) as JsonMap
              }
          ],
          'downloadEngine': 'librqbit'
          ,'programExecution': {'enabled': programs.enabled,
            'workingDirectory': repository.path,
            'defaultShell': Platform.isWindows ? 'cmd' : 'sh'}
        };
    settings = SettingsRegistry(database, [meshAddressSetting(mesh)]);
    programs = ProgramRuntime(enabled: await loadProgramPermission(root),
        location: HeadlessRepository(repository.path))
      ..credentialFile = File('${root.path}/endpoint.json');
    programRepository = ProgramRepository(programs);
    subtitles = SubtitleLibrary(media, root);
    SettingsAccess.registry = settings;
    final danmakuHost = HttpDanmakuHost(dandanplay: DandanplayGateway(
        client: _danmakuClient = DandanplayHttpClient(authorization: authorization)));
    final onlineDanmaku = DandanplayDanmakuSource(danmakuHost,
        allowedHosts: NetworkSettings.officialServers.map((s) => Uri.parse(s).host).toList());
    final danmaku = DanmakuService(
        store: DanmakuStore(media.store),
        sources: [DandanplayDanmakuSource(
            ScopedDanmakuHost(danmakuHost, onlineDanmaku.describe),
            allowedHosts: onlineDanmaku.allowedHosts), LocalDanmakuSource(media.authorizedPath)],
        player: NoPlayer());
    final helpers = Helpers();
    final exportRoot =
        await Directory(p.join(root.path, 'exports')).create(recursive: true);
    danmaku.exporter = DanmakuExporter(danmaku.store, (path) async {
      final real = await Directory(path).resolveSymbolicLinks();
      final base = await exportRoot.resolveSymbolicLinks();
      if (!p.equals(real, base) && !p.isWithin(base, real)) {
        throw const Failure(FailureCode.invalidInput,
            'Headless exports must stay under data/exports; media roots are read-only.');
      }
      return real;
    });
    sidecars = SidecarIndexer(danmaku.store, () async {});
    final downloadConfig = File(p.join(root.path, 'download.json'));
    backend = HeadlessDownloadBackend(
        native: native,
        root: root,
        readOnlyRoots: mediaRoots,
        configuration: await downloadConfig.exists()
            ? jsonDecode(await downloadConfig.readAsString()) as JsonMap
            : const {});
    final library = HeadlessDownloadLibrary(media);
    // The qBittorrents written in qbittorrent.json (logins enrolled in the
    // vault under namespace qbittorrent, key = id). They are tracked when a
    // download names them, never adopted.
    final qbittorrent = QbittorrentHub(
        file: File(p.join(root.path, 'qbittorrent.json')), vault: vault);
    await qbittorrent.load();
    final backends = DownloadBackends([backend, ...qbittorrent.backends]);
    downloadExecutor = DownloadExecutor(
        backends: backends, library: library, isEnabled: () async => true);
    _executors.addAll([
      for (final e in [
        ...mediaExecutors(media),
        ...danmakuExecutors(danmaku),
        hooks,
        programs,
        downloadExecutor,
        helpers,
        delegations
      ])
        HeadlessExecutor(OriginExecutor(e, database))
    ]);
    final jobOrigins = JobOrigins();
    engine = TaskEngine(
        store: HeadlessJobStore(SqliteJobStore.fromDatabase(database)),
        ownerDeviceId: identity,
        originOf: jobOrigins.of,
        executors: _executors);
    jobOrigins.lookup = engine.get;
    media.engine = engine;
    danmaku.engine = engine;
    hooks.engine = engine;
    programs.engine = engine;
    downloadExecutor.engine = engine;
    downloads = DownloadService(
        engine: engine,
        executor: downloadExecutor,
        backends: backends,
        library: library);
    followups =
        Followups(database, engine, HeadlessRepository(repository.path));
    helpers.engine = engine;
    helpers.followups = followups;
    followups.helpers = helpers;
    downloads.returnTarget = followups.downloadReturnTarget;
    programs.returnTarget = followups.downloadReturnTarget;
    attachMeshDelivery(mesh, followups);
    delegationHost = attachMeshDelegation(mesh, delegations, engine, followups);
    chatGuests = attachMeshChatGuests(mesh, followups);
    hooks.observeEvent = followups.hookEvent;
    bodyEvents = BodyEvents(database);
    followups.eventCommitted = bodyEvents.changed;
    BodySignals.emit = (event, id, facts) => hooks.emit(event, id, facts);
    settings.onChanged = (facts) => hooks.emit(
        'settings.changed', facts['key'] as String, facts);
    hooks.scheduleError = (error) async {
      await followups.discover({
        'title': '定时配置无效',
        'source': 'hooks/schedules.json',
        'facts': {'error': error}
      }, Invocation(origin: 'application'));
    };
    final sources = StateSources();
    final activity =
        ActivityInvocations(database, File('${root.path}/journal.jsonl'));
    final activityView = ActivityView(media, settings, activity,
        HeadlessRepository(repository.path), history);
    final state = StateCapability([
      ...publicStateViews(
          media: media,
          settings: settings,
          danmaku: danmaku,
          mesh: mesh,
          sources: sources),
      followups.view,
      activityView.view,
    ]);
    registerSystemViews(state, SystemStatusSources()..hooks = hooks.status);
    uiData = UiDataService(media, engine, state, sources, root, vault);
    libraryData = LibraryDataService(uiData);
    uiData.libraryData = libraryData;
    libraryData.register(state);
    uiData.subtitles = subtitles;
    uiData.meshLibrary = MeshLibrary(uiData, mesh);
    registerMergedLibrary(state, uiData.meshLibrary!);
    await uiData.meshLibrary!.start();
    settings.register([uiData.openingSetting]);
    memory = HarnessMemory(
        HeadlessRepository(repository.path), settings, followups.discover)
      ..redact = uiData.meshLibrary!.worker.redactText;
    model = HeadlessModel(root: root, vault: vault);
    nipa = HeadlessNipa(
        root: root,
        repository: repository,
        agentAssets: agentAssets,
        model: model,
        followups: followups,
        engine: engine,
        jobOrigins: jobOrigins,
        memory: memory,
        sessions: SessionStore(database),
        activityPage: activityView.readPage,
        staleSources: [bodyEvents.committed.stream],
        redact: uiData.meshLibrary!.worker.redactText,
        environment: environment);
    final db = createDbService(database: database, media: media, uiData: uiData);
    final downloadSources =
        DownloadSources(Directory('${root.path}/torrent_sources'));
    late final Harness harness;
    harness = Harness([
      FamilyDescriptionCapability(() => harness.catalog),
      InvocationScopeCapability(HeadlessCapabilities([
        AppCapabilities(host: 'headless', catalog: () => harness.catalog,
            media: media, danmaku: danmaku, settings: settings, vault: vault,
            programEnabled: () => programs.enabled,
            subtitleProbeReady: () => headlessFfprobe != null),
        InstanceCapability(const InstanceFacts(headlessAppVersion)),
        bodyEvents,
        TaskCapability(engine),
        programs.capability,
        programRepository,
        SubtitleCapability(subtitles),
        MeshCapability(mesh),
        MeshDelegationCapability(delegations),
        HeadlessLibraryRoots(root, mediaRoots),
        MemoryCapability(memory),
        HeadlessChatCapability(nipa,
            model: model, programsEnabled: () => programs.enabled),
        MediaCapability(media),
        DanmakuCapability(danmaku),
        SettingsCapability(settings),
        FollowupCapability(followups),
        UiDataCapability(uiData),
        LibraryCapability(libraryData),
        DbCapability(db),
        MeshLibraryCapability(uiData.meshLibrary!),
        MeshFilesCapability(uiData.meshLibrary!.files),
        state,
        HeadlessDownloadMetadata(backend, downloadSources),
        DownloadCapability(
            downloads: downloads,
            deleteAudit:
                JsonlJournal(File('${root.path}/download-audit.jsonl')),
            sources: downloadSources),
      ]))
    ], observers: [
      nextJournal(File('${root.path}/journal.jsonl')),
      activity
    ]);
    endpoint = AgentEndpoint(
        harness: harness,
        seed: seed,
        appVersion: headlessAppVersion,
        nowPlaying: uiData.nowPlaying,
        port: port,
        credentialFile: File('${root.path}/endpoint.json'),
        seedRepository: Directory('${root.path}/harness-seed'));
    nipa.endpoint = endpoint;
    _resourcesReady = true;
    await engine.start();
    await uiData.start();
    followups.start();
    await media.recoverProjections();
    final status = await endpoint.start(repository);
    if (status is! AgentEndpointRunning) {
      throw StateError((status as AgentEndpointFailed).message);
    }
    hooks.enable(repository, endpoint.credentialFile);
    _jobs = engine.changes.listen((job) {
      _events = _events.then((_) => hooks.taskChanged(job));
    });
    _files = media.store.fileChanges.listen((file) {
      _events = _events.then((_) =>
          hooks.emit('library.file_added', file['path'] as String, file));
    });
    sidecars.start();
    subtitles.start();
    mesh.attach(harness);
    await mesh.startConfigured();
    // Nipa comes up in the background (the runtime takes seconds to start);
    // until she does, app.runtime says whether she will and what she lacks.
    nipa.start();
    return status;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_resourcesReady) {
      await _database?.close();
      _client.close();
      _dandanplay?.close();
      _danmakuClient?.close();
      return;
    }
    await nipa.close();
    await endpoint.stop();
    await mesh.close();
    await _jobs?.cancel();
    await _files?.cancel();
    await _events;
    await hooks.disable();
    await sidecars.close();
    await subtitles.close();
    await programRepository.drain();
    await programs.close();
    await followups.close();
    await bodyEvents.committed.close();
    BodySignals.emit = null;
    await uiData.close();
    await media.mutate(() async {});
    await settings.drain();
    await engine.close();
    await Future.wait([for (final executor in _executors) executor.drain()]);
    await history.drain();
    BodyChanges.attached = null;
    SettingsAccess.registry = null;
    await media.store.closeEvents();
    await _database!.close();
    _client.close();
    _dandanplay?.close();
    _danmakuClient?.close();
    final credential = endpoint.credentialFile;
    if (await credential.exists()) await credential.delete();
  }
}
