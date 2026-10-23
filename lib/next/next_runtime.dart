import 'dart:async';
import 'dart:io';
import 'followups/service.dart';
import 'platform/background_activity.dart';
import 'platform/loop_lag.dart';
import 'player/classic/classic_backed_playback.dart';
import 'player/next_playback.dart';
import 'player/perf/budget.dart';
import 'ui/shell/next_ui_preference.dart';
import 'runtime/codex_runtime.dart';
import 'settings/classic_host_device_settings.dart';
import 'package:nipaplay/utils/lab_profile.dart';
import 'package:nipaplay/utils/media_source_utils.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/episode_file_selection_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'agent_endpoint.dart';
import 'capabilities/history_capability.dart';
import 'capabilities/family_descriptions.dart';
import 'mesh/playback.dart';
import 'capabilities/watched_history.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'capabilities/library_capability.dart';
import 'capabilities/ui_capability.dart';
import 'capabilities/ui_capture.dart';
import 'capabilities/media_frames.dart';
import 'capabilities/media_frames_erika.dart';
import 'capabilities/media_frames_mdk.dart';
import 'instance_facts.dart';
import 'app_capabilities.dart';
import 'capabilities/classic_ui_open.dart';
import 'capabilities/discover_capability.dart';
import 'capabilities/playback_capability.dart';
import 'capabilities/download_playback_capability.dart';
import 'settings/download_settings.dart';
import 'capabilities/playback_controls_capability.dart';
import 'capabilities/local_library_operations.dart';
import 'capabilities/player_facts.dart';
import 'capabilities/kernel_control.dart';
import 'system/player_native_log.dart';
import 'system/runtime_diagnostics.dart';
import 'system/uncaught_errors.dart';
import 'media/file_indexing.dart';
import 'media_sources/login_dialog.dart';
import 'accounts/login_dialog.dart';
import 'settings/application_settings.dart';
import 'settings/classic_settings.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'harness_location.dart';
import 'harness_hooks.dart';
import 'harness_repository.dart';
import 'chat/chat_host.dart';
import 'chat/dsh_runtime.dart';
import 'memory/recent.dart';
import 'work_detail_bridge.dart';
import 'chat/debug_chat.dart';
import 'ui_data/debug_ui_data.dart';
import 'ui_data/library_service.dart';
import 'harness_redaction.dart';
import 'state/activity.dart';
import 'state/change_history.dart';
import 'settings/host_settings_service.dart';
import 'ui_data/host_settings.dart';
import 'settings/debug_host_settings.dart';

final class NextRuntime extends ChangeNotifier {
  NextRuntime._(this._labs, this._preference, this.playback,
      List<Capability> capabilities) {
    _operations = _initialize(capabilities);
  }

  factory NextRuntime.fromContext(BuildContext context) {
    final labs = context.read<LabsSettingsProvider>();
    ClassicSettings.attached = ClassicSettings(
      appearance: context.read<AppearanceSettingsProvider>(),
      language: context.read<AppLanguageProvider>(),
      home: context.read<HomeSectionsSettingsProvider>(),
      theme: context.read<ThemeNotifier>(),
      developer: context.read<DeveloperOptionsProvider>(),
      labs: labs,
      webdav: context.read<WebDAVQuickAccessProvider>(),
      plugins: context.read<PluginService>(),
    );
    final core = ServiceProvider.nextCore;
    DownloadSettings.provider = context.read<DownloaderSettingsProvider>();
    core.ready.then((_) {
      if (!context.mounted) return;
      core.mediaSources.shared = context.read<SharedRemoteLibraryProvider>();
      core.mediaSources.dandanRemoteProvider =
          context.read<DandanplayRemoteProvider>();
      core.mediaSources.shared!.observeChanges();
      core.mediaSources.updateGuiSelection = (type, ids) => type == 'jellyfin'
          ? context.read<JellyfinProvider>().updateSelectedLibraries(ids)
          : context.read<EmbyProvider>().updateSelectedLibraries(ids);
      core.mediaSources.applySort = (type, sorts) async {
        if (type == 'jellyfin') {
          final provider = context.read<JellyfinProvider>();
          for (final sort in sorts) {
            provider.setLibrarySortSettings(sort['libraryId'] as String,
                sort['sortBy'] as String, sort['sortOrder'] as String);
          }
          await provider.persistLibrarySortSettings();
        } else {
          final provider = context.read<EmbyProvider>();
          for (final sort in sorts) {
            provider.setLibrarySortSettings(sort['libraryId'] as String,
                sort['sortBy'] as String, sort['sortOrder'] as String);
          }
          await provider.persistLibrarySortSettings();
        }
      };
      core.mediaSources.requestPassword = (source, stopped) {
        if (!context.mounted) {
          throw const Failure(
              FailureCode.unavailable, 'The NipaPlay login window has closed.');
        }
        return showMediaSourceLogin(source, stopped);
      };
      core.accounts.requestLogin = showAccountLogin;
    });
    ApplicationSettings.erikaVisible = () =>
        PlayerFactory.isErikaKernelSupported &&
        (globals.isTelevision ||
            PlayerFactory.isHarmonyOS ||
            labs.enableErikaPlayerKernel);
    final settings = context.read<SettingsProvider>();
    final nextPlayback = ClassicBackedPlayback.of(context);
    final history = ServiceProvider.watchHistoryProvider;
    final seriesDetail = BangumiService.instance.getAnimeDetailsFromMemory;
    var meshProxy = false;
    final playback = PlaybackCapability(
      player: nextPlayback.port,
      start: (item) {
        final remote = core.uiData.meshLibrary?.playback.containsKey(item.videoPath) == true;
        if (remote || meshProxy) {
          MeshPlayback.directLoopback(nextPlayback.kernelHost, remote);
        }
        meshProxy = remote;
        return PlaybackService().play(item, episodeFileSelectionHandled: true);
      },
      usesExternalPlayer: () => settings.useExternalPlayer,
      historyItem: WatchHistoryManager.getHistoryItem,
      episodeItem: WatchHistoryManager.getHistoryItemByEpisode,
      fileSelection: EpisodeFileSelectionService(),
    );
    final playbackApi = Harness([playback]);
    core.mediaSources.playItem = (source, itemId, position) async {
      final type = source['type'];
      PlayableItem item;
      if (type == 'dandanplay_remote') {
        final service = core.mediaSources.dandanRemote;
        await core.mediaSources.refreshDandanRemote();
        final episodes =
            service.cachedEpisodes.where((e) => e.entryId == itemId);
        if (episodes.isEmpty) {
          throw const Failure(
              FailureCode.notFound, 'Remote episode not found.');
        }
        final e = episodes.single;
        final url = service.buildEpisodeStreamUrl(
            hash: e.hasHash ? e.hash : null, entryId: e.entryId);
        if (url == null) {
          throw const Failure(
              FailureCode.unavailable, 'Remote episode has no stream.');
        }
        final recorded = await WatchHistoryManager.getHistoryItem(url);
        final history = recorded ??
            WatchHistoryItem(
                filePath: url,
                animeName: e.animeTitle,
                episodeTitle: e.episodeTitle,
                animeId: e.animeId,
                episodeId: e.episodeId,
                watchProgress: 0,
                lastPosition: 0,
                duration: e.duration ?? 0,
                lastWatchTime: DateTime.now(),
                videoHash: e.hash);
        item = PlayableItem(
            videoPath: url,
            actualPlayUrl: url,
            title: e.animeTitle,
            subtitle: e.episodeTitle,
            animeId: e.animeId,
            episodeId: e.episodeId,
            historyItem: history);
      } else if (type == 'nipaplay') {
        final sharing = core.mediaSources.sharing;
        await sharing.refreshLibrary(userInitiated: true);
        PlayableItem? found;
        for (final anime in sharing.animeSummaries) {
          final episodes =
              await sharing.loadAnimeEpisodes(anime.animeId, force: true);
          for (final episode in episodes) {
            if (episode.shareId == itemId) {
              found = sharing.buildPlayableItem(anime: anime, episode: episode);
            }
          }
          if (found != null) break;
        }
        if (found == null) {
          throw const Failure(
              FailureCode.notFound, 'Shared episode not found.');
        }
        item = found;
      } else {
        final path = switch (type) {
          'jellyfin' || 'emby' => '$type://$itemId',
          'smb' => MediaSourceUtils.buildSmbPath(
              core.mediaSources.key(source['sourceId'] as String), itemId),
          'webdav' => MediaSourceUtils.buildWebDavPath(
              core.mediaSources.key(source['sourceId'] as String), itemId),
          _ => throw const Failure(
              FailureCode.invalidInput, 'Unsupported media source.')
        };
        final outcome = await playbackApi.invokeJson(
            'playback.open',
            {'path': path, if (position != null) 'startPositionMs': position},
            BodyChanges.invocation ?? Invocation(origin: 'application'));
        if (outcome is Failed) throw outcome.failure;
        return outcome.toEnvelope();
      }
      if (!await PlaybackService()
          .play(item, episodeFileSelectionHandled: true)) {
        throw const Failure(
            FailureCode.unavailable, 'NipaPlay cannot start playback.');
      }
      if (position != null) {
        await nextPlayback.port.seekTo(Duration(milliseconds: position));
      }
      return {
        'sourceId': source['sourceId'],
        'itemId': itemId,
        'state': nextPlayback.snapshot().toJson()
      };
    };
    return NextRuntime._(labs, context.read<NextUiPreference>(), nextPlayback, [
      WatchedHistoryCapability(WatchedHistory(() => core.media.service,
          () => WatchHistoryDatabase.instance.database, history.refresh),
          mergedLibrary: () => core.uiData.meshLibrary!),
      LibraryCapability(
        history: () => history.history,
        seriesDetail: seriesDetail,
      ),
      HistoryCapability(
        continueWatching: () => history.continueWatchingItems,
        seriesDetail: seriesDetail,
      ),
      playback,
      DiscoverCapability(),
      UiCapability(
        media: () => core.media.service,
        resolveEntity: (id) async {
          if (sourceEntityRef(id, 'work') != null) return {'workId': (await core.uiData.work(id))!.workId};
          final episode = await core.libraryData.validatedSourceRef(id, 'episode');
          if (episode != null) return {'sourcePlayback': await core.mediaSources.play(episode[0], episode[1], expectedServerId: episode.length == 3 ? episode[2] : null)};
          final merged = id.startsWith('mesh-') ? await core.uiData.meshLibrary!.open(id) : null;
          final source = merged?['sourceInfo'] as Map?;
          if (source != null) return {'sourcePlayback': await core.mediaSources.play(source['sourceId'] as String, source['itemId'] as String,
            expectedServerId: source['serverId'] as String?, startPositionMs: merged!['resumeMs'] as int?)};
          return merged;
        },
        openPage: ClassicUiOpen().page,
        openDetail: ClassicUiOpen().detail,
        openWork: WorkDetailBridge.open,
        openTarget: ClassicUiOpen(harnessPath: () async {
          await core.harnessLocation.ready;
          return core.harnessLocation.path;
        }).target,
        close: ClassicUiOpen().close,
        play: (input, invocation) => playbackApi.invokeJson('playback.open', input, invocation)),
    ]);
  }

  final LabsSettingsProvider _labs;
  final NextUiPreference _preference;

  /// What plays, for Next (Classic's player behind it until P1).
  final NextPlayback playback;
  late final Harness _harness;
  late final AgentEndpoint _endpoint;
  late final TaskEngine _taskEngine;
  late final LocalLibraryOperations _localLibrary;
  HarnessLocation? _location;
  late final HarnessHooks _hooks;
  StreamSubscription<Job>? _jobEvents;
  StreamSubscription<JsonMap>? _fileEvents;
  Future<void> _hookEvents = Future.value();
  String? _lastPlaybackStatus, _lastPlaybackPath;
  Set<String> _libraryPaths = {};
  String? _startedPath;
  late Future<void> _operations;
  AgentEndpointStatus _endpointStatus = const AgentEndpointStopped();
  final _loopLag = LoopLag();
  bool _disposed = false;
  ClassicSettings? _classicSettings;
  MeshPlayback? _meshPlayback;
  UncaughtErrors? _uncaught;
  KernelControl? _kernel;
  ChatHost? chat;
  String? chatError;
  final _hostReady = Completer<NextHostSettings>();
  late final PendingHostSettings hostSettings = PendingHostSettings(_hostReady.future);
  HostSettingsService? _hostSettings;
  StreamSubscription<ChatMessage>? _hostEvents;
  StreamSubscription<void>? _activityEvents;
  Future<void> closeChat() async {
    await _hostSettings?.codex?.cancel();
    await _operations;
    // In Classic there is no conversation to close (D1).
    if (!_nipa && chat == null) return;
    await ServiceProvider.nextCore.followups.attach(null, reason: 'Chat host was closed.');
    await chat?.close();
    chat = null;
    _hostSettings?.notify();
  }

  void _syncPluginSettings() {
    final classic = _classicSettings!;
    ServiceProvider.nextCore.settings.replaceGroup('plugins.enabled.', []);
    ServiceProvider.nextCore.settings.replaceGroup('plugins.settings.', classic.pluginEntries());
  }

  StreamSubscription<void>? _calendarChanges;
  Harness get harness => _harness;
  TaskEngine get taskEngine => _taskEngine;
  AgentEndpointStatus get endpointStatus => _endpointStatus;
  String get repositoryPath => _location?.path ?? defaultHarnessPath;
  Future<void> setHarnessPath(String path) async {
    await ServiceProvider.nextCore.settings.set(
        'next.harnessPath', path, Invocation(origin: 'gui'),
        reason: 'Changed harness repository in Labs.');
  }

  Future<void> _initialize(List<Capability> capabilities) async {
    final core = ServiceProvider.nextCore;
    await core.ready;
    _classicSettings = ClassicSettings.current;
    await _classicSettings!.ready;
    await _classicSettings!.plugins.ready;
    _syncPluginSettings();
    core.stateSources.calendar = () async => [
      for (final anime in await BangumiService.instance.cachedCalendarDetails())
        Map<String, Object?>.from(anime.toJson())
    ];
    _classicSettings!.plugins.addListener(_syncPluginSettings);
    core.stateSources.history = () => [
          for (final item in ServiceProvider.watchHistoryProvider.history)
            item.toJson()
        ];
    core.stateSources.continueWatching = () => [
          for (final item
              in ServiceProvider.watchHistoryProvider.continueWatchingItems)
            item.toJson()
        ];
    // Classic tells when its history and calendar move; what Next reads from
    // them is read again then and not before.
    ServiceProvider.watchHistoryProvider.addListener(core.stateSources.changed);
    _calendarChanges = BangumiService.instance.calendarChanges
        .listen((_) => core.stateSources.changed());
    core.stateSources.classicLibrary = classicLibraryStateViews(
      history: () => ServiceProvider.watchHistoryProvider.history,
      seriesDetail: BangumiService.instance.getAnimeDetailsFromMemory,
    );
    _taskEngine = core.engine;
    _hooks = core.hooks;
    _location = core.harnessLocation;
    await _location!.ready;
    await _labs.ready;
    await _preference.ready;
    final root = core.root;
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    const prefix = 'assets/next/harness/';
    final seed = <String, List<int>>{};
    for (final asset
        in manifest.listAssets().where((path) => path.startsWith(prefix))) {
      final data = await rootBundle.load(asset);
      seed[asset.substring(prefix.length)] =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    final packageInfo = await PackageInfo.fromPlatform();
    final instanceFacts = InstanceFacts(packageInfo.version);
    PlayerPerf.install();
    final localPlayback = playback.localOperations(core.settings,
        () => globals.navigatorKey.currentContext!);
    final localLibrary = _localLibrary = LocalLibraryOperations(
        ServiceProvider.scanService, ServiceProvider.watchHistoryProvider, engine: core.engine);
    core.classicScan.scan = ServiceProvider.scanService;
    core.classicScan.history = ServiceProvider.watchHistoryProvider;
    core.storage.playbackActive = () => playback.hasVideo;
    core.storage.scanning = () => ServiceProvider.scanService.isScanning;
    core.diagnostics.playerFacts = playback.diagnostics;
    final uncaught = _uncaught = UncaughtErrors(
        Directory('${root.path}/diagnostics'), appVersion: packageInfo.version)
      ..context = playback.errorContext;
    final kernel =
        _kernel = KernelControl(playback.kernelHost, harness: () => repositoryPath);
    _harness = Harness(
      [
        FamilyDescriptionCapability(() => _harness.catalog),
        AppCapabilities(host: 'gui', catalog: () => _harness.catalog,
            media: core.media.service, danmaku: core.danmaku.service,
            settings: core.settings, vault: core.credentialVault,
            programEnabled: () => core.programs.enabled),
        InstanceCapability(instanceFacts),
        UiCaptureCapability(ClassicUiCapture(instanceFacts).capture),
        MediaFramesCapability(
            engine: PreferredFrameEngine([
              if (PlayerFactory.supportedKernelTypes
                  .contains(PlayerKernelType.erika))
                const ErikaFrameEngine(),
              const MdkFrameEngine(),
            ]),
            outputRoot: () async => Directory(
                '${(await getTemporaryDirectory()).path}/media-frames'),
            episodePath: (animeId, episodeId) async => (await WatchHistoryManager
                    .getHistoryItemByEpisode(animeId, episodeId))
                ?.filePath),
        for (final capability in capabilities)
          InvocationScopeCapability(FileIndexingCapability(capability, core.media.service.store)),
        PlaybackControlsCapability(playback.controls),
        KernelControlCapability(kernel),
        RuntimeDiagnosticsCapability(
            errors: uncaught,
            log: PlayerNativeLog.instance,
            player: () => playback.kernelHost.player,
            logDirectory: Directory('${root.path}/diagnostics/player-logs')),
        InvocationScopeCapability(localPlayback),
        InvocationScopeCapability(localLibrary),
        FileIndexingCapability(
            DownloadPlaybackCapability(
                core.downloads, (item) => PlaybackService().play(item)),
            core.media.service.store),
        ...core.capabilities
      ],
      observers: [nextJournal(File('${root.path}/journal.jsonl')),
        core.activityInvocations],
    );
    core.attachHarness(_harness);
    try {
      // First launch only stores; later ones record what the catalogue gained,
      // lost or re-described since.
      await core.catalogChanges.observe(_harness.catalog,
          appVersion: packageInfo.version, build: packageInfo.buildNumber);
    } catch (error) {
      debugPrint('Capability catalogue fingerprint failed: $error');
    }
    core.catalogChanges.onRecorded = () => chat?.memoryChanged();
    _endpoint = AgentEndpoint(
      harness: _harness,
      appVersion: packageInfo.version,
      catalogChange: () async => (await core.catalogChanges.recent()).firstOrNull,
      instanceFacts: instanceFacts.read,
      nowPlaying: core.uiData.nowPlaying,
      seed: seed,
      seedRepository: Directory('${root.path}/harness-seed'),
      port: LabProfile.active ? 0 : kDebugMode && Platform.environment['NIPAPLAY_AGENT_PORT'] != null
          ? int.parse(Platform.environment['NIPAPLAY_AGENT_PORT']!)
          : 47811,
    );
    core.programs.credentialFile = _endpoint.credentialFile;
    _hostSettings = HostSettingsService(root: root,
      codex: LabProfile.active || !(Platform.isMacOS || Platform.isWindows || Platform.isLinux)
        ? null : CodexRuntime.desktop(
        root: Directory('${root.path}/codex-runtime'),
        notify: () => _hostSettings?.notify(),
        inUse: () => chat?.available == true),
      device: ClassicHostDeviceSettings(vault: core.credentialVault,
        webServer: ServiceProvider.webServer,
        spoilerChanged: playback.spoilerKeyChanged),
      vault: LabProfile.active ? LabModelVault() : core.credentialVault,
      meshRuntime: core.mesh, programs: core.programs, history: core.changeHistory,
      chat: () => chat, chatProblem: () => chatError,
      repository: () => repositoryPath,
      codexHome: Directory(LabProfile.active ? '${LabProfile.root}/codex-home'
        : '${Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']}/.codex'),
      checkCodex: _checkCodexModel, modelSaved: () async {
        if (chat != null || _disposed || !_open) return;
        _operations = _operations.then((_) async {
          if (_endpointStatus case AgentEndpointRunning(:final repository)) {
            await _startChat(repository);
            notifyListeners();
          }
        });
        await _operations;
      });
    _hostReady.complete(_hostSettings);
    if (_disposed) return;
    if (kDebugMode && LabProfile.active) installDebugChat(() => chat);
    if (kDebugMode && LabProfile.active) installDebugHostSettings(hostSettings);
    if (kDebugMode && LabProfile.active) installDebugUiData(ServiceProvider.nextCore);
    if (kDebugMode && LabProfile.active) playback.installDebug();
    _labs.addListener(_queueEndpointUpdate);
    _preference.addListener(_queueEndpointUpdate);
    _location!.addListener(_queueEndpointUpdate);
    _open = _nextOpen;
    notifyListeners();
    await _updateEndpoint(_open);
  }

  /// Next's interface is what shows. Nipa, her endpoint and every
  /// capability run only then; in Classic none of them do (D1).
  bool get _nextOpen => NextUiPreference.interfaceOpen(
      nextEnabled: _labs.enableAgentEndpoint, preference: _preference.enabled);
  bool _open = false;

  void _queueEndpointUpdate() {
    notifyListeners();
    final enabled = _nextOpen;
    if (enabled != _open) {
      _open = enabled;
      // Between Next and Classic what plays closes, its progress saved; the
      // other side does not take it over (D2). At once, not behind work
      // still queued.
      final closing = playback
          .close(reason: enabled ? 'next_interface_opened' : 'next_interface_closed')
          .catchError((Object error, StackTrace stack) =>
              Zone.current.handleUncaughtError(error, stack));
      _operations = _operations.then((_) => closing);
    }
    if (!enabled) {
      unawaited(_hostSettings?.codex?.cancel());
    }
    _operations = _operations.then((_) => _updateEndpoint(enabled));
  }

  /// Nipa's services and what Next hooks into the playback, only while
  /// Next's interface is open.
  bool _nipa = false;
  Future<void> _setNipa(bool on) async {
    if (on == _nipa) return;
    _nipa = on;
    final core = ServiceProvider.nextCore;
    if (on) {
      await core.startNipa();
      core.danmaku.startRestoring(_harness, playback);
      _meshPlayback = MeshPlayback(core, playback)..attach();
      core.media.service.currentPath = () => playback.path;
      return;
    }
    await _meshPlayback?.close();
    _meshPlayback = null;
    await core.danmaku.stopRestoring();
    core.media.service.currentPath = null;
    await _hostEvents?.cancel();
    await _activityEvents?.cancel();
    _hostEvents = null;
    _activityEvents = null;
    // Nothing keeps the closed conversation's host.
    core.jobOrigins.threadFor = null;
    core.memory.recent = null;
    await core.stopNipa();
  }

  Future<void> _updateEndpoint(bool enabled) async {
    if (_disposed) return;
    if (_endpointStatus case AgentEndpointRunning(:final repository)) {
      if (enabled && repository.path == repositoryPath) return;
    }
    await _detachHooks();
    await ServiceProvider.nextCore.followups.attach(null,
        reason: enabled ? 'Chat host is restarting for the active harness.' : 'Next chat host is disabled.');
    await chat?.close();
    chat = null;
    chatError = null;
    final AgentEndpointStatus status;
    if (enabled) {
      await _setNipa(true);
      // Only for Next: Classic keeps its handlers and kernel logs as they are.
      await _uncaught?.attach();
      PlayerNativeLog.instance.attach();
      ServiceProvider.nextCore.subtitles.attachPlayer(playback.subtitleTarget);
      await _localLibrary.attachClassicHistory();
      status = await _endpoint.start(Directory(repositoryPath));
      if (status case AgentEndpointRunning(:final repository)) {
        await _attachHooks(repository);
        await _startChat(repository);
      }
    } else {
      // What Next changed in the kernel for this playback goes back first.
      await _kernel?.release();
      await _uncaught?.detach();
      await PlayerNativeLog.instance.detach();
      ServiceProvider.nextCore.subtitles.detachPlayer();
      await _endpoint.stop();
      await _setNipa(false);
      status = const AgentEndpointStopped();
    }
    if (_disposed || _endpointStatus == status) return;
    _endpointStatus = status;
    unawaited(BackgroundActivity.set(status is AgentEndpointRunning));
    status is AgentEndpointRunning ? _loopLag.start() : _loopLag.stop();
    _hostSettings?.notify();
    notifyListeners();
  }

  Future<void> _startChat(Directory repository) async {
    chatError = null;
    await _hostEvents?.cancel();
    await _activityEvents?.cancel();
    final labRoot = LabProfile.active ? Directory(LabProfile.root) : null;
    final DshRuntime? dsh;
    try {
      dsh = DshRuntime.select(Platform.environment, labRoot: labRoot);
    } on StateError catch (error) {
      chatError = redactHarnessText(error.message);
      await ServiceProvider.nextCore.followups.attach(null, reason: chatError);
      _hostSettings!.notify();
      return;
    }
    // NipaPlay's, not the harness's: written from the build on every start.
    final agent = '${ServiceProvider.nextCore.root.path}/agent';
    Future<File> install(String asset, String path) async {
      final file = File('$agent/$path');
      await file.parent.create(recursive: true);
      await file.writeAsString(await rootBundle.loadString(asset), flush: true);
      return file;
    }
    // DSH keeps its own system prompt; Nipa is its persona (dsh/persona-*.md).
    final base = dsh == null
        ? await install('assets/next/agent/nipa-base.md', 'nipa-base.md')
        : null;
    if (dsh != null) {
      for (final name in const [
        'nipa-app-server.mjs',
        'nipa-memory.mjs',
        'persona-prefix.md',
        'persona-suffix.md'
      ]) {
        await install('assets/next/agent/dsh/$name', 'dsh/$name');
      }
    }
    final host = chat = ChatHost(endpoint: _endpoint, repository: repository,
      memory: ServiceProvider.nextCore.memory,
      sessions: ServiceProvider.nextCore.sessions,
      modelLaunch: _hostSettings!.launch,
      labRoot: labRoot,
      baseInstructions: base,
      dsh: dsh,
      dshPlugins: dsh == null ? null : Directory('$agent/dsh'));
    final core = ServiceProvider.nextCore;
    core.jobOrigins.threadFor = host.threadForOrigin;
    core.memory.recent = (current) async => recentMemoryFacts(host,
      [for (final job in await core.engine.list())
        if (!job.state.isTerminal) job.toJson()],
      (await core.followups.list()).where((r) =>
        !const {'completed', 'cancelled'}.contains(r['state'])).toList(),
      (await core.state.views['activity']!.readAll!()).rows, current,
      capabilityChanges: await core.catalogChanges.recent(),
      finishedHelpers: [
        for (final job in ((await core.engine.list(type: 'agent.helper'))
                .where((job) => job.state.isTerminal)
                .toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
            .take(3))
          job.toJson()
      ]);
    // DSH's memory block carries the latest 动态; tell it when that grows.
    _activityEvents = core.activityChanges.stream.listen((_) => host.memoryChanged());
    _hostEvents = host.events.listen((event) {
      if (const {'host/modelChanged', 'host/error', 'turn/completed', 'error'}
          .contains(event['method'])) {
        _hostSettings!.notify();
      }
    });
    if (kDebugMode && LabProfile.active) recordDebugChat(host);
    try {
      await host.start();
      await host.getMainSession();
      await ServiceProvider.nextCore.followups.attach(host);
    } catch (error) {
      chatError = redactHarnessText(error.toString());
      await host.close();
      chat = null;
      await ServiceProvider.nextCore.followups.attach(null, reason: chatError);
    }
    _hostSettings!.notify();
  }

  Future<UiModelCheck> _checkCodexModel() async {
    final host = ChatHost(endpoint: _endpoint, repository: Directory(repositoryPath),
      codexExecutable: await _hostSettings!.codex?.executable(),
      probe: true, labRoot: LabProfile.active ? Directory(LabProfile.root) : null);
    final watch = Stopwatch()..start();
    try {
      await host.start().timeout(const Duration(seconds: 15));
      final ok = await host.checkSavedModel().timeout(const Duration(seconds: 30));
      return UiModelCheck(ok: ok, message: ok ? '可以使用' :
        modelFailureMessage(host.threadLiveness.values.firstOrNull?.latestError ?? ''),
        latency: watch.elapsed);
    } on TimeoutException {
      return UiModelCheck(ok: false, message: '服务器响应超时', latency: watch.elapsed);
    } catch (error) {
      return UiModelCheck(ok: false, message: modelFailureMessage('$error'), latency: watch.elapsed);
    } finally { await host.close(); }
  }

  void _queueHook(Future<void> Function() event) {
    _hookEvents = _hookEvents.then((_) => event());
  }

  Future<void> _attachHooks(Directory repository) async {
    final store = ServiceProvider.nextCore.media.service.store;
    _libraryPaths = {
      for (final row in await store.database.query('media_locations'))
        row['locator'] as String,
      for (final item in ServiceProvider.watchHistoryProvider.history)
        item.filePath,
    };
    final transport = playback.transport.value;
    _startedPath = {PlaybackPhase.playing, PlaybackPhase.paused}
            .contains(transport.phase)
        ? playback.media.value.path
        : null;
    _hooks.enable(repository, _endpoint.credentialFile);
    ServiceProvider.nextCore.desktopSystem.attach();
    _jobEvents = _taskEngine.changes.listen((job) {
      _queueHook(() => _hooks.taskChanged(job));
      // A scan ending delivers the files it brought without waiting out the
      // quiet window, once no other scan is still running: scans started
      // together (a folder each) arrive as one batch.
      if (const {'media.scan', 'media.scan_classic'}.contains(job.type) &&
          job.state.isTerminal) {
        _queueHook(() async {
          for (final type in const ['media.scan', 'media.scan_classic']) {
            if ((await _taskEngine.list(type: type))
                .any((other) => !other.state.isTerminal)) {
              return;
            }
          }
          await _reportLibrary(
              ServiceProvider.nextCore.followups.libraryBatchEnded);
        });
      }
    });
    _queueHook(() async {
      for (final job in await _taskEngine.list(type: 'download')) {
        await _hooks.fileCompletions(job);
      }
    });
    _fileEvents = store.fileChanges.listen((file) => _queueHook(() async {
          final path = file['path'] as String;
          if (_libraryPaths.add(path)) {
            await _hooks.emit('library.file_added', path, file);
            await _reportLibrary(
                () => ServiceProvider.nextCore.followups.libraryFileAdded(file));
          }
        }));
    ServiceProvider.watchHistoryProvider.addListener(_libraryChanged);
    playback.media.addListener(_playbackChanged);
    playback.transport.addListener(_playbackChanged);
  }

  void _libraryChanged() => _queueHook(_observeLibrary);
  Future<void> _observeLibrary() async {
    final files = {
      for (final item in ServiceProvider.watchHistoryProvider.history)
        if (!_libraryPaths.contains(item.filePath))
          item.filePath: {'path': item.filePath, 'via': 'classic_history'},
    };
    for (final entry in files.entries) {
      if (_libraryPaths.add(entry.key)) {
        await _hooks.emit('library.file_added', entry.key, entry.value);
        await _reportLibrary(
            () => ServiceProvider.nextCore.followups.libraryFileAdded(entry.value));
      }
    }
  }

  /// Telling Nipa never stops the hook chain that follows it.
  Future<void> _reportLibrary(Future<void> Function() report) async {
    try {
      await report();
    } catch (error, stack) {
      Zone.current.handleUncaughtError(error, stack);
    }
  }

  void _playbackChanged() =>
      PlayerPerf.span('runtime.playbackChanged', _playbackChange);
  void _playbackChange() {
    final path = playback.media.value.path;
    final transport = playback.transport.value;
    final status = transport.status;
    if (status != _lastPlaybackStatus || path != _lastPlaybackPath) {
      final previous = _lastPlaybackStatus;
      final pathChanged = path != _lastPlaybackPath;
      _lastPlaybackStatus = status;
      _lastPlaybackPath = path;
      _queueHook(() => _hooks.emit('playback.state_changed', path ?? 'player', {
        'status': status, 'previousStatus': previous, 'path': path,
        'changedFields': ['status'],
      }));
      // Classic sets its error text right after the status; read both once
      // the code that failed has returned.
      if (status == 'error') scheduleMicrotask(_recordFailure);
      if (pathChanged || status == 'error') {
        _uncaught?.notePlayback(playback.errorContext());
      }
    }
    if (!transport.hasVideo) {
      _startedPath = null;
      return;
    }
    if (!transport.playing ||
        path == null ||
        path == _startedPath) {
      return;
    }
    _startedPath = path;
    _queueHook(() async {
      await _hooks.emit('playback.started', path, {'path': path});
    });
  }

  void _recordFailure() {
    final captured = playback.captureFailure();
    _queueHook(() async {
      try {
        final failure = await PlaybackFailures.instance.record(captured);
        await _hooks.emit('playback.failed',
            failure['path'] as String? ?? 'player', {...failure, 'status': 'error'});
      } catch (error, stack) {
        Zone.current.handleUncaughtError(error, stack);
      }
    });
  }

  /// The app is leaving through its exit path; the next start does not
  /// report this run as ended abruptly.
  Future<void> exiting() async => _uncaught?.exiting();

  Future<void> _detachHooks() async {
    ServiceProvider.nextCore.desktopSystem.detach();
    playback.media.removeListener(_playbackChanged);
    playback.transport.removeListener(_playbackChanged);
    ServiceProvider.watchHistoryProvider.removeListener(_libraryChanged);
    await _jobEvents?.cancel();
    await _fileEvents?.cancel();
    _jobEvents = null;
    _fileEvents = null;
    await _hookEvents;
    await _hooks.disable();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(BackgroundActivity.set(false));
    _loopLag.stop();
    unawaited(_hostSettings?.codex?.cancel());
    ServiceProvider.nextCore.subtitles.detachPlayer();
    _classicSettings?.plugins.removeListener(_syncPluginSettings);
    ServiceProvider.watchHistoryProvider
        .removeListener(ServiceProvider.nextCore.stateSources.changed);
    unawaited(_calendarChanges?.cancel());
    if (identical(ClassicSettings.attached, _classicSettings)) ClassicSettings.attached = null;
    _labs.removeListener(_queueEndpointUpdate);
    _preference.removeListener(_queueEndpointUpdate);
    _location?.removeListener(_queueEndpointUpdate);
    _operations = _operations.then((_) async {
      await _kernel?.release(reopen: false);
      await _uncaught?.detach();
      await PlayerNativeLog.instance.detach();
      await _meshPlayback?.close();
      await _detachHooks();
      await ServiceProvider.nextCore.followups.attach(null, reason: 'NipaPlay is shutting down.');
      await chat?.close();
      await _hostEvents?.cancel();
      await _activityEvents?.cancel();
      await _hostSettings?.close();
      await hostSettings.close();
      await _endpoint.stop();
    });
    super.dispose();
  }
}
