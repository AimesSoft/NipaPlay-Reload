import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../danmaku/service.dart';
import '../danmaku/sidecar_index.dart';
import '../danmaku/store.dart';
import '../followups/service.dart';
import '../headless/ports.dart';
import '../harness_redaction.dart';
import '../media/identity_store.dart';
import '../media/media_probe.dart';
import '../media/media_service.dart';
import '../media/metadata_provider.dart';
import '../media/provider_transport.dart';
import '../media/providers.dart';
import '../settings/registry.dart';
import '../state/activity.dart';
import '../state/calendar_material.dart';
import '../state/query.dart';
import '../state/views.dart';
import '../subtitles/episode_subtitles.dart';
import '../subtitles/facts.dart';
import '../subtitles/index_scan.dart';
import '../tasks/sqlite_job_store.dart';
import '../ui_data/library_service.dart';
import '../ui_data/no_airing.dart' if (dart.library.ui) '../ui_data/airing.dart'
    as airing;
import '../ui_data/service.dart';
import '../ui_data/ui_data.dart';
import 'library_codec.dart';
import 'library_projection.dart';

/// A request owns its reply port. Errors retain their typed Failure contract.
Future<Object?> _request(SendPort target, String method, Object? input,
    {Future<void>? exited}) async {
  final reply = RawReceivePort();
  final first = Completer<Object?>();
  reply.handler = (Object? response) {
    if (!first.isCompleted) first.complete(response);
  };
  try {
    target.send((method, input, reply.sendPort));
    final response = await Future.any([
      first.future,
      if (exited != null)
        // A worker that ends by Isolate.exit sends its reply first; the exit
        // notice may still be handled before that reply is. Give it a turn.
        exited.then<Object?>((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          throw StateError('Library worker exited');
        })
    ]);
    final (ok, value) = response as (bool, Object?);
    if (!ok) {
      if (value is Failure) throw value;
      throw StateError(value.toString());
    }
    return value;
  } finally {
    reply.close();
  }
}

Future<void> _answer(
    Object? message, Future<Object?> Function(String, Object?) dispatch) async {
  final (method, input, reply) = message as (String, Object?, SendPort);
  try {
    final value = await dispatch(method, input);
    if (value is _ExitWith) Isolate.exit(reply, (true, value.value));
    if (value is _DetachedReply) {
      // The relay exits with the value; the UI then takes ownership without
      // walking and copying this large object graph in its message callback.
      await Isolate.spawn(_detachedReply, (reply, value.value));
      return;
    }
    reply.send((true, value));
  } catch (error) {
    reply.send((false, error is Failure ? error : error.toString()));
  }
}

/// Ends this worker after sending its final value. Isolate.exit transfers the
/// value without the main isolate copying the complete library graph.
final class _ExitWith {
  const _ExitWith(this.value);
  final Object? value;
}

final class _DetachedReply {
  const _DetachedReply(this.value);
  final Object? value;
}

void _detachedReply((SendPort, Object?) args) {
  Isolate.exit(args.$1, (true, args.$2));
}

final class LibraryBuildResult {
  const LibraryBuildResult(this.stamp, this.builds);
  final String stamp;
  final int builds;
}

final class LibraryPrepareResult {
  const LibraryPrepareResult(
      this.snapshot, this.builtStamp, this.compositionStamp, this.builds,
      {this.composed = false});
  final LibrarySnapshot? snapshot;
  final String builtStamp;
  final String compositionStamp;
  final int builds;
  final bool composed;
}

PackedWorks _packedWorks(LibrarySnapshot snapshot) {
  final orderedIds = snapshot.orderedWorks.isEmpty
      ? snapshot.works.keys.toList(growable: false)
      : [for (final work in snapshot.orderedWorks) work.workId];
  return PackedWorks.pack(orderedIds,
      [for (final id in orderedIds) jsonEncode(workJson(snapshot.works[id]!))]);
}

/// One worker per catalogue lifetime. Only plugin/network primitives and live
/// host observations cross back to the UI isolate; SQL and projections do not.
final class LibraryWorker {
  LibraryWorker(
    this.ui, {
    Future<JsonMap> Function(String) subtitleProbe = probeMediaInfo,
  }) : _subtitleProbe = subtitleProbe {
    // Spawn during core construction, so the first memory turn does not pay
    // for starting an isolate inside its 4 ms main-thread budget. This worker
    // stays independent of the catalogue worker, which ends after compose.
    unawaited(_startRedactor().then<void>((_) {}, onError: (_, __) {}));
  }

  final UiDataService ui;
  final Future<JsonMap> Function(String) _subtitleProbe;
  Isolate? _isolate;
  ReceivePort? _host;
  ReceivePort? _exit;
  Completer<void> _exited = Completer<void>();
  Future<SendPort>? _starting;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  /// A mesh library may be closed before its owning UI service. Stamp polling
  /// then falls back to the UI connection instead of surfacing an async error.
  bool get isClosed => _closed;

  String? _runtimeBuiltStamp;
  String? _lastBuiltStamp;
  Map<String, JsonMap>? _lastPeers;
  Map<String, bool>? _lastOnline;
  String? _lastAccount;
  int? _lastPeerRevision;
  int? _lastOnlineRevision;
  bool _needsRestore = false;
  bool _restartScheduled = false;
  Isolate? _redactorIsolate;
  ReceivePort? _redactorExit;
  Completer<void> _redactorExited = Completer<void>();
  Future<SendPort>? _redactorStarting;

  Future<SendPort> _startRedactor() => _redactorStarting ??= (() async {
        _redactorExited = Completer<void>();
        final ready = ReceivePort();
        final exited = _redactorExit = ReceivePort();
        exited.listen((_) {
          if (!_redactorExited.isCompleted) _redactorExited.complete();
        });
        try {
          _redactorIsolate = await Isolate.spawn(
              _redactionEntry, ready.sendPort,
              onExit: exited.sendPort, debugName: 'next-redaction');
          final result = await Future.any([
            ready.first,
            _redactorExited.future.then<Object?>((_) =>
                throw StateError('Redaction worker exited during startup'))
          ]);
          return result as SendPort;
        } finally {
          ready.close();
        }
      })();

  /// Worker requests are serialized here because compose transfers its result
  /// by terminating the worker. A request queued behind that exit belongs to
  /// the next worker, after the projection has been restored.
  Future<T> _serial<T>(Future<T> Function() action) {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    return (() async {
      await previous;
      try {
        return await action();
      } finally {
        gate.complete();
      }
    })();
  }

  /// Ends the running worker the way a crash would, for tests of recovery.
  void killWorkerForTest() => _isolate?.kill(priority: Isolate.immediate);

  /// A request that fails, instead of waiting for ever, if the worker ends.
  Future<Object?> _ask(SendPort target, String method, Object? input) =>
      _request(target, method, input, exited: _exited.future);

  Future<SendPort> _start() => _starting ??= (() async {
        final done = _exited = Completer<void>();
        final ready = ReceivePort();
        final host = _host = ReceivePort();
        final exited = _exit = ReceivePort();
        exited.listen((_) {
          if (!done.isCompleted) done.complete();
          // Ending on its own (compose forgets its worker first, close sets
          // _closed first): the next request starts a new one and restores
          // the projection, rather than waiting on a worker that is gone.
          if (!_closed && identical(_exit, exited)) {
            _forgetWorker(restore: true);
          }
        });
        host.listen((message) => unawaited(_answer(message, _hostRequest)));
        try {
          _isolate = await Isolate.spawn(
              _entry,
              (
                ready.sendPort,
                host.sendPort,
                ui.db.path,
                ui.mediaRoot.path,
                ui.media.store.ownerDeviceId,
                _subtitleProbe
              ),
              onExit: exited.sendPort,
              debugName: 'next-library');
          final result = await Future.any([
            ready.first,
            done.future.then<Object?>(
                (_) => throw StateError('Library worker exited during startup'))
          ]);
          if (result is Failure) throw result;
          if (result is String) throw StateError(result);
          return result as SendPort;
        } catch (_) {
          // A start that failed must not stay as the answer to every later
          // request: the next one tries again.
          if (identical(_exit, exited)) {
            _isolate?.kill(priority: Isolate.immediate);
            _forgetWorker(restore: _needsRestore);
          }
          rethrow;
        } finally {
          ready.close();
        }
      })();

  /// Opens the catalogue isolate and hands it the current Classic sources
  /// while Nipa's services start. The first home therefore neither spawns a
  /// worker nor materialises the history snapshot on the UI isolate.
  Future<void> warm() => _serial(() async {
        if (_closed) return;
        final target = await _start();
        await _syncSources(target);
      });

  /// The first indexer pass is one worker request. Both directory walks, all
  /// candidate comparisons, media/sidecar parsing and the final database writes
  /// stay in the catalogue isolate; the UI receives only the two summaries.
  Future<JsonMap> reconcileIndexers({
    required bool danmaku,
    required bool subtitles,
    required JsonMap subtitlePreferences,
  }) =>
      _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return await _ask(target, 'indexers', (
          danmaku,
          subtitles,
          SubtitleIndexPreferences.fromJson(subtitlePreferences),
        )) as JsonMap;
      });

  Future<Object?> _hostRequest(String method, Object? input) async {
    switch (method) {
      case 'vault':
        return ui.artwork.vault.read(input as CredentialRef);
      case 'metadata':
        final (provider, path, query, body) =
            input as (String, String, Map<String, String>, JsonMap?);
        final delegate = ui.media.providers[provider];
        if (delegate is! TmdbMetadataProvider) {
          throw StateError('Missing artwork metadata transport: $provider');
        }
        return delegate.transport.request(path, query: query, body: body);
      case 'activity':
        final prepare = ui.state.prepareActivity;
        return prepare == null ? null : await prepare();
      case 'read':
        final (name, offset, limit, all) = input as (String, int, int, bool);
        final view = ui.state.views[name]!;
        return all ? await view.readAll!() : await view.read(offset, limit);
      default:
        throw StateError('Unknown library host request: $method');
    }
  }

  /// Returns a live worker. After compose exits it rebuilds the database-backed
  /// projection and silently composes the last peer set before serving another
  /// request. [buildStamp] lets a caller restore directly to a new build rather
  /// than rebuilding the previous one and immediately replacing it.
  Future<SendPort> _worker({String? buildStamp}) async {
    final target = await _start();
    if (!_needsRestore) return target;

    await _syncSources(target);
    final stamp = buildStamp ?? _lastBuiltStamp;
    if (stamp != null) {
      await _ask(target, 'build', stamp);
      _runtimeBuiltStamp = stamp;
      _lastBuiltStamp = stamp;
    }
    final peers = _lastPeers;
    final online = _lastOnline;
    if (peers != null && online != null) {
      await _ask(target, 'restore', (peers, online, _lastAccount));
    }
    _syncedViews = null;
    _needsRestore = false;
    return target;
  }

  Future<void> _syncSources(SendPort target) async {
    if (_sourceRevision == ui.sources.revision) return;
    final revision = ui.sources.revision;
    await _ask(target, 'sources', (
      ui.sources.history?.call(),
      ui.sources.continueWatching?.call(),
      ui.media.authorizedRoots().toList(),
    ));
    _sourceRevision = revision;
  }

  int? _sourceRevision;
  int? _calendarRevision;
  bool _activityContextSent = false;
  ActivityHostContext? _activityContext;

  Future<Object?> call(String method, [Object? input]) => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return _ask(target, method, input);
      });

  /// Reads the catalogue epoch on the worker's own database connection. The
  /// UI isolate still combines it with the source revision it owns.
  Future<int> catalogueEpoch() async => await call('catalogueEpoch') as int;

  Future<void> build(String stamp) => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker(buildStamp: stamp);
        await _syncSources(target);
        if (_runtimeBuiltStamp != stamp) {
          await _ask(target, 'build', stamp);
          _runtimeBuiltStamp = stamp;
          _lastBuiltStamp = stamp;
        }
      });

  /// Reads the catalogue stamp in the worker, then builds until the stamp it
  /// built from is still current. The UI receives only the stamp and a count.
  Future<LibraryBuildResult> buildCurrent(String owner) => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        await _syncSources(target);
        final result =
            await _ask(target, 'buildCurrent', owner) as LibraryBuildResult;
        _runtimeBuiltStamp = result.stamp;
        _lastBuiltStamp = result.stamp;
        return result;
      });

  /// Prepares the complete index without reading SQL or encoding the catalogue
  /// stamp on the UI isolate. Startup returns only stamps; the live worker
  /// retains the projection and serves catalogue records on demand.
  Future<LibraryPrepareResult> prepare({
    required String owner,
    required Map<String, JsonMap> peers,
    required int peerRevision,
    required Map<String, bool> online,
    required int onlineRevision,
    required String? account,
    required String? composedStamp,
  }) =>
      _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        await _syncSources(target);
        final reply = await _ask(target, 'prepare', (
          owner,
          _lastPeerRevision == peerRevision ? null : peers,
          peerRevision,
          _lastOnlineRevision == onlineRevision ? null : online,
          onlineRevision,
          account,
          composedStamp
        ));
        final result = reply is LibrarySnapshot
            ? LibraryPrepareResult(
                reply, reply.builtStamp!, reply.compositionStamp!, reply.builds,
                composed: true)
            : reply as LibraryPrepareResult;
        _runtimeBuiltStamp = result.builtStamp;
        _lastBuiltStamp = result.builtStamp;
        _lastPeerRevision = peerRevision;
        _lastOnlineRevision = onlineRevision;
        _lastPeers = peers;
        _lastOnline = online;
        _lastAccount = account;
        return result;
      });

  Future<LibrarySnapshot> compose(Map<String, JsonMap> peers,
          Map<String, bool> online, String? account) =>
      _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        final result = await _ask(target, 'compose', (peers, online, account))
            as LibrarySnapshot;
        _lastPeers = Map.of(peers);
        _lastOnline = Map.of(online);
        _lastAccount = account;
        _forgetWorker(restore: true);
        // Recreate the long-lived query worker while the UI returns to normal
        // work. Views such as activity otherwise fall back to main-isolate SQL
        // after the transfer worker exits.
        _restartWorker();
        return result;
      });

  void _restartWorker() {
    if (_closed || _restartScheduled) return;
    _restartScheduled = true;
    // Isolate.spawn runs synchronously on the UI isolate. Queue it after the
    // caller has received and published its result, rather than extending the
    // prepare turn with worker startup.
    Timer.run(() {
      _restartScheduled = false;
      if (_closed) return;
      unawaited(_serial(() async {
        try {
          await _worker();
        } on Object {
          // The next request will retry and surface any persistent failure.
        }
      }));
    });
  }

  void _forgetWorker({required bool restore}) {
    _isolate = null;
    _starting = null;
    _sourceRevision = null;
    _calendarRevision = null;
    _activityContextSent = false;
    _activityContext = null;
    _syncedViews = null;
    _runtimeBuiltStamp = null;
    _needsRestore = restore;
    _host?.close();
    _host = null;
    _exit?.close();
    _exit = null;
  }

  Future<PackedActivityRows?> activityRows(ActivityHostContext context) async {
    _activityContext ??= context;
    if (_closed) return null;
    try {
      return await _serial(() async {
        if (_closed) return null;
        final target = await _worker();
        final reply = await _ask(
                target, 'activityRows', _activityContextSent ? null : context)
            as PackedActivityRows;
        _activityContextSent = true;
        return reply;
      });
    } on Object {
      if (_closed) return null;
      rethrow;
    }
  }

  /// Counts live queue states on the worker's persistent database connection.
  /// The UI isolate only receives four small integer fields.
  Future<Map<String, int>> countQueuedJobs() => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return (await _ask(target, 'jobCounts', null) as Map)
            .cast<String, int>();
      });

  Future<StateRows?> activityRowsPage(
      ActivityHostContext context, int offset, int limit) async {
    _activityContext ??= context;
    if (_closed) return null;
    try {
      return await _serial(() async {
        if (_closed) return null;
        final target = await _worker();
        final reply = await _ask(target, 'activityPage', (
          _activityContextSent ? null : context,
          offset,
          limit
        )) as (String, int, List<String>);
        _activityContextSent = true;
        return StateRows((jsonDecode(reply.$1) as List).cast<JsonMap>(),
            total: reply.$2, warnings: reply.$3);
      });
    } on Object {
      if (_closed) return null;
      rethrow;
    }
  }

  /// Assembles and materialises the home page in the catalogue worker.
  /// Calendar matching, bound episodes, saved shelves, the fallback hero scan
  /// and work-record decoding all stay there; the UI receives the finished
  /// value instead of walking or decoding catalogue-sized inputs.
  Future<UiHome> homePlan() => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        await _syncSources(target);
        final revision = ui.sources.revision;
        if (_calendarRevision != revision) {
          final material = await ui.sources.calendar?.call();
          await _ask(target, 'calendar', material);
          _calendarRevision = revision;
        }
        return await _ask(target, 'homePlan', null) as UiHome;
      });

  /// The complete compact catalogue, fetched after prepare has released the
  /// main isolate. The record block is transferred without copying its bytes
  /// and decoded one work at a time only when a view reads that work.
  Future<PackedWorks> works() => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return await _ask(target, 'works', null) as PackedWorks;
      });

  /// File locations stay in the worker catalogue and cross only when a caller
  /// actually opens an episode.
  Future<List<JsonMap>> episodeLocations(String episodeId) => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return (await _ask(target, 'locations', episodeId) as List)
            .cast<JsonMap>();
      });

  Future<String?> asset(String id) => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return await _ask(target, 'asset', id) as String?;
      });

  Future<String?> localTarget(String episodeId) => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return await _ask(target, 'localTarget', episodeId) as String?;
      });

  Future<String> canonical(String id) => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return await _ask(target, 'canonical', id) as String;
      });

  Future<List<UiEpisode>> episodes(String workId, {int? season}) =>
      _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return (await _ask(target, 'episodes', (workId, season)) as List)
            .cast<UiEpisode>();
      });

  Future<UiEpisode?> episode(String episodeId) => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return await _ask(target, 'episode', episodeId) as UiEpisode?;
      });

  Future<String?> parent(String id) => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return await _ask(target, 'parent', id) as String?;
      });

  /// Memory context is capped, but its redaction regexes still exceed the main
  /// isolate budget in JIT builds. Keep one small worker alive for this rather
  /// than spawn one per turn or rebuild the catalogue worker after compose.
  Future<String> redactText(String value) async {
    if (_closed) return redactMemoryTextOffMain(value);
    try {
      final target = await _startRedactor();
      return await _request(
          target, 'redact', (value, SecretRedactor.remembered()),
          exited: _redactorExited.future) as String;
    } on Object {
      return redactMemoryTextOffMain(value);
    }
  }

  /// The same small worker handles a Hook payload without spawning another
  /// isolate for every event. The UI isolate still has to hand the value to
  /// the worker, but keeps the redaction regexes and result construction away.
  Future<Object?> redactJson(Object? value) async {
    if (_closed) return redactHarnessJsonOffMain(value);
    try {
      final target = await _startRedactor();
      return await _request(
          target, 'redactJson', (value, SecretRedactor.remembered()),
          exited: _redactorExited.future);
    } on Object {
      return redactHarnessJsonOffMain(value);
    }
  }

  Map<String, StateView>? _syncedViews;
  Future<void> _syncViews(SendPort target, JsonMap input) async {
    final required = <String>{};
    void include(String name) {
      if (!required.add(name)) return;
      final view = ui.state.views[name];
      if (view == null) return;
      for (final relation in view.relations.values) {
        include(relation.view);
      }
    }

    include(input['view'] as String);
    final synced = _syncedViews ??= {};
    final pending = [
      for (final name in required)
        if (ui.state.views[name] case final view?
            when !view.background && !identical(synced[name], view))
          view
    ];
    if (pending.isEmpty) return;
    // Background views already exist in the worker with the same registration.
    // Only host-only schemas cross the isolate, and only those a query needs.
    await _ask(target, 'views', [
      for (final view in pending)
        (
          view.name,
          view.description,
          view.fields,
          view.cursorKey,
          view.cursorOrder,
          view.relations,
          view.background,
          view.readAll != null
        )
    ]);
    for (final view in pending) {
      synced[view.name] = view;
    }
  }

  Future<JsonMap> query(JsonMap input) async {
    if (input['view'] == 'library.merged') await ui.meshLibrary?.prepareIndex();
    return _serial(() async {
      if (_closed) throw StateError('Library worker is closed');
      final target = await _worker();
      await _syncSources(target);
      final isActivity = input['view'] == 'activity';
      ActivityHostContext? activityContext;
      if (isActivity && !_activityContextSent) {
        var context = _activityContext;
        if (context == null) {
          final prepared = await ui.state.prepareActivity?.call();
          if (prepared is ActivityHostContext) context = prepared;
        }
        if (context is! ActivityHostContext) {
          throw StateError('Activity state is unavailable');
        }
        _activityContext = context;
        activityContext = context;
      }
      await _syncViews(target, input);
      final reply = isActivity
          ? await _ask(target, 'queryActivity', (input, activityContext))
          : await _ask(target, 'query', (input, null));
      if (reply is Uint8List) {
        if (isActivity) _activityContextSent = true;
        return jsonDecode(utf8.decode(gzip.decode(reply))) as JsonMap;
      }
      return reply as JsonMap;
    });
  }

  Future<void> close() => _serial(() async {
        if (_closed) return;
        try {
          if (_starting != null) {
            final target = await _worker();
            await _ask(target, 'close', null);
          }
        } finally {
          _closed = true;
          _isolate?.kill(priority: Isolate.immediate);
          _forgetWorker(restore: false);
          final redactor = _redactorStarting;
          if (redactor != null) {
            try {
              await _request(await redactor, 'close', null,
                  exited: _redactorExited.future);
            } on Object {
              // The worker may already have stopped.
            }
          }
          _redactorIsolate?.kill(priority: Isolate.immediate);
          _redactorExit?.close();
          _redactorExit = null;
          _redactorStarting = null;
        }
      });
}

Future<void> _redactionEntry(SendPort ready) async {
  final requests = ReceivePort();
  ready.send(requests.sendPort);
  await for (final message in requests) {
    await _answer(message, (method, input) async {
      switch (method) {
        case 'redact':
          final (value, remembered) =
              input as (String, Map<String, CredentialRef>);
          for (final MapEntry(key: secret, value: ref) in remembered.entries) {
            SecretRedactor.remember(ref, secret);
          }
          return redactMemoryText(value);
        case 'redactJson':
          final (value, remembered) =
              input as (Object?, Map<String, CredentialRef>);
          for (final MapEntry(key: secret, value: ref) in remembered.entries) {
            SecretRedactor.remember(ref, secret);
          }
          return redactHarnessJson(value);
        case 'close':
          return const _ExitWith(null);
        default:
          throw StateError('Unknown redaction operation: $method');
      }
    });
  }
}

typedef _View = (
  String,
  String,
  ObjectSchema,
  String?,
  List<JsonMap>,
  Map<String, StateRelation>,
  bool,
  bool
);

Future<void> _entry(
    (
      SendPort,
      SendPort,
      String,
      String,
      String,
      Future<JsonMap> Function(String)
    ) args) async {
  try {
    await _serve(args);
  } catch (error) {
    args.$1.send(error is Failure ? error : error.toString());
  }
}

Future<void> _serve(
    (
      SendPort,
      SendPort,
      String,
      String,
      String,
      Future<JsonMap> Function(String)
    ) args) async {
  final (ready, host, databasePath, rootPath, owner, subtitleProbe) = args;
  final requests = ReceivePort();
  // No migrations, cache pruning or business-service startup on this second
  // connection. Core owns the schema and creates it before the worker starts.
  sqfliteFfiInit();
  final db = await databaseFactoryFfiNoIsolate.openDatabase(databasePath,
      options: OpenDatabaseOptions(
          singleInstance: false,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
            await db.execute('PRAGMA busy_timeout = 5000');
          }));
  final sources = StateSources();
  var roots = <String>[];
  final media = MediaService(
      store: IdentityStore(db, owner),
      providers: [TmdbMetadataProvider(_Transport(host))],
      classic: NoClassic(),
      authorizedRoots: () => roots);
  ActivityHostContext? activityContext;
  Future<StateRows> readActivity() async {
    final context = activityContext ??=
        await _request(host, 'activity', null) as ActivityHostContext?;
    if (context == null) {
      return await _request(host, 'read', ('activity', 0, 0, true))
          as StateRows;
    }
    final (events, warnings) = await readActivityFromDatabase(db, context);
    return StateRows(events, warnings: warnings);
  }

  final state = StateCapability([
    ...publicStateViews(
        media: media,
        settings: SettingsRegistry(db, const []),
        danmaku: DanmakuService(
            store: DanmakuStore(media.store),
            sources: const [],
            player: NoPlayer()),
        mesh: NoMesh(),
        sources: sources),
    Followups.viewForDatabase(db),
    StateView(
        name: 'activity',
        background: true,
        description: '',
        fields: activityFields,
        readAll: readActivity,
        readPage: (offset, limit) async {
          final rows = await readActivity();
          return StateRows(rows.rows.skip(offset).take(limit).toList(),
              warnings: rows.warnings, total: rows.rows.length);
        },
        read: (offset, limit) async =>
            (await readActivity()).rows.skip(offset).take(limit).toList()),
  ]);
  final ui = UiDataService(
      media,
      TaskEngine(store: SqliteJobStore.fromDatabase(db), ownerDeviceId: owner),
      state,
      sources,
      Directory(rootPath),
      _Vault(host));
  ui.subtitles = _Subtitles(db);
  LibraryDataService(ui).register(state);
  Future<void> releaseResources() async {
    ui.artwork.close();
    await sources.close();
    await media.store.closeEvents();
    await db.close();
  }

  final projection = LibraryProjection(ui, owner);
  await projection.initialize();
  sources.canonicalEntityId =
      (id) async => projection.snapshot.aliases[id] ?? id;
  sources.cachedArtwork = ui.artwork.cached;
  var cachedDescriptors = <_View>[];
  Future<LibraryBuildResult> buildCurrent(String projectionOwner) async {
    var builds = 0;
    for (var attempt = 0; attempt < 3; attempt++) {
      final stamp = jsonEncode([projectionOwner, await ui.catalogueStamp()]);
      if (projection.builtStamp == stamp) {
        return LibraryBuildResult(stamp, builds);
      }
      await projection.build(stamp);
      builds++;
    }
    return LibraryBuildResult(projection.builtStamp!, builds);
  }

  ready.send(requests.sendPort);
  // Mutations and queries observe the previous completed operation. This queue
  // exists only in the worker; its lifetime is the catalogue's lifetime.
  await for (final message in requests) {
    await _answer(message, (method, input) async {
      switch (method) {
        case 'snapshot':
          final (query, revision) = input as (JsonMap, int);
          return projection.page(query, revision);
        case 'merge':
          return projection.mergeProgress(input as Map<String, JsonMap>);
        case 'saved':
          final peers = <String, JsonMap>{};
          for (final row
              in await db.query('ui_cache', where: "id LIKE 'mesh:peer:%'")) {
            final value = jsonDecode(row['payload'] as String) as JsonMap;
            peers[(row['id'] as String).substring(10)] = value;
          }
          return peers;
        case 'indexers':
          final (danmaku, subtitles, preferences) =
              input as (bool, bool, SubtitleIndexPreferences);
          final locations = await db.query('media_locations',
              columns: ['file_id', 'locator'],
              where: 'source=? AND owner_device_id=?',
              whereArgs: ['local', owner]);
          return {
            'sidecars': danmaku
                ? await reconcileSidecarIndex(
                    store: DanmakuStore(media.store),
                    db: db,
                    locations: locations)
                : null,
            'subtitles': subtitles
                ? await reconcileSubtitleIndex(
                    db: db,
                    identities: media.store,
                    root: Directory(rootPath),
                    locations: locations,
                    probe: subtitleProbe,
                    preferences: preferences)
                : null,
          };
        case 'sources':
          final (history, continuing, authorized) =
              input as (List<JsonMap>?, List<JsonMap>?, List<String>);
          sources.history = history == null ? null : () => history;
          sources.continueWatching =
              continuing == null ? null : () => continuing;
          roots = authorized;
          return null;
        case 'calendar':
          final material = input as CalendarMaterial?;
          sources.calendar = material == null ? null : () async => material;
          return null;
        case 'build':
          await projection.build(input as String);
          return null;
        case 'catalogueEpoch':
          final row = await db.rawQuery(
              "SELECT COALESCE((SELECT n FROM change_epochs WHERE name='catalogue'),0) AS n");
          return row.single['n'] as int;
        case 'buildCurrent':
          return buildCurrent(input as String);
        case 'prepare':
          final (
            projectionOwner,
            peers,
            peerRevision,
            online,
            onlineRevision,
            account,
            composedStamp
          ) = input as (
            String,
            Map<String, JsonMap>?,
            int,
            Map<String, bool>?,
            int,
            String?,
            String?
          );
          final built = await buildCurrent(projectionOwner);
          final compositionStamp = jsonEncode([
            projectionOwner,
            built.stamp,
            peerRevision,
            onlineRevision,
            account
          ]);
          if (composedStamp == compositionStamp) {
            return LibraryPrepareResult(
                null, built.stamp, compositionStamp, built.builds,
                composed: false);
          }
          await projection.compose(
              peers ?? projection.peers, online ?? projection.online, account);
          return LibraryPrepareResult(
              null, built.stamp, compositionStamp, built.builds,
              composed: true);
        case 'restore':
          final (peers, online, account) =
              input as (Map<String, JsonMap>, Map<String, bool>, String?);
          await projection.compose(peers, online, account);
          return null;
        case 'compose':
          final (peers, online, account) =
              input as (Map<String, JsonMap>, Map<String, bool>, String?);
          final snapshot = await projection.compose(peers, online, account);
          // The worker ends right after this reply; its database connection
          // and clients go with it now, not whenever the heap is collected.
          await releaseResources();
          return _ExitWith(snapshot);
        case 'progress':
          return projection.progress(input as List<JsonMap>);
        case 'search':
          final (query, limit, episodeLimit) = input as (String, int, int?);
          return projection.search(query, limit, episodeLimit);
        case 'searchWorkIds':
          return projection.searchWorkIds(input as List<ExternalRef>);
        case 'managementTargets':
          return projection.managementTargets(input as List<String>);
        case 'evidence':
          return projection.evidence(input as String);
        case 'activityRows':
          activityContext = (input as ActivityHostContext?) ?? activityContext;
          final (events, warnings) = await readActivityFromDatabase(
              db,
              activityContext ??
                  await _request(host, 'activity', null)
                      as ActivityHostContext);
          return packActivityRows(events, warnings);
        case 'activityPage':
          final (context, offset, limit) =
              input as (ActivityHostContext?, int, int);
          activityContext = context ?? activityContext;
          final (events, warnings) = await readActivityFromDatabase(
              db,
              activityContext ??
                  await _request(host, 'activity', null)
                      as ActivityHostContext);
          return (
            jsonEncode(events.skip(offset).take(limit).toList()),
            events.length,
            warnings
          );
        case 'jobCounts':
          final rows = await db.rawQuery('SELECT type, COUNT(*) AS n FROM jobs '
              "WHERE state IN ('queued', 'waiting_retry', 'interrupted') "
              'GROUP BY type');
          return <String, int>{
            for (final row in rows) row['type'] as String: row['n'] as int
          };
        case 'homePlan':
          return _DetachedReply(await _homePlan(
              db, media, sources, ui.engine, projection.snapshot));
        case 'works':
          return _packedWorks(projection.snapshot);
        case 'locations':
          final id = input as String;
          final target = projection.canonical(id);
          return projection.snapshot.locations[target] ?? const <JsonMap>[];
        case 'asset':
          return projection.snapshot.assets[input as String];
        case 'localTarget':
          final id = input as String;
          final target = projection.canonical(id);
          return projection.snapshot.localTargets[target];
        case 'canonical':
          return projection.canonical(input as String);
        case 'episodes':
          final (workId, season) = input as (String, int?);
          final target = projection.canonical(workId);
          return [
            for (final episode
                in projection.snapshot.episodes[target] ?? const <UiEpisode>[])
              if (season == null || episode.season == season) episode
          ];
        case 'episode':
          final id = input as String;
          final target = projection.canonical(id);
          final workId = projection.snapshot.episodeParents[target];
          if (workId == null) return null;
          for (final episode
              in projection.snapshot.episodes[workId] ?? const <UiEpisode>[]) {
            if (episode.episodeId == target) return episode;
          }
          return null;
        case 'parent':
          final id = input as String;
          final target = projection.canonical(id);
          if (projection.snapshot.works.containsKey(target)) return target;
          final workId = projection.snapshot.episodeParents[target];
          return workId == null ? null : projection.canonical(workId);
        case 'views':
          cachedDescriptors = [
            ...cachedDescriptors,
            ...(input as List<_View>),
          ];
          return null;
        case 'queryActivity':
          final (query, suppliedActivityContext) =
              input as (JsonMap, ActivityHostContext?);
          activityContext = suppliedActivityContext ?? activityContext;
          final result = await state.query(query);
          return Uint8List.fromList(
              gzip.encode(utf8.encode(jsonEncode(result))));
        case 'query':
          final (query, _) = input as (JsonMap, ActivityHostContext?);
          final descriptors = cachedDescriptors;
          final views = [...state.views.values];
          for (final descriptor in descriptors) {
            final (
              name,
              description,
              fields,
              key,
              order,
              relations,
              background,
              all
            ) = descriptor;
            final local = state.views[name];
            Future<List<JsonMap>> read(int offset, int limit) async {
              if (name == 'library.merged') {
                return [
                  for (final work in projection.snapshot.works.values
                      .skip(offset)
                      .take(limit))
                    {
                      'id': work.workId,
                      ...workJson(work),
                      'episodes': [
                        for (final episode
                            in projection.snapshot.episodes[work.workId] ??
                                <UiEpisode>[])
                          episodeJson(episode)
                      ]
                    }
                ];
              }
              return background && local != null
                  ? local.read(offset, limit)
                  : await _request(host, 'read', (name, offset, limit, false))
                      as List<JsonMap>;
            }

            final page =
                background && local?.readPage != null ? local!.readPage : null;
            views.add(StateView(
                name: name,
                description: description,
                fields: fields,
                cursorKey: key,
                cursorOrder: order,
                relations: relations,
                read: read,
                readPage: page,
                readAll: all
                    ? () async => background && local?.readAll != null
                        ? await local!.readAll!()
                        : await _request(host, 'read', (name, 0, 0, true))
                            as StateRows
                    : null));
          }
          return StateCapability(views).query(query);
        case 'close':
          await releaseResources();
          requests.close();
          return null;
        default:
          throw StateError('Unknown library operation: $method');
      }
    });
  }
}

final class _Vault implements CredentialVault {
  _Vault(this.host);
  final SendPort host;
  @override
  Future<String?> read(CredentialRef ref) async =>
      await _request(host, 'vault', ref) as String?;
  @override
  Future<void> write(CredentialRef ref, String secret) =>
      throw UnsupportedError('Library reads credentials only');
  @override
  Future<void> delete(CredentialRef ref) =>
      throw UnsupportedError('Library reads credentials only');
}

typedef _HomeLink = ({String fileId, String workId, List<String> episodeIds});

Future<JsonMap> _homeLinks(Database db, MediaService media,
    StateSources sources, Map<String, String> aliases) async {
  final continuing = sources.continueWatching?.call() ?? const <JsonMap>[];
  final history = sources.history?.call() ?? const <JsonMap>[];
  bool ongoing(JsonMap row) {
    final progress = (row['watchProgress'] as num?)?.toDouble() ?? 0;
    return progress > 0 && progress < .95;
  }

  final wanted = <String>{
    for (final row in continuing)
      if (row['filePath'] is String) row['filePath'] as String,
    for (final row in history)
      if (ongoing(row) && row['filePath'] is String) row['filePath'] as String,
  };
  final links = <String, _HomeLink>{};
  final locators = wanted.toList(growable: false);
  for (var start = 0; start < locators.length; start += 250) {
    final page =
        locators.sublist(start, (start + 250).clamp(0, locators.length));
    final rows = await db.rawQuery(
        'SELECT l.locator, l.file_id AS fileId, fe.episode_id AS episodeId, r.parent_id AS workId '
        'FROM media_locations l '
        'JOIN media_file_episodes fe ON fe.file_id = l.file_id '
        'JOIN media_entities e ON e.id = fe.episode_id '
        'JOIN media_entities r ON r.id = e.parent_id '
        'WHERE l.owner_device_id = ? AND l.locator IN (${List.filled(page.length, '?').join(',')}) '
        'ORDER BY l.id, fe.ordinal',
        [media.store.ownerDeviceId, ...page]);
    for (final row in rows) {
      final locator = row['locator'] as String;
      final existing = links[locator];
      if (existing == null) {
        links[locator] = (
          fileId: row['fileId'] as String,
          workId: row['workId'] as String,
          episodeIds: [row['episodeId'] as String],
        );
      } else {
        existing.episodeIds.add(row['episodeId'] as String);
      }
    }
  }

  String canonical(String id) => aliases[id] ?? id;
  Future<_HomeLink?> link(String path) async {
    var found = links[path];
    if (found != null) return found;
    final resolved = await visibleLocator(path, media);
    if (resolved == null || resolved == path) return null;
    found = links[resolved];
    if (found != null) return found;
    final rows = await db.rawQuery(
        'SELECT l.locator, l.file_id AS fileId, fe.episode_id AS episodeId, r.parent_id AS workId '
        'FROM media_locations l '
        'JOIN media_file_episodes fe ON fe.file_id = l.file_id '
        'JOIN media_entities e ON e.id = fe.episode_id '
        'JOIN media_entities r ON r.id = e.parent_id '
        'WHERE l.owner_device_id = ? AND l.locator=? '
        'ORDER BY l.id, fe.ordinal',
        [media.store.ownerDeviceId, resolved]);
    for (final row in rows) {
      final existing = links[resolved];
      if (existing == null) {
        links[resolved] = (
          fileId: row['fileId'] as String,
          workId: row['workId'] as String,
          episodeIds: [row['episodeId'] as String],
        );
      } else {
        existing.episodeIds.add(row['episodeId'] as String);
      }
    }
    return links[resolved];
  }

  final continueLinks = <JsonMap?>[];
  final following = <String>{}, followingRaw = <String>{};
  for (final row in continuing) {
    final path = row['filePath'] as String?;
    final found = path == null ? null : await link(path);
    if (found == null) {
      continueLinks.add(null);
      continue;
    }
    final workId = canonical(found.workId);
    followingRaw.add(found.workId);
    following.add(workId);
    continueLinks.add({
      'workId': workId,
      'episodeIds': [for (final id in found.episodeIds) canonical(id)],
    });
  }
  for (final row in history.where(ongoing)) {
    final path = row['filePath'] as String?;
    if (path == null) continue;
    if (await link(path) case final found?) {
      followingRaw.add(found.workId);
      following.add(canonical(found.workId));
    }
  }
  return {
    'continue': continueLinks,
    'following': following.toList(growable: false),
    'followingRaw': followingRaw.toList(growable: false),
  };
}

String? _homeCaption(UiWork work, UiEpisode? episode) {
  if (episode == null) return null;
  final left = episode.runtime != null &&
          episode.progress != null &&
          episode.progress! > 0 &&
          episode.progress! < 1
      ? (episode.runtime!.inMilliseconds * (1 - episode.progress!) / 60000)
          .ceil()
      : null;
  if (work.film) return left == null ? null : '剩 $left 分钟';
  final caption = [
    if (episode.number case final number?) '第 $number 集',
    if (left != null) '剩 $left 分钟',
  ].join(' · ');
  return caption.isEmpty ? null : caption;
}

UiShelfItem _homeItem(UiWork work, UiEpisode? episode,
        {String? caption, String? badge}) =>
    UiShelfItem(work, episode: episode, caption: caption, badge: badge);

/// Resolves an entity or file mentioned by a job to a work in [snapshot].
/// This mirrors the UI lookup without crossing back to the host for every id.
Future<String?> _homeJobParent(Database db, LibrarySnapshot snapshot, String id,
    [Set<String>? visited]) async {
  visited ??= <String>{};
  if (!visited.add(id)) return null;
  final target = snapshot.aliases[id] ?? id;
  if (snapshot.works.containsKey(target)) return target;
  final episodeParent = snapshot.episodeParents[target];
  if (episodeParent != null) {
    return snapshot.aliases[episodeParent] ?? episodeParent;
  }
  final links = await db.query('media_file_episodes',
      columns: ['episode_id'], where: 'file_id=?', whereArgs: [id], limit: 1);
  if (links.isEmpty) return null;
  return _homeJobParent(
      db, snapshot, links.single['episode_id'] as String, visited);
}

Future<String?> _homeJobWork(
    Database db, LibrarySnapshot snapshot, Job job) async {
  final ids = [
    job.input['workId'],
    job.input['entityId'],
    job.input['fileId'],
    ...?job.receipt?.details['workIds'] as List?,
    ...?job.receipt?.details['fileIds'] as List?,
    for (final file in job.checkpoint['completedFiles'] as List? ?? [])
      if (file is Map && file['media'] is Map) (file['media'] as Map)['fileId'],
  ];
  for (final id in ids.whereType<String>()) {
    final work = await _homeJobParent(db, snapshot, id);
    if (work != null) return work;
  }
  return null;
}

/// Builds and materialises the home page in the catalogue worker. Calendar
/// matching, bound episodes, saved shelves and the fallback hero scan all walk
/// catalogue-sized inputs, so none of that or its record decoding reaches the
/// UI isolate.
Future<UiHome> _homePlan(Database db, MediaService media, StateSources sources,
    TaskEngine engine, LibrarySnapshot snapshot) async {
  final works = snapshot.works;
  final aliases = snapshot.aliases;
  String canonical(String id) => aliases[id] ?? id;
  UiWork? work(String id) => works[canonical(id)];
  List<UiEpisode> episodes(String workId) =>
      snapshot.episodes[canonical(workId)] ?? const <UiEpisode>[];

  final shelves = <UiShelf>[];
  final continuing = <UiShelfItem>[];
  final continuingIds = <String>{};
  final seen = <String>{};
  final continueRows = sources.continueWatching?.call() ?? const <JsonMap>[];

  // With no Classic history, the published progress is the only source of
  // in-progress works. This remains a worker-side scan.
  if (sources.continueWatching == null && sources.history == null) {
    for (final work in snapshot.orderedWorks) {
      final episode = episodes(work.workId)
          .where((episode) =>
              (episode.progress ?? 0) > 0 && (episode.progress ?? 0) < 1)
          .firstOrNull;
      if (episode != null && seen.add(work.workId)) {
        continuing.add(
            _homeItem(work, episode, caption: _homeCaption(work, episode)));
        continuingIds.add(work.workId);
      }
    }
  }

  final links = await _homeLinks(db, media, sources, aliases);
  final linkedRows = (links['continue'] as List? ?? const []).cast<JsonMap?>();
  for (var index = 0; index < continueRows.length; index++) {
    final path = continueRows[index]['filePath'];
    if (path is! String) continue;
    final linked = index < linkedRows.length ? linkedRows[index] : null;
    if (linked == null) continue;
    final workId = linked['workId'] as String;
    if (!seen.add(workId)) continue;
    final linkedIds = <String>{
      for (final id
          in (linked['episodeIds'] as List? ?? const []).whereType<String>())
        canonical(id),
    };
    final itemWork = work(workId);
    if (itemWork == null) continue;
    final episode = episodes(itemWork.workId)
        .where((episode) =>
            linkedIds.contains(episode.episodeId) &&
            (episode.progress ?? 0) < 1)
        .firstOrNull;
    continuing.add(
        _homeItem(itemWork, episode, caption: _homeCaption(itemWork, episode)));
    continuingIds.add(itemWork.workId);
  }
  if (continuing.isNotEmpty) {
    shelves.add(UiShelf(
        id: 'continue',
        title: '继续观看',
        kind: UiShelfKind.continueWatching,
        items: continuing));
  }

  final following = <String>{
    ...seen,
    ...continuingIds,
    ...(links['following'] as List? ?? const []).whereType<String>(),
    ...(links['followingRaw'] as List? ?? const []).whereType<String>(),
  };
  final airingItems = <UiShelfItem>[];
  if (sources.calendar != null) {
    for (final update in await airing.todayUpdates(
        media.store, following, (await sources.calendar!())?.rows() ?? const [])) {
      final itemWork = work(update['workId'] as String);
      if (itemWork == null) continue;
      final matches = await db.rawQuery(
          "SELECT b.entity_id FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id WHERE b.status='accepted' AND o.provider='dandanplay' AND o.object_type='episode' AND o.external_id=?",
          [update['externalEpisodeId']]);
      final matchingIds = <String>{
        for (final match in matches) canonical(match['entity_id'] as String),
      };
      final episode = episodes(itemWork.workId)
          .where((episode) => matchingIds.contains(episode.episodeId))
          .firstOrNull;
      airingItems.add(
          _homeItem(itemWork, episode, caption: update['caption'] as String?));
    }
  }
  if (airingItems.isNotEmpty) {
    shelves.add(UiShelf(
        id: 'airing',
        title: '今天更新',
        kind: UiShelfKind.airing,
        items: airingItems));
  }

  UiHero? hero;
  for (final row in await db.query('ui_shelves', orderBy: 'rowid')) {
    final shelf = decodeMediaJson(row['payload']);
    final items = <UiShelfItem>[];
    for (final item in (shelf['items'] as List).cast<Map>()) {
      final itemWork = work(item['workId'] as String);
      if (itemWork == null) continue;
      if (shelf['placement'] == 'hero') {
        hero = UiHero(itemWork, note: shelf['note'] as String?);
      } else {
        items.add(_homeItem(itemWork, itemWork.next,
            caption: item['note'] as String? ??
                _homeCaption(itemWork, itemWork.next)));
      }
    }
    if (shelf['placement'] == 'shelf') {
      shelves.add(UiShelf(
          id: row['id'] as String,
          title: shelf['title'] as String,
          kind: UiShelfKind.agent,
          items: items));
    }
  }

  final recent = [
    for (final work in snapshot.orderedWorks.take(20))
      _homeItem(work, work.next, caption: _homeCaption(work, work.next)),
  ];
  if (recent.isNotEmpty) {
    shelves.add(UiShelf(
        id: 'recent', title: '最近添加', kind: UiShelfKind.recent, items: recent));
  }

  if (hero == null) {
    for (var offset = 0; hero == null; offset += 20) {
      final jobs = await engine.listRecent(
          state: JobState.succeeded, limit: 20, offset: offset);
      if (jobs.isEmpty) break;
      for (final job in jobs) {
        final workId = await _homeJobWork(db, snapshot, job);
        if (workId == null) continue;
        final itemWork = work(workId);
        if (itemWork?.next?.playable == true) {
          hero = UiHero(itemWork!);
          break;
        }
      }
    }
    if (hero == null) {
      final ready = await db.rawQuery(
          "SELECT r.parent_id AS work_id FROM media_locations l JOIN media_file_episodes fe ON fe.file_id=l.file_id JOIN media_entities e ON e.id=fe.episode_id JOIN media_entities r ON r.id=e.parent_id WHERE l.available=1 ORDER BY l.rowid DESC");
      for (final row in ready) {
        final itemWork = work(row['work_id'] as String);
        if (itemWork?.next?.playable == true) {
          hero = UiHero(itemWork!);
          break;
        }
      }
    }
    if (hero == null) {
      String? fallback;
      for (final item in recent) {
        final workId = item.work.workId;
        if (continuingIds.contains(workId) &&
            work(workId)?.next?.playable == true) {
          fallback = workId;
          break;
        }
      }
      fallback ??= continuingIds.firstOrNull;
      if (fallback != null) hero = UiHero(work(fallback)!);
    }
  }
  return UiHome(hero: hero, shelves: shelves);
}

final class _Transport implements MetadataTransport {
  _Transport(this.host);
  final SendPort host;
  @override
  Future<JsonMap> request(String path,
          {Map<String, String> query = const {}, JsonMap? body}) async =>
      await _request(host, 'metadata', ('tmdb', path, query, body)) as JsonMap;
}

final class _Subtitles implements SubtitleFacts {
  _Subtitles(this.db);
  final Database db;
  @override
  Future<({List<JsonMap> tracks, List<JsonMap> files})> episodeSubtitles(
          String id) =>
      readEpisodeSubtitles(db, id);
  @override
  Future<List<JsonMap>> episodeTracks(String id) async =>
      (await episodeSubtitles(id)).tracks;
  @override
  Future<List<JsonMap>> episodeFiles(String id) async =>
      (await episodeSubtitles(id)).files;
}
