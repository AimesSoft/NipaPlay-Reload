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
import '../next_database.dart';
import '../tasks/device_identity.dart';
import '../tasks/sqlite_job_store.dart';
import '../state/change_history.dart';
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
import '../media/providers.dart';
import '../media/provider_transport.dart';
import '../danmaku/service.dart';
import '../danmaku/store.dart';
import '../danmaku/local_source.dart';
import '../danmaku/executors.dart';
import '../danmaku/capability.dart';
import '../danmaku/export.dart';
import '../danmaku/sidecar.dart';
import '../harness_hooks.dart';
import '../followups/service.dart';
import '../followups/capability.dart';
import '../ui_data/service.dart';
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
import 'library_roots.dart';
import '../mesh/runtime.dart';
import '../mesh/library.dart';
import '../mesh/library_capability.dart';
import '../mesh/capability.dart';
import '../mesh/delivery.dart';
import '../mesh/native.dart';
import '../../security/credential_vault.dart';

/// Composes the same domain services without attaching Classic or a widget tree.
final class HeadlessCore {
  HeadlessCore(
      {required this.root,
      required this.repository,
      required this.mediaRoots,
      required this.seed,
      this.nativeLibrary,
      this.port = 0});
  final Directory root, repository;
  final List<String> mediaRoots;
  final Map<String, List<int>> seed;
  final int port;
  final String? nativeLibrary;
  late final MeshRuntime mesh;
  late final HeadlessVault vault;
  late final TaskEngine engine;
  late final MediaService media;
  late final AgentEndpoint endpoint;
  late final Followups followups;
  late final SettingsRegistry settings;
  late final ChangeHistory history;
  late final UiDataService uiData;
  late final SidecarIndexer sidecars;
  late final DownloadExecutor downloadExecutor;
  late final DownloadService downloads;
  late final HeadlessDownloadBackend backend;
  late final ProgramRuntime programs;
  late final ProgramRepository programRepository;
  late final SubtitleLibrary subtitles;
  final hooks = HarnessHooks();
  final _client = http.Client();
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
    media = MediaService(
        store: IdentityStore(database, identity),
        providers: [
          BangumiMetadataProvider(HttpMetadataTransport(
              provider: 'bangumi',
              baseUri: Uri.parse('https://api.bgm.tv'),
              client: _client))
        ],
        classic: NoClassic(),
        authorizedRoots: () => [...mediaRoots, '${root.path}/downloads']);
    vault = HeadlessVault(Directory(p.join(root.path, 'vault')));
    final native =
        HeadlessNative(nativeLibrary ?? HeadlessNative.defaultLibrary());
    mesh = MeshRuntime(
        root: root,
        vault: vault,
        token: () =>
            vault.read(const CredentialRef('preferences', 'dandanplay_token')),
        forceLoopback: true,
        authorize: (_, __) async => null,
        native: MeshNative(bridge: native));
    mesh.describeSelf = () async => {
          'host': 'headless',
          'conversationHost': false,
          'mediaRoots': mediaRoots.toList(),
          'mediaReadOnly': true,
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
    final danmaku = DanmakuService(
        store: DanmakuStore(media.store),
        sources: [LocalDanmakuSource(media.authorizedPath)],
        player: NoPlayer());
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
    final backends = DownloadBackends([backend]);
    downloadExecutor = DownloadExecutor(
        backends: backends, library: library, isEnabled: () async => true);
    _executors.addAll([
      for (final e in [
        ...mediaExecutors(media),
        ...danmakuExecutors(danmaku),
        hooks,
        programs,
        downloadExecutor
      ])
        HeadlessExecutor(OriginExecutor(e, database))
    ]);
    engine = TaskEngine(
        store: HeadlessJobStore(SqliteJobStore.fromDatabase(database)),
        ownerDeviceId: identity,
        executors: _executors);
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
    downloads.returnTarget = followups.downloadReturnTarget;
    programs.returnTarget = followups.downloadReturnTarget;
    attachMeshDelivery(mesh, followups);
    hooks.observeEvent = followups.hookEvent;
    hooks.scheduleError = (error) async {
      await followups.discover({
        'title': '定时配置无效',
        'source': 'hooks/schedules.json',
        'facts': {'error': error}
      }, Invocation(origin: 'application'));
    };
    final sources = StateSources();
    final state = StateCapability([
      ...publicStateViews(
          media: media,
          settings: settings,
          danmaku: danmaku,
          mesh: mesh,
          sources: sources),
      followups.view,
      ActivityView(media, settings, File('${root.path}/journal.jsonl'),
          HeadlessRepository(repository.path), history).view,
    ]);
    uiData = UiDataService(media, engine, state, sources, root, NoVault());
    uiData.subtitles = subtitles;
    uiData.meshLibrary = MeshLibrary(uiData, mesh);
    registerMergedLibrary(state, uiData.meshLibrary!);
    await uiData.meshLibrary!.start();
    settings.register([uiData.openingSetting]);
    final downloadSources =
        DownloadSources(Directory('${root.path}/torrent_sources'));
    late final Harness harness;
    harness = Harness([
      FamilyDescriptionCapability(() => harness.catalog),
      InvocationScopeCapability(HeadlessCapabilities([
        InstanceCapability(const InstanceFacts('1.11.10-headless')),
        TaskCapability(engine),
        programs.capability,
        programRepository,
        SubtitleCapability(subtitles),
        MeshCapability(mesh),
        HeadlessLibraryRoots(root, mediaRoots),
        MediaCapability(media),
        DanmakuCapability(danmaku),
        SettingsCapability(settings),
        FollowupCapability(followups),
        UiDataCapability(uiData),
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
      JsonlJournal(File('${root.path}/journal.jsonl'),
          effects: Effect.values.toSet())
    ]);
    endpoint = AgentEndpoint(
        harness: harness,
        seed: seed,
        appVersion: '1.11.10-headless',
        port: port,
        credentialFile: File('${root.path}/endpoint.json'),
        seedRepository: Directory('${root.path}/harness-seed'));
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
    return status;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_resourcesReady) {
      await _database?.close();
      _client.close();
      return;
    }
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
    final credential = endpoint.credentialFile;
    if (await credential.exists()) await credential.delete();
  }
}
