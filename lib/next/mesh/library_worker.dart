import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_vault.dart' show CredentialRef;
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../danmaku/service.dart';
import '../followups/service.dart';
import '../danmaku/store.dart';
import '../headless/ports.dart';
import '../harness_redaction.dart';
import '../media/identity_store.dart';
import '../media/media_service.dart';
import '../media/metadata_provider.dart';
import '../media/provider_transport.dart';
import '../media/providers.dart';
import '../settings/registry.dart';
import '../state/activity.dart';
import '../state/query.dart';
import '../state/views.dart';
import '../subtitles/episode_subtitles.dart';
import '../subtitles/facts.dart';
import '../tasks/sqlite_job_store.dart';
import '../ui_data/library_service.dart';
import '../ui_data/service.dart';
import '../ui_data/ui_data.dart';
import 'library_codec.dart';
import 'library_projection.dart';

/// A request owns its reply port. Errors retain their typed Failure contract.
Future<Object?> _request(SendPort target, String method, Object? input,
    {Future<void>? exited}) async {
  final reply = ReceivePort();
  try {
    target.send((method, input, reply.sendPort));
    final response = await Future.any([
      reply.first,
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

/// One worker per catalogue lifetime. Only plugin/network primitives and live
/// host observations cross back to the UI isolate; SQL and projections do not.
final class LibraryWorker {
  LibraryWorker(this.ui) {
    // Spawn during core construction, so the first memory turn does not pay
    // for starting an isolate inside its 4 ms main-thread budget. This worker
    // stays independent of the catalogue worker, which ends after compose.
    unawaited(_startRedactor().then<void>((_) {}, onError: (_, __) {}));
  }

  final UiDataService ui;
  Isolate? _isolate;
  ReceivePort? _host;
  ReceivePort? _exit;
  Completer<void> _exited = Completer<void>();
  Future<SendPort>? _starting;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

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
                ui.media.store.ownerDeviceId
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

  Future<Object?> call(String method, [Object? input]) => _serial(() async {
        if (_closed) throw StateError('Library worker is closed');
        final target = await _worker();
        return _ask(target, method, input);
      });

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
  /// stamp on the UI isolate. A changed projection is transferred back by
  /// [Isolate.exit]; the caller only replaces its published references.
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
        if (result.composed) {
          _forgetWorker(restore: true);
          _restartWorker();
        }
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
    _syncedViews = null;
    _runtimeBuiltStamp = null;
    _needsRestore = restore;
    _host?.close();
    _host = null;
    _exit?.close();
    _exit = null;
  }

  Future<PackedActivityRows?> activityRows(ActivityHostContext context) async {
    if (_closed || _starting == null) return null;
    return await call('activityRows', context) as PackedActivityRows;
  }

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

  List<StateView>? _syncedViews;
  Future<void> _syncViews(SendPort target) async {
    final current = ui.state.views.values.toList(growable: false);
    if (_syncedViews != null &&
        _syncedViews!.length == current.length &&
        Iterable<int>.generate(current.length)
            .every((i) => identical(_syncedViews![i], current[i]))) {
      return;
    }
    // Descriptors contain schemas, never the closures that own GUI services.
    final descriptors = [
      for (final view in current)
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
    ];
    await _ask(target, 'views', descriptors);
    _syncedViews = current;
  }

  Future<JsonMap> query(JsonMap input) async {
    if (input['view'] == 'library.merged') await ui.meshLibrary?.prepareIndex();
    return _serial(() async {
      if (_closed) throw StateError('Library worker is closed');
      final target = await _worker();
      await _syncSources(target);
      await _syncViews(target);
      return await _ask(target, 'query', input) as JsonMap;
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

Future<void> _entry((SendPort, SendPort, String, String, String) args) async {
  try {
    await _serve(args);
  } catch (error) {
    args.$1.send(error is Failure ? error : error.toString());
  }
}

Future<void> _serve((SendPort, SendPort, String, String, String) args) async {
  final (ready, host, databasePath, rootPath, owner) = args;
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
  Future<StateRows> readActivity() async {
    final context =
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
        case 'sources':
          final (history, continuing, authorized) =
              input as (List<JsonMap>?, List<JsonMap>?, List<String>);
          sources.history = history == null ? null : () => history;
          sources.continueWatching =
              continuing == null ? null : () => continuing;
          roots = authorized;
          return null;
        case 'build':
          await projection.build(input as String);
          return null;
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
          final snapshot = projection.snapshot;
          await releaseResources();
          return _ExitWith(LibrarySnapshot(
              snapshot.assets,
              snapshot.works,
              snapshot.episodes,
              snapshot.aliases,
              snapshot.locations,
              snapshot.localTargets,
              snapshot.orderedWorks,
              snapshot.episodeParents,
              builtStamp: built.stamp,
              compositionStamp: compositionStamp,
              builds: built.builds,
              composed: true));
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
          final (events, warnings) =
              await readActivityFromDatabase(db, input as ActivityHostContext);
          return packActivityRows(events, warnings);
        case 'views':
          cachedDescriptors = input as List<_View>;
          return null;
        case 'query':
          final query = input as JsonMap;
          final descriptors = cachedDescriptors;
          final views = <StateView>[];
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

            views.add(StateView(
                name: name,
                description: description,
                fields: fields,
                cursorKey: key,
                cursorOrder: order,
                relations: relations,
                read: read,
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
