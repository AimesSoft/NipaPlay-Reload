import '../capabilities/user_authorization.dart';
import 'dart:async';
import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/local_media_management_api.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media/identity_store.dart';
import 'metadata.dart';
import 'search.dart';
import 'source_facts.dart';
import 'package:nipaplay/services/address_probe.dart';

/// Source configuration and discovery reuse SMB/WebDAV instances and locators.
final class MediaSourcesService {
  MediaSourcesService(this.store);
  final IdentityStore store;

  /// What was last observed of each source, kept across restarts.
  final facts = SourceFacts();
  Future<String> Function(String id)? canonicalEntityId;
  Future<JsonMap> Function(String entityId)? cachedArtwork;
  Future<JsonMap> search(String query,
          {List<String>? sourceIds, int limit = 12}) =>
      searchSources(this, query, sourceIds: sourceIds, limit: limit);
  final smb = SMBService.instance;
  final webdav = WebDAVService.instance;
  Future<JsonMap> Function(JsonMap source, String itemId, int? startPositionMs)?
      playItem;
  Future<String?> Function(JsonMap source, Future<void> stopped)?
      requestPassword;
  late TaskEngine _engine;
  TaskEngine get engine => _engine;
  StreamSubscription<Job>? _jobs;
  set engine(TaskEngine value) {
    _engine = value;
    _jobs = value.changes.listen((job) {
      if (job.type != 'media.sources.login' || !job.state.isTerminal) return;
      _passwords.remove(job.jobId);
    });
  }

  Future<void> close() async {
    if (AddressProbes.observer == facts.probe) AddressProbes.observer = null;
    await facts.flush();
    await _jobs?.cancel();
    await _tail;
    _passwords.clear();
  }

  final Map<String, String> _passwords = {};
  Future<void> _tail = Future.value();
  Future<void>? _ready;
  Future<void> ensureInitialized() => _ready ??= initialize();

  Future<List<String>> syncRoots(String id) async {
    final selected = await selection(id);
    if (selected.isNotEmpty) return selected;
    return ['/'];
  }

  final _catalogueStarts = <String, Future<void>>{};

  /// The first library visit starts discovery in the existing task engine;
  /// showing the first page does not wait for the whole server to be indexed.
  Future<void> ensureCatalogue(String id) async {
    final row = await source(id);
    final scope = jsonEncode([id, endpointOf(row)]);
    return _catalogueStarts.putIfAbsent(scope, () async {
      try {
        final roots = await syncRoots(id);
        if (roots.isEmpty) return;
        await engine
            .submit(type: 'media.sources.sync', title: '同步来源目录与资料', input: {
          'sourceId': id,
          'libraries': roots,
          ...endpointOf(row),
        });
      } catch (_) {
        _catalogueStarts.remove(scope);
        rethrow;
      }
    });
  }

  Future<T> serial<T>(Future<T> Function() run) {
    final result = _tail.then((_) => run());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> initialize() async {
    await smb.initialize();
    await webdav.initialize();
    facts.exists = _knownProbeTarget;
    AddressProbes.observer = facts.probe;
  }

  /// Sources that are configured now.
  bool _knownProbeTarget(String id) {
    final reference = key(id);
    return switch (id.split(':').first) {
      'smb' => smb.getConnectionByIdOrName(reference) != null,
      'webdav' => webdav.getConnectionByIdOrName(reference) != null,
      _ => false,
    };
  }

  String validateUrl(String value) {
    final url = value.contains('://') ? value.trim() : 'http://${value.trim()}';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const Failure(FailureCode.invalidInput,
          'Use an HTTP(S) source URL without credentials, query or fragment.');
    }
    return url.replaceFirst(RegExp(r'/+$'), '');
  }

  /// The addresses a listed source has configured (LAN and WAN), without
  /// the one currently in use, which Classic may switch on its own.
  Set<String> addressesOf(JsonMap row) => {
        for (final field in ['url', 'wanUrl'])
          if (row[field] is String && (row[field] as String).isNotEmpty)
            row[field] as String
      };

  /// The endpoint facts a background job keeps, to detect later edits.
  JsonMap endpointOf(JsonMap row) => {
        'url': row['address'],
        'addresses': addressesOf(row).toList()..sort(),
        'username': row['username'],
      };

  /// Whether two listings describe the same configured endpoints and account.
  bool sameEndpoint(JsonMap a, JsonMap b) =>
      a['url'] == b['url'] &&
      (a['wanUrl'] ?? '') == (b['wanUrl'] ?? '') &&
      a['username'] == b['username'];

  /// Whether the source still has the addresses and account a job saved.
  /// Jobs saved before dual addresses only have `url`, the single address.
  bool holdsEndpoint(JsonMap row, JsonMap saved) {
    final addresses = saved['addresses'];
    final expected = addresses is List
        ? addresses.cast<String>().toSet()
        : {if (saved['url'] is String) saved['url'] as String};
    final current = addressesOf(row);
    return current.length == expected.length &&
        current.containsAll(expected) &&
        row['username'] == saved['username'];
  }

  Future<List<String>> selection(String sourceId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('next.source.$sourceId.libraries') ?? [];
  }

  /// The sources, and with [withFacts] what was last observed of each: its
  /// addresses, its last sync, its credential and its last failure.
  Future<List<JsonMap>> list({bool withFacts = false}) async {
    final result = <JsonMap>[];
    for (final c in smb.connections) {
      final effective = smb.effectiveConnection(c);
      result.add({
        'sourceId': 'smb:${c.id}',
        'type': 'smb',
        'name': c.name,
        'url': c.hasLan ? 'smb://${c.host}:${c.port}' : '',
        'wanUrl': c.hasWan ? 'smb://${c.wanHost}:${c.wanPort}' : '',
        'address': 'smb://${effective.host}:${effective.port}',
        'host': c.host,
        'port': c.port,
        'wanHost': c.wanHost,
        'wanPort': c.wanPort,
        'username': c.username,
        'connected': c.isConnected,
        'domain': c.domain
      });
    }
    for (final c in webdav.connections) {
      result.add({
        'sourceId': 'webdav:${c.id}',
        'type': 'webdav',
        'name': c.name,
        'url': c.url,
        'wanUrl': c.wanUrl,
        'address': webdav.effectiveUrl(c),
        'username': c.username,
        'connected': c.isConnected
      });
    }
    for (final source in result) {
      source.putIfAbsent('address', () => source['url']);
      source['selectedLibraries'] =
          await selection(source['sourceId'] as String);
      source['connectionState'] =
          source['connected'] == true ? 'connected' : 'unverified';
      final error = (await SharedPreferences.getInstance())
          .getString('next.source.${source['sourceId']}.lastError');
      if (error != null) {
        source['connectionState'] = 'failed';
        source['connected'] = false;
        source['error'] = error;
      }
      if (withFacts) await _addFacts(source);
    }
    return result;
  }

  static JsonMap _entry(String role, String address, JsonMap? fact,
      {String? label, bool? enabled}) {
    final reachable = fact?['reachable'];
    return {
      'role': role,
      if (label != null) 'label': label,
      'address': address,
      if (enabled != null) 'enabled': enabled,
      'reachability': reachable == null
          ? 'unknown'
          : reachable == true
              ? 'reachable'
              : 'unreachable',
      'lastAttemptAt': fact?['lastAttemptAt'],
      'lastSuccessAt': fact?['lastSuccessAt'],
      'lastFailureAt': fact?['lastFailureAt'],
      'errorCode': fact?['errorCode'],
      'latencyMs': fact?['latencyMs'],
    };
  }

  Future<void> _addFacts(JsonMap source) async {
    final id = source['sourceId'] as String;
    final type = source['type'] as String;
    final saved = await facts.read(id);
    final probed = ((saved['addresses'] as Map?) ?? const {}).map(
        (key, value) =>
            MapEntry('$key', (value as Map).cast<String, Object?>()));
    final addresses = <JsonMap>[];
    if (type == 'smb' || type == 'webdav') {
      final classic = type == 'smb'
          ? smb.lastAddressReachability(key(id))
          : webdav.lastAddressReachability(key(id));
      JsonMap? fallback(bool? reachable) =>
          reachable == null ? null : {'reachable': reachable};
      for (final role in ['lan', 'wan']) {
        final address =
            (role == 'lan' ? source['url'] : source['wanUrl']) as String? ?? '';
        if (address.isEmpty) continue;
        addresses.add(_entry(
            role,
            address,
            probed[role] ??
                fallback(role == 'lan' ? classic?.lan : classic?.wan)));
      }
    }
    source['addresses'] = addresses;
    final check = (saved['check'] as Map?)?.cast<String, Object?>();
    source['lastCheck'] = check;
    final sync = (saved['sync'] as Map?)?.cast<String, Object?>();
    final syncedAt = source['lastSyncedAt'] as String?;
    source['sync'] = {
      'result': facts.syncResult(id, sync),
      'jobId': sync?['jobId'],
      'startedAt': sync?['startedAt'],
      'finishedAt': sync?['finishedAt'],
      'lastSuccessAt': sync?['lastSuccessAt'] ?? syncedAt,
      'indexed': sync?['indexed'],
      'errorCode': sync?['errorCode'],
    };
    final lastError = (saved['lastError'] as Map?)?.cast<String, Object?>();
    final legacy = source['error'];
    source['lastError'] = lastError == null && legacy == null
        ? null
        : {
            'code': lastError?['code'],
            'at': lastError?['at'],
            'message': legacy,
          };
    final rejection = (saved['credential'] as Map?)?.cast<String, Object?>();
    final held = await _credentialHeld(source);
    final rejectedAt = rejection?['lastRejectedAt'] as String?;
    final verifiedAt = rejection?['lastVerifiedAt'] as String?;
    final rejectedSince = rejectedAt != null &&
        (verifiedAt == null || rejectedAt.compareTo(verifiedAt) > 0);
    source['credential'] = {
      'state': held == null
          ? 'none'
          : !held
              ? 'missing'
              : rejectedSince
                  ? 'rejected'
                  : 'saved',
      'lastRejectedAt': rejectedAt,
      'lastRejectedCode': rejection?['lastRejectedCode'],
      'lastVerifiedAt': verifiedAt,
    };
  }

  /// Whether a login is on record for the source: null when it needs none,
  /// otherwise saved or not. Only presence is looked at; neither the secret
  /// nor the vault is read.
  Future<bool?> _credentialHeld(JsonMap source) async {
    final id = source['sourceId'] as String;
    final username = source['username'] as String? ?? '';
    switch (source['type']) {
      case 'smb':
        final held = await smb.getConnectionByIdOrName(key(id))?.hasPassword();
        return held == true ? true : (username.isEmpty ? null : false);
      case 'webdav':
        final held =
            await webdav.getConnectionByIdOrName(key(id))?.hasPassword();
        return held == true ? true : (username.isEmpty ? null : false);
      default:
        return null;
    }
  }

  /// A stable code for why a source could not be used. No exception text.
  static String failureCode(Object error) {
    if (error is Failure) {
      final m = error.message;
      if (m.contains('Login is required') || m.contains('Log in to the')) {
        return 'login_required';
      }
      if (m.contains('authentication failed')) return 'auth_failed';
      if (m.contains('offline')) return 'offline';
      return classifyFailure(m);
    }
    return classifyFailure(error);
  }

  Future<JsonMap> source(String id) async {
    for (final row in await list()) {
      if (row['sourceId'] == id) {
        return row;
      }
    }
    throw Failure(FailureCode.notFound, 'Unknown media source: $id');
  }

  String key(String id) => id.substring(id.indexOf(':') + 1);

  Future<JsonMap> configure(JsonMap input, {bool update = false}) =>
      serial(() async {
        final old = update ? await source(input['sourceId'] as String) : null;
        final type = old?['type'] as String? ?? input['type'] as String;
        final name =
            input['name'] as String? ?? old?['name'] as String? ?? type;
        final username =
            input['username'] as String? ?? old?['username'] as String? ?? '';
        String id;
        if (type == 'smb') {
          final previous = old == null
              ? null
              : smb.getConnectionByIdOrName(key(old['sourceId'] as String))!;
          String address(String field, String? saved) {
            final value =
                input.containsKey(field) ? input[field] as String : saved ?? '';
            final host = value.trim();
            if (host.contains('/') || host.contains('@')) {
              throw const Failure(FailureCode.invalidInput,
                  'SMB requires a host without credentials or path.');
            }
            return host;
          }

          final host = address('host', previous?.host);
          final wanHost = address('wanHost', previous?.wanHost);
          if (host.isEmpty && wanHost.isEmpty) {
            throw const Failure(FailureCode.invalidInput,
                'SMB requires a host or wanHost without credentials or path.');
          }
          if (smb.connections
              .any((c) => c.name == name && c.id != previous?.id)) {
            throw const Failure(
                FailureCode.conflict, 'SMB source name already exists.');
          }
          final c = previous?.copyWith(
                  name: name,
                  host: host,
                  username: username,
                  port: input['port'] as int?,
                  wanHost: wanHost,
                  wanPort: input['wanPort'] as int?,
                  domain: input['domain'] as String?,
                  credentialOrigin:
                      previous.credentialOrigin ?? previous.credentialAuthority,
                  isConnected: false) ??
              SMBConnection(
                  name: name,
                  host: host,
                  port: input['port'] as int? ?? 445,
                  wanHost: wanHost,
                  wanPort: input['wanPort'] as int? ?? 445,
                  username: username,
                  password: '',
                  domain: input['domain'] as String? ?? '');
          await smb.configureConnection(c);
          id = 'smb:${c.id}';
        } else if (type == 'webdav') {
          final previous = old == null
              ? null
              : webdav.getConnectionByIdOrName(key(old['sourceId'] as String))!;
          String address(String field, String? saved) {
            final value =
                input.containsKey(field) ? input[field] as String : saved ?? '';
            return value.trim().isEmpty ? '' : validateUrl(value);
          }

          final url = address('url', previous?.url);
          final wanUrl = address('wanUrl', previous?.wanUrl);
          if (url.isEmpty && wanUrl.isEmpty) {
            throw const Failure(FailureCode.invalidInput,
                'WebDAV requires a url (LAN) or wanUrl (WAN).');
          }
          if (webdav.connections
              .any((c) => c.name == name && c.id != previous?.id)) {
            throw const Failure(
                FailureCode.conflict, 'WebDAV source name already exists.');
          }
          final c = previous?.copyWith(
                  name: name,
                  url: url,
                  wanUrl: wanUrl,
                  username: username,
                  credentialOrigin:
                      previous.credentialOrigin ?? previous.credentialAuthority,
                  isConnected: false) ??
              WebDAVConnection(
                  name: name,
                  url: url,
                  wanUrl: wanUrl,
                  username: username,
                  password: '');
          await webdav.configureConnection(c);
          id = 'webdav:${c.id}';
        } else {
          throw const Failure(
              FailureCode.invalidInput, 'Choose SMB or WebDAV.');
        }
        await (await SharedPreferences.getInstance())
            .remove('next.source.$id.lastError');
        if (old != null) {
          final now = await source(id);
          if (addressesOf(now).difference(addressesOf(old)).isNotEmpty ||
              addressesOf(old).difference(addressesOf(now)).isNotEmpty ||
              now['username'] != old['username']) {
            await facts.reset(id);
          }
        }
        return {'source': await source(id)};
      });

  Future<JsonMap> remove(String id) => serial(() async {
        final row = await source(id);
        switch (row['type']) {
          case 'smb':
            await smb.removeConnection(row['name'] as String);
            await smb.persistConnections();
          case 'webdav':
            await webdav.removeConnection(row['name'] as String);
            await webdav.persistConnections();
        }
        await (await SharedPreferences.getInstance())
            .remove('next.source.$id.libraries');
        await (await SharedPreferences.getInstance())
            .remove('next.source.$id.lastError');
        await facts.clear(id);
        return {'sourceId': id, 'removed': true, 'indexedFilesPreserved': true};
      });

  Future<JsonMap> play(String sourceId, String itemId,
          {int? startPositionMs}) =>
      serial(() async {
        final row = await source(sourceId);
        final play = playItem;
        if (play == null)
          throw const Failure(
              FailureCode.unavailable, 'The NipaPlay player is not attached.');
        return play(row, itemId, startPositionMs);
      });

  Future<JsonMap> libraries(String id) => serial(() async {
        final row = await source(id);
        final result = <JsonMap>[];
        for (final entry in await _browse(row, '/', indexFiles: false)) {
          if (entry['isDirectory'] == true) {
            result.add(
                {'id': entry['id'], 'name': entry['name'], 'kind': 'folder'});
          }
        }
        return {
          'sourceId': id,
          'libraries': result,
          'selectedLibraries': await selection(id)
        };
      });

  Future<JsonMap> select(String id, List<String> ids) async {
    final target = await source(id);
    final available = (await libraries(id))['libraries'] as List<JsonMap>;
    if (ids.any((id) => !available.any((l) => l['id'] == id))) {
      throw const Failure(FailureCode.invalidInput,
          'Select library IDs returned by media.sources.libraries.');
    }
    return serial(() async {
      final row = await source(id);
      if (!sameEndpoint(row, target)) {
        throw const Failure(FailureCode.conflict,
            'Source changed while selecting libraries; select again.');
      }
      await (await SharedPreferences.getInstance())
          .setStringList('next.source.$id.libraries', ids);
      return {'sourceId': id, 'selectedLibraries': ids};
    });
  }

  Future<JsonMap> check(String id) async {
    final target = await source(id);
    final clock = Stopwatch()..start();
    try {
      await libraries(id);
    } catch (error) {
      final code = failureCode(error);
      final latency = clock.elapsedMilliseconds;
      await facts.checked(id, ok: false, errorCode: code, latencyMs: latency);
      await serial(() async {
        final row = await source(id);
        if (!sameEndpoint(row, target)) {
          throw const Failure(FailureCode.conflict,
              'Source changed while checking its connection; check again.');
        }
        await (await SharedPreferences.getInstance()).setString(
            'next.source.$id.lastError', SecretRedactor.text('$error'));
        if (row['type'] == 'smb') {
          final c = smb.getConnectionByIdOrName(key(id))!;
          await smb.configureConnection(c.copyWith(isConnected: false));
        } else if (row['type'] == 'webdav') {
          final c = webdav.getConnectionByIdOrName(key(id))!;
          await webdav.configureConnection(c.copyWith(isConnected: false));
        }
      });
      rethrow;
    }
    final latency = clock.elapsedMilliseconds;
    await facts.checked(id, ok: true, latencyMs: latency);
    return serial(() async {
      final row = await source(id);
      if (!sameEndpoint(row, target)) {
        throw const Failure(FailureCode.conflict,
            'Source changed while checking its connection; check again.');
      }
      if (row['type'] == 'smb') {
        final c = smb.getConnectionByIdOrName(key(id))!;
        await smb.configureConnection(c.copyWith(isConnected: true));
      } else if (row['type'] == 'webdav') {
        final c = webdav.getConnectionByIdOrName(key(id))!;
        await webdav.configureConnection(c.copyWith(isConnected: true));
      }
      await (await SharedPreferences.getInstance())
          .remove('next.source.$id.lastError');
      return {'source': await source(id), 'checked': true};
    });
  }

  Future<JsonMap> testConfiguration(JsonMap input) async {
    final type = input['type'] as String;
    final username = input['username'] as String? ?? '';
    if (type == 'smb') {
      final host = (input['host'] as String? ?? '').trim();
      final wanHost = (input['wanHost'] as String? ?? '').trim();
      if ((host.isEmpty && wanHost.isEmpty) ||
          [host, wanHost].any((h) => h.contains('/') || h.contains('@'))) {
        throw const Failure(FailureCode.invalidInput,
            'SMB requires a host or wanHost without credentials or a path.');
      }
      final c = SMBConnection(
          name: input['name'] as String? ?? 'Test',
          host: host,
          port: input['port'] as int? ?? 445,
          wanHost: wanHost,
          wanPort: input['wanPort'] as int? ?? 445,
          domain: input['domain'] as String? ?? '',
          username: username,
          password: '');
      await smb.listDirectory(c, '/', forceRefresh: true);
      return {'connected': true, 'authenticated': false};
    }
    if (type == 'webdav') {
      String optional(String field) {
        final value = (input[field] as String? ?? '').trim();
        return value.isEmpty ? '' : validateUrl(value);
      }

      final url = optional('url');
      final wanUrl = optional('wanUrl');
      if (url.isEmpty && wanUrl.isEmpty) {
        throw const Failure(FailureCode.invalidInput,
            'WebDAV requires a url (LAN) or wanUrl (WAN).');
      }
      final connected = await webdav.testConnection(WebDAVConnection(
          name: input['name'] as String? ?? 'Test',
          url: url,
          wanUrl: wanUrl,
          username: username,
          password: ''));
      return {'connected': connected, 'authenticated': false};
    }
    throw const Failure(FailureCode.invalidInput, 'Choose SMB or WebDAV.');
  }

  Future<void> scrape(JobContext context) async {
    final id = context.job.input['sourceId'] as String;
    await context.running(phase: 'matching');
    final results = <JsonMap>[];
    for (final path in (context.job.input['paths'] as List).cast<String>()) {
      if ((await context.snapshot()).cancelRequestedAt != null) {
        await context.cancelled(JobReceipt(
            verification: VerificationLevel.acknowledged,
            details: {'results': results}));
        return;
      }
      final counts = await serial(() async {
        final row = await source(id);
        final api = LocalMediaManagementApi();
        return row['type'] == 'webdav'
            ? api.scrapeWebDav(webdav.getConnectionByIdOrName(key(id))!, path)
            : api.scrapeSmb(smb.getConnectionByIdOrName(key(id))!, path);
      });
      results.add({'path': path, ...counts});
      await context.markSideEffectCommitted(checkpoint: {'results': results});
    }
    await context.succeed(JobReceipt(
        verification: VerificationLevel.verified,
        details: {'sourceId': id, 'results': results}));
  }

  Future<List<JsonMap>> _browse(JsonMap row, String? parent,
      {bool indexFiles = true}) async {
    final id = row['sourceId'] as String;
    final type = row['type'] as String;
    final result = <JsonMap>[];
    {
      final path = parent ?? '/';
      final uri = Uri.parse(path);
      if (!path.startsWith('/') ||
          uri.hasAuthority ||
          path.split('/').any((segment) => Uri.decodeComponent(
                  segment.replaceAllMapped(RegExp(r'[^\x00-\x7f]+'),
                      (match) => Uri.encodeComponent(match[0]!)))
              .split('/')
              .contains('..'))) {
        throw const Failure(FailureCode.invalidInput,
            'Use an absolute path within this source.');
      }
      if (type == 'smb') {
        final c = smb.getConnectionByIdOrName(key(id))!;
        for (final f in await smb.listDirectory(c, path, forceRefresh: true)) {
          result.add({
            'id': f.path,
            'name': f.name,
            'kind': f.isShare
                ? 'Share'
                : f.isDirectory
                    ? 'Folder'
                    : 'File',
            'isDirectory': f.isDirectory,
            'size': f.size,
            'metadata': {
              'Path': f.path,
              'Size': f.size,
              'LastModified': f.lastModified?.toUtc().toIso8601String(),
            },
            'path': f.isDirectory
                ? null
                : MediaSourceUtils.buildSmbPath(c.id, f.path)
          });
        }
      } else {
        final c = webdav.getConnectionByIdOrName(key(id))!;
        for (final f
            in await webdav.listDirectory(c, path, forceRefresh: true)) {
          result.add({
            'id': f.path,
            'name': f.name,
            'kind': f.isDirectory ? 'Folder' : 'File',
            'isDirectory': f.isDirectory,
            'size': f.size,
            'metadata': {
              'Path': f.path,
              'Size': f.size,
              'LastModified': f.lastModified?.toUtc().toIso8601String(),
            },
            'path': f.isDirectory
                ? null
                : MediaSourceUtils.buildWebDavPath(c.id, f.path)
          });
        }
      }
    }
    final observedAt = DateTime.now().toUtc().toIso8601String();
    for (final entry in result) {
      entry['provenance'] =
          sourceProvenance(row, entry['id'] as String, observedAt);
      entry['fileId'] = entry['path'] == null || !indexFiles
          ? null
          : await store.ensureRemoteFile(entry['path'] as String, id, {
              'type': type,
              if (entry['serverId'] != null) 'serverId': entry['serverId'],
              'itemId': entry['id'],
              'seriesId': entry['seriesId'],
              'seasonId': entry['seasonId'],
              'number': entry['number'],
              'name': entry['name'],
            });
    }
    if (indexFiles) {
      final records = <JsonMap>[];
      for (final entry in result) {
        if (entry['kind'] == 'File' &&
            (type == 'smb'
                ? !smb.isVideoFile(entry['name'] as String)
                : type == 'webdav' &&
                    !webdav.isVideoFile(entry['name'] as String))) continue;
        final native = sourceCatalogRecords(id, entry);
        records.addAll(native);
        if (native.isNotEmpty) entry['workId'] = native.first['id'];
        final episode = native.where((r) => r['kind'] == 'episode').firstOrNull;
        if (episode != null) entry['episodeId'] = episode['id'];
      }
      if (records.isNotEmpty) await store.observeSourceCatalog(records);
    }
    return result;
  }

  Future<JsonMap> browse(String id, String? parent, {JsonMap? expected}) =>
      serial(() async {
        final row = await source(id);
        if (expected != null && !holdsEndpoint(row, expected)) {
          throw const Failure(FailureCode.conflict,
              'Source changed during synchronization; submit a new sync.');
        }
        final entries = await _browse(row, parent);
        return {'sourceId': id, 'entries': entries, 'total': entries.length};
      });

  Future<JsonMap> query(String id, List<String> itemIds) => serial(() async {
        if (itemIds.isEmpty) {
          throw const Failure(
              FailureCode.invalidInput, 'Supply nonempty itemIds.');
        }
        final row = await source(id);
        final entries = <JsonMap>[];
        final wanted = itemIds.toSet();
        {
          final parents = <String>{};
          for (final item in wanted) {
            final path = item.replaceFirst(RegExp(r'/+$'), '');
            final slash = path.lastIndexOf('/');
            if (!path.startsWith('/') || slash < 0) {
              throw const Failure(FailureCode.invalidInput,
                  'Use directory entry IDs returned by browse.');
            }
            parents.add(path.substring(0, slash + 1));
          }
          for (final parent in parents) {
            entries.addAll((await _browse(row, parent, indexFiles: false))
                .where((entry) => wanted.contains(entry['id'])));
          }
        }
        return {
          'sourceId': id,
          'entries': entries,
          'total': entries.length,
          'missingItemIds': wanted
              .difference(entries.map((entry) => entry['id'] as String).toSet())
              .toList(),
        };
      });

  /// Where a login the person completes is reported: the asking
  /// conversation (`returnTo` in the job input).
  Future<JsonMap?> Function(Invocation)? returnTarget;

  Future<JsonMap> login(JsonMap input, {Invocation? invocation}) async {
    final row = await source(input['sourceId'] as String);
    var method = input['method'] as String? ?? 'auto';
    final password = input['password'] as String?;
    if (password != null) requireUserAuthorization(input);
    if (password != null) method = 'password';
    if (method == 'password' && password == null) {
      throw const Failure(FailureCode.invalidInput,
          'Password mode requires a user-provided password.');
    }
    final jobId = newMediaId('source-login');
    if (method == 'auto') method = 'window';
    if (method == 'window' && requestPassword == null) {
      throw const Failure(FailureCode.unavailable,
          'The NipaPlay login window is not attached.');
    }
    if (password != null) {
      SecretRedactor.remember(
          CredentialRef('media_source_login', jobId), password);
      _passwords[jobId] = password;
    }
    final target = invocation == null || password != null
        ? null
        : await returnTarget?.call(invocation);
    try {
      final job = await engine.submit(
        type: 'media.sources.login',
        jobId: jobId,
        title: SecretRedactor.text('Log in to ${row['name']}'),
        input: {
          'sourceId': row['sourceId'],
          'method': method,
          ...endpointOf(row),
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
          if (target != null) 'returnTo': target
        },
      );
      return {
        'sourceId': row['sourceId'],
        'method': method,
        'jobId': job.jobId,
      };
    } catch (_) {
      _passwords.remove(jobId);
      rethrow;
    }
  }

  Future<void> completeLogin(JobContext context) async {
    final id = context.job.input['sourceId'] as String;
    try {
      await _completeLogin(context);
    } catch (error) {
      await facts.failed(id, failureCode(error));
      rethrow;
    }
    if ((await context.snapshot()).state == JobState.succeeded) {
      await facts.loggedIn(id);
    }
  }

  Future<void> _completeLogin(JobContext context) async {
    await ensureInitialized();
    final input = context.job.input;
    final id = input['sourceId'] as String;
    final ref = CredentialRef('media_source_login', context.job.jobId);
    var stopped = false;
    context.stopRequested.then((_) => stopped = true);
    await context.running(phase: 'awaiting_password');
    if (context.job.checkpoint['authenticated'] == true) {
      await serial(() async {
        await source(id);
      });
      await context.succeed(
          JobReceipt(verification: VerificationLevel.verified, details: {
            'sourceId': id,
            'connected': true,
            'method': input['method']
          }),
          phase: 'connected');
      return;
    }
    Future<JsonMap> unchanged() async {
      final row = await source(id);
      if (!holdsEndpoint(row, input)) {
        throw const Failure(FailureCode.conflict,
            'Source changed during login; start a new login.');
      }
      return row;
    }

    try {
      {
        final row = await unchanged();
        final String? password;
        if (input['method'] == 'password') {
          password = _passwords.remove(context.job.jobId);
          if (password == null) {
            throw const Failure(FailureCode.unavailable,
                'User-provided password was discarded at restart; start a new login.');
          }
        } else {
          final prompt = requestPassword;
          if (prompt == null) {
            throw const Failure(FailureCode.unavailable,
                'Open a new login after the NipaPlay window is attached.');
          }
          password = await prompt(row, context.stopRequested);
          if (password == null && !stopped) {
            await engine.cancel(context.job.jobId);
          }
        }
        if (password != null && !stopped) {
          SecretRedactor.remember(ref, password);
          await serial(() async {
            final current = await unchanged();
            final type = current['type'] as String;
            if (type == 'smb') {
              final c = smb.getConnectionByIdOrName(key(id))!;
              final updated = c.copyWith(
                  password: password, credentialOrigin: c.credentialAuthority);
              if (!await smb.updateConnection(c.name, updated)) {
                throw const Failure(
                    FailureCode.unavailable, 'SMB authentication failed.');
              }
              // Explicitly verify persistence; Classic's UI saving method reports network success.
              await smb
                  .configureConnection(updated.copyWith(isConnected: true));
            } else {
              final c = webdav.getConnectionByIdOrName(key(id))!;
              final updated = c.copyWith(
                  password: password, credentialOrigin: c.credentialAuthority);
              if (!await webdav.upsertConnection(updated)) {
                throw const Failure(
                    FailureCode.unavailable, 'WebDAV authentication failed.');
              }
              await webdav.configureConnection(
                  webdav.getConnectionByIdOrName(key(id))!);
            }
          });
          await context
              .markSideEffectCommitted(checkpoint: {'authenticated': true});
          await context.succeed(
              JobReceipt(verification: VerificationLevel.verified, details: {
                'sourceId': id,
                'connected': true,
                'method': input['method']
              }),
              phase: 'connected');
          return;
        }
        stopped = true;
      }
      if ((await context.snapshot()).cancelRequestedAt != null) {
        await context.cancelled(JobReceipt(
            verification: VerificationLevel.acknowledged,
            details: {'sourceId': id, 'connected': false}));
      }
    } finally {
      _passwords.remove(context.job.jobId);
    }
  }

  Future<void> synchronize(JobContext context) async {
    await ensureInitialized();
    final id = context.job.input['sourceId'] as String;
    final jobId = context.job.jobId;
    await facts.syncStarted(id, jobId);
    try {
      await _synchronize(context);
    } catch (error) {
      await facts.syncFinished(id, jobId,
          result: 'failed', errorCode: failureCode(error));
      rethrow;
    }
    final snapshot = await context.snapshot();
    final receipt = snapshot.receipt?.details;
    await facts.syncFinished(id, jobId,
        result: switch (snapshot.state) {
          JobState.succeeded => 'succeeded',
          JobState.cancelled || JobState.cancelling => 'cancelled',
          JobState.failed => 'failed',
          _ => 'interrupted',
        },
        indexed: receipt?['indexed'] as int?,
        errorCode: snapshot.state == JobState.failed ? 'unknown' : null);
  }

  Future<void> _synchronize(JobContext context) async {
    final id = context.job.input['sourceId'] as String;
    final selected = (context.job.input['libraries'] as List).cast<String>();
    var stopped = false;
    context.stopRequested.then((_) => stopped = true);
    await context.running(phase: 'discover');
    final fileIds = <String>{};
    final seen = <String>{};
    final pending = [...selected];
    while (pending.isNotEmpty && !stopped) {
      final parent = pending.removeAt(0);
      if (!seen.add(parent)) {
        continue;
      }
      final entries =
          (await browse(id, parent, expected: context.job.input))['entries']
              as List<JsonMap>;
      for (final entry in entries) {
        if (entry['fileId'] case final String fileId) fileIds.add(fileId);
        if (entry['isDirectory'] == true) {
          pending.add(entry['id'] as String);
        }
      }
      await context.markSideEffectCommitted();
      await context.report(
          progress: JobProgress(completed: fileIds.length, unit: 'files'));
    }
    final receipt =
        JobReceipt(verification: VerificationLevel.verified, details: {
      'sourceId': id,
      'indexed': fileIds.length,
      'fileIds': fileIds.toList(),
      'libraries': selected,
      'indexedFilesPreserved': true
    });
    if (stopped) {
      if ((await context.snapshot()).cancelRequestedAt != null) {
        await context.cancelled(receipt);
      }
      return;
    }
    await context.succeed(receipt);
  }
}
