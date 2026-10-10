import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/episode_file_selection_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'agent_endpoint.dart';
import 'capabilities/history_capability.dart';
import 'capabilities/library_capability.dart';
import 'capabilities/navigation_capability.dart';
import 'capabilities/playback_capability.dart';
import 'capabilities/video_player_state_port.dart';
import 'media/file_indexing.dart';
import 'settings/application_settings.dart';

final class NextRuntime extends ChangeNotifier {
  NextRuntime._(this._labs, this._player, List<Capability> capabilities) {
    _operations = _initialize(capabilities);
  }

  factory NextRuntime.fromContext(BuildContext context) {
    final labs = context.read<LabsSettingsProvider>();
    ApplicationSettings.erikaVisible = () =>
        PlayerFactory.isErikaKernelSupported &&
        (globals.isTelevision ||
            PlayerFactory.isHarmonyOS ||
            labs.enableErikaPlayerKernel);
    final settings = context.read<SettingsProvider>();
    final player = context.read<VideoPlayerState>();
    final navigation = context.read<TabChangeNotifier>();
    final history = ServiceProvider.watchHistoryProvider;
    final seriesDetail = BangumiService.instance.getAnimeDetailsFromMemory;
    return NextRuntime._(labs, player, [
      LibraryCapability(
        history: () => history.history,
        seriesDetail: seriesDetail,
      ),
      HistoryCapability(
        continueWatching: () => history.continueWatchingItems,
        seriesDetail: seriesDetail,
      ),
      PlaybackCapability(
        player: VideoPlayerStatePort(player),
        start: (item) =>
            PlaybackService().play(item, episodeFileSelectionHandled: true),
        usesExternalPlayer: () => settings.useExternalPlayer,
        historyItem: WatchHistoryManager.getHistoryItem,
        episodeItem: WatchHistoryManager.getHistoryItemByEpisode,
        fileSelection: EpisodeFileSelectionService(),
      ),
      NavigationCapability(changePage: navigation.changePage),
    ]);
  }

  final LabsSettingsProvider _labs;
  final VideoPlayerState _player;
  late final Harness _harness;
  late final AgentEndpoint _endpoint;
  late final TaskEngine _taskEngine;
  late Future<void> _operations;
  AgentEndpointStatus _endpointStatus = const AgentEndpointStopped();
  bool _disposed = false;

  Harness get harness => _harness;
  TaskEngine get taskEngine => _taskEngine;
  AgentEndpointStatus get endpointStatus => _endpointStatus;

  Future<void> _initialize(List<Capability> capabilities) async {
    final core = ServiceProvider.nextCore;
    await core.ready;
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
    await _labs.ready;
    final root = core.root;
    final agentsMd = await rootBundle.loadString('assets/next/AGENTS.md');
    final packageInfo = await PackageInfo.fromPlatform();
    _harness = Harness(
      [
        for (final capability in capabilities)
          FileIndexingCapability(capability, core.media.service.store),
        ...core.capabilities
      ],
      observers: [JsonlJournal(File('${root.path}/journal.jsonl'))],
    );
    core.attachHarness(_harness);
    core.danmaku.startRestoring(_harness, _player);
    core.media.service.currentPath = () => _player.currentVideoPath;
    _endpoint = AgentEndpoint(
      harness: _harness,
      root: root,
      appVersion: packageInfo.version,
      agentsMd: agentsMd,
      port: kDebugMode && Platform.environment['NIPAPLAY_AGENT_PORT'] != null
          ? int.parse(Platform.environment['NIPAPLAY_AGENT_PORT']!)
          : 47811,
    );
    if (_disposed) return;
    _labs.addListener(_queueEndpointUpdate);
    await _updateEndpoint(_labs.enableAgentEndpoint);
  }

  void _queueEndpointUpdate() {
    final enabled = _labs.enableAgentEndpoint;
    _operations = _operations.then((_) => _updateEndpoint(enabled));
  }

  Future<void> _updateEndpoint(bool enabled) async {
    if (_disposed) return;
    final AgentEndpointStatus status;
    if (enabled) {
      status = await _endpoint.start();
    } else {
      await _endpoint.stop();
      status = const AgentEndpointStopped();
    }
    if (_disposed || _endpointStatus == status) return;
    _endpointStatus = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _labs.removeListener(_queueEndpointUpdate);
    _operations = _operations.then((_) async {
      await _endpoint.stop();
    });
    super.dispose();
  }
}
