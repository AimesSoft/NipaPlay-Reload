import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/episode_file_selection_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'agent_endpoint.dart';
import 'capabilities/history_capability.dart';
import 'capabilities/library_capability.dart';
import 'capabilities/navigation_capability.dart';
import 'capabilities/playback_capability.dart';
import 'capabilities/video_player_state_port.dart';
import 'media/media_capability.dart';
import 'media/media_executors.dart';
import 'media/media_runtime.dart';
import 'tasks/device_identity.dart';
import 'tasks/sqlite_job_store.dart';

final class NextRuntime extends ChangeNotifier {
  NextRuntime._(this._labs, List<Capability> capabilities) {
    _operations = _initialize(capabilities);
  }

  factory NextRuntime.fromContext(BuildContext context) {
    final labs = context.read<LabsSettingsProvider>();
    final settings = context.read<SettingsProvider>();
    final player = context.read<VideoPlayerState>();
    final navigation = context.read<TabChangeNotifier>();
    final history = ServiceProvider.watchHistoryProvider;
    final seriesDetail = BangumiService.instance.getAnimeDetailsFromMemory;
    return NextRuntime._(labs, [
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
  late final Harness _harness;
  late final AgentEndpoint _endpoint;
  late final TaskEngine _taskEngine;
  late final MediaRuntime _media;
  late Future<void> _operations;
  AgentEndpointStatus _endpointStatus = const AgentEndpointStopped();
  bool _disposed = false;

  Harness get harness => _harness;
  TaskEngine get taskEngine => _taskEngine;
  AgentEndpointStatus get endpointStatus => _endpointStatus;

  Future<void> _initialize(List<Capability> capabilities) async {
    await _labs.ready;
    final storage = await StorageService.getAppStorageDirectory();
    final root = Directory('${storage.path}/next');
    final deviceId = await loadDeviceIdentity(root);
    final jobs = await SqliteJobStore.open(root);
    _media = await MediaRuntime.create(root, jobs.database, deviceId);
    _taskEngine = TaskEngine(
        store: jobs,
        ownerDeviceId: deviceId,
        executors: mediaExecutors(_media.service));
    _media.service.engine = _taskEngine;
    await _taskEngine.start();
    await _media.service.recoverProjections();
    final agentsMd = await rootBundle.loadString('assets/next/AGENTS.md');
    final packageInfo = await PackageInfo.fromPlatform();
    _harness = Harness(
      [
        ...capabilities,
        TaskCapability(_taskEngine),
        MediaCapability(_media.service)
      ],
      observers: [JsonlJournal(File('${root.path}/journal.jsonl'))],
    );
    _endpoint = AgentEndpoint(
      harness: _harness,
      root: root,
      appVersion: packageInfo.version,
      agentsMd: agentsMd,
    );
    if (_disposed) return;
    _labs.addListener(_queueEndpointUpdate);
    await _updateEndpoint();
  }

  void _queueEndpointUpdate() {
    _operations = _operations.then((_) => _updateEndpoint());
  }

  Future<void> _updateEndpoint() async {
    if (_disposed) return;
    final AgentEndpointStatus status;
    if (_labs.enableAgentEndpoint) {
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
      await _taskEngine.close();
      _media.close();
    });
    super.dispose();
  }
}
