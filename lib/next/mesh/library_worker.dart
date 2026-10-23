import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../danmaku/service.dart';
import '../danmaku/store.dart';
import '../headless/ports.dart';
import '../media/identity_store.dart';
import '../media/media_service.dart';
import '../media/metadata_provider.dart';
import '../media/provider_transport.dart';
import '../media/providers.dart';
import '../settings/registry.dart';
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
        exited.then<Object?>((_) => throw StateError('Library worker exited'))
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
    reply.send((true, await dispatch(method, input)));
  } catch (error) {
    reply.send((false, error is Failure ? error : error.toString()));
  }
}

/// One worker per catalogue lifetime. Only plugin/network primitives and live
/// host observations cross back to the UI isolate; SQL and projections do not.
final class LibraryWorker {
  LibraryWorker(this.ui);
  final UiDataService ui;
  Isolate? _isolate;
  ReceivePort? _host;
  ReceivePort? _exit;
  final _exited = Completer<void>();
  Future<SendPort>? _starting;
  bool _closed = false;
  Future<SendPort> _start() => _starting ??= (() async {
        final ready = ReceivePort();
        final host = _host = ReceivePort();
        final exited = _exit = ReceivePort();
        exited.listen((_) {
          if (!_exited.isCompleted) _exited.complete();
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
            _exited.future.then<Object?>(
                (_) => throw StateError('Library worker exited during startup'))
          ]);
          if (result is Failure) throw result;
          if (result is String) throw StateError(result);
          return result as SendPort;
        } finally {
          ready.close();
        }
      })();

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
      case 'read':
        final (name, offset, limit, all) = input as (String, int, int, bool);
        final view = ui.state.views[name]!;
        return all ? await view.readAll!() : await view.read(offset, limit);
      default:
        throw StateError('Unknown library host request: $method');
    }
  }

  Future<Object?> call(String method, [Object? input]) async {
    if (_closed) throw StateError('Library worker is closed');
    final target = await _start();
    return _request(target, method, input, exited: _exited.future);
  }

  /// Suppliers are evaluated only after their revision moves. The worker
  /// retains this input, rather than shipping it again for each read.
  int? _sourceRevision;
  Future<void> syncSources() async {
    if (_sourceRevision == ui.sources.revision) return;
    final revision = ui.sources.revision;
    await call('sources', (
      ui.sources.history?.call(),
      ui.sources.continueWatching?.call(),
      ui.media.authorizedRoots().toList(),
    ));
    _sourceRevision = revision;
  }

  Future<void> build(String stamp) async {
    await syncSources();
    await call('build', stamp);
  }

  Future<LibrarySnapshot> compose(Map<String, JsonMap> peers,
          Map<String, bool> online, String? account) async =>
      await call('compose', (peers, online, account)) as LibrarySnapshot;

  Future<JsonMap> query(JsonMap input) async {
    if (input['view'] == 'library.merged') await ui.meshLibrary?.prepareIndex();
    await syncSources();
    // Descriptors contain schemas, never the closures that own GUI services.
    final descriptors = [
      for (final view in ui.state.views.values)
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
    return await call('query', (input, descriptors)) as JsonMap;
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      if (_starting != null) await call('close');
    } finally {
      _closed = true;
      _isolate?.kill(priority: Isolate.immediate);
      _host?.close();
      _exit?.close();
    }
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
  final state = StateCapability(publicStateViews(
      media: media,
      settings: SettingsRegistry(db, const []),
      danmaku: DanmakuService(
          store: DanmakuStore(media.store),
          sources: const [],
          player: NoPlayer()),
      mesh: NoMesh(),
      sources: sources));
  final ui = UiDataService(
      media,
      TaskEngine(store: SqliteJobStore.fromDatabase(db), ownerDeviceId: owner),
      state,
      sources,
      Directory(rootPath),
      _Vault(host));
  ui.subtitles = _Subtitles(db);
  LibraryDataService(ui).register(state);
  final projection = LibraryProjection(ui, owner);
  await projection.initialize();
  sources.canonicalEntityId =
      (id) async => projection.snapshot.aliases[id] ?? id;
  sources.cachedArtwork = ui.artwork.cached;
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
        case 'compose':
          final (peers, online, account) =
              input as (Map<String, JsonMap>, Map<String, bool>, String?);
          return projection.compose(peers, online, account);
        case 'progress':
          return projection.progress(input as List<JsonMap>);
        case 'query':
          final (query, descriptors) = input as (JsonMap, List<_View>);
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
          ui.artwork.close();
          await sources.close();
          await media.store.closeEvents();
          await db.close();
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
