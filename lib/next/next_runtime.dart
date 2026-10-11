import 'dart:async';
import 'dart:io';
import 'package:nipaplay/utils/lab_profile.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/episode_file_selection_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'agent_endpoint.dart';
import 'capabilities/history_capability.dart';
import 'capabilities/library_capability.dart';
import 'capabilities/ui_capability.dart';
import 'capabilities/ui_capture.dart';
import 'instance_facts.dart';
import 'capabilities/classic_ui_open.dart';
import 'capabilities/discover_capability.dart';
import 'capabilities/playback_capability.dart';
import 'capabilities/download_playback_capability.dart';
import 'settings/download_settings.dart';
import 'capabilities/playback_controls_capability.dart';
import 'capabilities/classic_playback_controls.dart';
import 'capabilities/video_player_state_port.dart';
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
import 'chat/debug_chat.dart';
import 'ui_data/debug_ui_data.dart';
import 'harness_redaction.dart';
import 'state/change_history.dart';

final class NextRuntime extends ChangeNotifier {
  NextRuntime._(this._labs, this._player, List<Capability> capabilities) {
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
      core.mediaSources.shared!.observeChanges();
      core.mediaSources.updateGuiSelection = (type, ids) => type == 'jellyfin'
          ? context.read<JellyfinProvider>().updateSelectedLibraries(ids)
          : context.read<EmbyProvider>().updateSelectedLibraries(ids);
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
    final player = context.read<VideoPlayerState>();
    final history = ServiceProvider.watchHistoryProvider;
    final seriesDetail = BangumiService.instance.getAnimeDetailsFromMemory;
    final playback = PlaybackCapability(
      player: VideoPlayerStatePort(player),
      start: (item) => PlaybackService().play(item, episodeFileSelectionHandled: true),
      usesExternalPlayer: () => settings.useExternalPlayer,
      historyItem: WatchHistoryManager.getHistoryItem,
      episodeItem: WatchHistoryManager.getHistoryItemByEpisode,
      fileSelection: EpisodeFileSelectionService(),
    );
    final playbackApi = Harness([playback]);
    return NextRuntime._(labs, player, [
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
        openPage: ClassicUiOpen().page,
        openDetail: ClassicUiOpen().detail,
        openTarget: ClassicUiOpen(harnessPath: () async {
          await core.harnessLocation.ready;
          return core.harnessLocation.path;
        }).target,
        close: ClassicUiOpen().close,
        play: (input, invocation) => playbackApi.invokeJson('playback.open', input, invocation)),
    ]);
  }

  final LabsSettingsProvider _labs;
  final VideoPlayerState _player;
  late final Harness _harness;
  late final AgentEndpoint _endpoint;
  late final TaskEngine _taskEngine;
  HarnessLocation? _location;
  late final HarnessHooks _hooks;
  StreamSubscription<Job>? _jobEvents;
  StreamSubscription<JsonMap>? _fileEvents;
  Future<void> _hookEvents = Future.value();
  Set<String> _libraryPaths = {};
  String? _startedPath;
  late Future<void> _operations;
  AgentEndpointStatus _endpointStatus = const AgentEndpointStopped();
  bool _disposed = false;
  ClassicSettings? _classicSettings;
  ChatHost? chat;
  String? chatError;
  Future<void> closeChat() async {
    await _operations;
    await ServiceProvider.nextCore.followups.attach(null, reason: 'Chat host was closed.');
    await chat?.close();
    chat = null;
  }

  void _syncPluginSettings() {
    final classic = _classicSettings!;
    ServiceProvider.nextCore.settings.replaceGroup('plugins.enabled.', []);
    ServiceProvider.nextCore.settings.replaceGroup('plugins.settings.', classic.pluginEntries());
  }

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
    core.stateSources.classicLibrary = classicLibraryStateViews(
      history: () => ServiceProvider.watchHistoryProvider.history,
      seriesDetail: BangumiService.instance.getAnimeDetailsFromMemory,
    );
    _taskEngine = core.engine;
    _hooks = core.hooks;
    _location = core.harnessLocation;
    await _location!.ready;
    await _labs.ready;
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
    _harness = Harness(
      [
        InstanceCapability(instanceFacts),
        UiCaptureCapability(ClassicUiCapture(instanceFacts).capture),
        for (final capability in capabilities)
          InvocationScopeCapability(FileIndexingCapability(capability, core.media.service.store)),
        PlaybackControlsCapability(ClassicPlaybackControls(_player)),
        FileIndexingCapability(
            DownloadPlaybackCapability(
                core.downloads, (item) => PlaybackService().play(item)),
            core.media.service.store),
        ...core.capabilities
      ],
      observers: [JsonlJournal(File('${root.path}/journal.jsonl'),
        effects: Effect.values.toSet())],
    );
    core.attachHarness(_harness);
    core.danmaku.startRestoring(_harness, _player);
    core.media.service.currentPath = () => _player.currentVideoPath;
    _endpoint = AgentEndpoint(
      harness: _harness,
      appVersion: packageInfo.version,
      instanceFacts: instanceFacts.read,
      seed: seed,
      seedRepository: Directory('${root.path}/harness-seed'),
      port: LabProfile.active ? 0 : kDebugMode && Platform.environment['NIPAPLAY_AGENT_PORT'] != null
          ? int.parse(Platform.environment['NIPAPLAY_AGENT_PORT']!)
          : 47811,
    );
    if (_disposed) return;
    if (kDebugMode && LabProfile.active) installDebugChat(() => chat);
    if (kDebugMode && LabProfile.active) installDebugUiData(ServiceProvider.nextCore);
    _labs.addListener(_queueEndpointUpdate);
    _location!.addListener(_queueEndpointUpdate);
    notifyListeners();
    await _updateEndpoint(_labs.enableAgentEndpoint);
  }

  void _queueEndpointUpdate() {
    notifyListeners();
    final enabled = _labs.enableAgentEndpoint;
    _operations = _operations.then((_) => _updateEndpoint(enabled));
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
      status = await _endpoint.start(Directory(repositoryPath));
      if (status case AgentEndpointRunning(:final repository)) {
        await _attachHooks(repository);
        final host = chat = ChatHost(endpoint: _endpoint, repository: repository,
          labRoot: LabProfile.active ? Directory(LabProfile.root) : null);
        if (kDebugMode && LabProfile.active) recordDebugChat(host);
        try {
          await host.start();
          await ServiceProvider.nextCore.followups.attach(host);
        } catch (error) {
          chatError = redactHarnessText(error.toString());
          await host.close();
          chat = null;
          await ServiceProvider.nextCore.followups.attach(null, reason: chatError);
        }
      }
    } else {
      await _endpoint.stop();
      status = const AgentEndpointStopped();
    }
    if (_disposed || _endpointStatus == status) return;
    _endpointStatus = status;
    notifyListeners();
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
    _startedPath =
        {PlayerStatus.playing, PlayerStatus.paused}.contains(_player.status)
            ? _player.currentVideoPath
            : null;
    _hooks.enable(repository, _endpoint.credentialFile);
    _jobEvents = _taskEngine.changes.listen((job) {
      _queueHook(() => _hooks.taskChanged(job));
    });
    _fileEvents = store.fileChanges.listen((file) => _queueHook(() async {
          final path = file['path'] as String;
          if (_libraryPaths.add(path)) {
            await _hooks.emit('library.file_added', path, file);
          }
        }));
    ServiceProvider.watchHistoryProvider.addListener(_libraryChanged);
    _player.addListener(_playbackChanged);
  }

  void _libraryChanged() => _queueHook(_observeLibrary);
  Future<void> _observeLibrary() async {
    final files = {
      for (final item in ServiceProvider.watchHistoryProvider.history)
        if (!_libraryPaths.contains(item.filePath))
          item.filePath: {'path': item.filePath},
    };
    for (final entry in files.entries) {
      if (_libraryPaths.add(entry.key)) {
        await _hooks.emit('library.file_added', entry.key, entry.value);
      }
    }
  }

  void _playbackChanged() {
    final path = _player.currentVideoPath;
    if (!_player.hasVideo) {
      _startedPath = null;
      return;
    }
    if (_player.status != PlayerStatus.playing ||
        path == null ||
        path == _startedPath) {
      return;
    }
    _startedPath = path;
    _queueHook(() async {
      await _hooks.emit('playback.started', path, {'path': path});
    });
  }

  Future<void> _detachHooks() async {
    _player.removeListener(_playbackChanged);
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
    _classicSettings?.plugins.removeListener(_syncPluginSettings);
    if (identical(ClassicSettings.attached, _classicSettings)) ClassicSettings.attached = null;
    _labs.removeListener(_queueEndpointUpdate);
    _location?.removeListener(_queueEndpointUpdate);
    _operations = _operations.then((_) async {
      await _detachHooks();
      await ServiceProvider.nextCore.followups.attach(null, reason: 'NipaPlay is shutting down.');
      await chat?.close();
      await _endpoint.stop();
    });
    super.dispose();
  }
}
