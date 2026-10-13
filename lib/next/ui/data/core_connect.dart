import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';

import '../../next_core.dart';
import '../../next_runtime.dart';
import '../../ui_data/library.dart';
import '../../ui_data/library_service.dart';
import '../../ui_data/ui_data.dart';
import 'login_requests.dart';
import 'ui_actions.dart';

/// The one place the shell takes its real data from: `NextCore.uiData`,
/// usable once the core is ready (the shell may appear before that).
NextUiData coreUiData(NextCore core) => _WhenReady(core);

/// The 片库 page's sources, arrangements and actions from the core
/// (`NextCore.libraryData`), once it is ready.
final class CoreLibrary implements NextLibraryData, NextLibraryActions {
  CoreLibrary(this.core);
  final NextCore core;

  Future<LibraryDataService> get _library async {
    await core.ready;
    return core.libraryData;
  }

  @override
  Future<List<UiLibrarySource>> sources() async => (await _library).sources();

  @override
  Future<UiLibraryPage> page(String sourceId) async =>
      (await _library).page(sourceId);

  @override
  Future<UiSlice> items(String categoryId,
          {int offset = 0, int limit = 60, String? sort}) async =>
      (await _library)
          .items(categoryId, offset: offset, limit: limit, sort: sort);

  @override
  Stream<void> get changes =>
      Stream.fromFuture(_library).asyncExpand((library) => library.changes);

  @override
  Future<void> setForm(String sourceId, UiLibraryForm form) async =>
      (await _library).setForm(sourceId, form);

  @override
  Future<void> useOriginal(String sourceId, bool original) async =>
      (await _library).useOriginal(sourceId, original);

  @override
  Future<void> moveCategory(String categoryId, int index) async =>
      (await _library).moveCategory(categoryId, index);

  @override
  Future<void> removeCategory(String categoryId) async =>
      (await _library).removeCategory(categoryId);

  @override
  Future<void> restoreCategory(String categoryId) async =>
      (await _library).restoreCategory(categoryId);
}

/// Real actions: task controls on the core's engine, playback through the
/// same `ui.open` Action the agent uses.
NextUiActions coreUiActions(NextCore core, NextRuntime runtime) =>
    CoreUiActions(core, runtime);

/// Routes the core's login windows (accounts and media sources started by
/// the agent without a secret) through [requests] while the shell lives.
/// Returns the detach, which puts the original windows back.
VoidCallback attachCoreLogins(NextCore core, LoginRequests requests) {
  var attached = true;
  Future<JsonMap?> Function(JsonMap, Future<void>)? account;
  Future<String?> Function(JsonMap, Future<void>)? source;
  Future<JsonMap?> accountCard(JsonMap input, Future<void> stopped) =>
      requests.request<JsonMap>(
          switch (input['provider']) {
            'dandanplay' => '弹弹play',
            'bangumi' => 'Bangumi',
            final other => '$other',
          },
          () => account!(input, stopped),
          stopped);
  Future<String?> sourceCard(JsonMap row, Future<void> stopped) =>
      requests.request<String>('${row['name'] ?? row['type']}',
          () => source!(row, stopped), stopped);
  // NextRuntime attaches the windows when the core is ready; wrap after it.
  core.ready.then((_) => Future<void>.delayed(Duration.zero)).then((_) {
    if (!attached) return;
    account = core.accounts.requestLogin;
    source = core.mediaSources.requestPassword;
    if (account != null) core.accounts.requestLogin = accountCard;
    if (source != null) core.mediaSources.requestPassword = sourceCard;
  });
  return () {
    attached = false;
    if (identical(core.accounts.requestLogin, accountCard)) {
      core.accounts.requestLogin = account;
    }
    if (identical(core.mediaSources.requestPassword, sourceCard)) {
      core.mediaSources.requestPassword = source;
    }
  };
}

final class _WhenReady implements NextUiData {
  _WhenReady(this.core);
  final NextCore core;

  Future<NextUiData> get _data async {
    await core.ready;
    return core.uiData;
  }

  @override
  Future<UiHome> home() async => (await _data).home();

  @override
  Future<UiWork?> work(String workId) async => (await _data).work(workId);

  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async =>
      (await _data).episodes(workId, season: season);

  @override
  Future<List<UiWork>> library() async => (await _data).library();

  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      (await _data).cards(threadId: threadId, turnId: turnId);

  @override
  Stream<List<UiTask>> tasks() async* {
    yield* (await _data).tasks();
  }

  @override
  Stream<void> get changes =>
      Stream.fromFuture(_data).asyncExpand((data) => data.changes);
}

final class CoreUiActions implements NextUiActions {
  CoreUiActions(this.core, this.runtime);
  final NextCore core;
  final NextRuntime runtime;

  // [UiTask.taskId] is the TaskEngine job ID (lib/next/ui_data/README.md).
  @override
  Future<void> pauseTask(String taskId) => core.engine.pause(taskId);

  @override
  Future<void> resumeTask(String taskId) => core.engine.resume(taskId);

  @override
  Future<void> cancelTask(String taskId) => core.engine.cancel(taskId);

  @override
  Future<bool> markWatched(List<UiEpisode> episodes,
      {required bool watched}) async {
    final outcome = await runtime.harness.invokeJson(
        'history.mark_watched_batch',
        {
          'entries': [
            for (final e in episodes)
              {'episodeId': e.episodeId, 'watched': watched}
          ]
        },
        Invocation(origin: 'gui'));
    if (outcome case Failed(:final failure)) {
      debugPrint('[NextUi] mark watched failed: ${failure.message}');
      return false;
    }
    return true;
  }

  @override
  Future<void> login(String provider) async {
    final outcome = await runtime.harness.invokeJson(
        'accounts.login', {'provider': provider}, Invocation(origin: 'gui'));
    if (outcome case Failed(:final failure)) {
      debugPrint('[NextUi] login failed: ${failure.message}');
    }
  }

  /// Plays in Classic's player, which the shell reveals while a video is
  /// open. Several recorded locations: the first one.
  @override
  Future<void> play(UiWork work, {UiEpisode? episode}) async {
    final target = episode ?? work.next;
    if (target == null) return;
    final invocation = Invocation(origin: 'gui');
    var outcome = await runtime.harness
        .invokeJson('ui.open', {'entityId': target.episodeId}, invocation);
    if (outcome case NeedsDecision(:final decision)
        when decision.options.isNotEmpty) {
      final call = decision.options.first.call;
      outcome = await runtime.harness
          .invokeJson(call.actionId, call.input, Invocation(origin: 'gui'));
    }
    if (outcome case Failed(:final failure)) {
      debugPrint('[NextUi] play failed: ${failure.message}');
    }
  }
}
