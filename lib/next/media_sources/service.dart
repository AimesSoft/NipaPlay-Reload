import 'dart:async';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
import 'package:nipaplay/services/multi_address_server_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media/identity_store.dart';
import 'metadata.dart';

/// Source configuration and discovery use the same Classic instances and locators.
final class MediaSourcesService {
  MediaSourcesService(this.store);
  final IdentityStore store;
  final profiles = MultiAddressServerService.instance;
  final smb = SMBService.instance;
  final webdav = WebDAVService.instance;
  SharedRemoteLibraryProvider? shared;
  Future<String?> Function(JsonMap source, Future<void> stopped)?
      requestPassword;
  Future<void> Function(String type, List<String> ids)? updateGuiSelection;
  late TaskEngine _engine;
  TaskEngine get engine => _engine;
  StreamSubscription<Job>? _jobs;
  Future<void> _cleanup = Future.value();
  set engine(TaskEngine value) {
    _engine = value;
    _jobs = value.changes.listen((job) {
      if (job.type != 'media.sources.login' || !job.state.isTerminal) return;
      _passwords.remove(job.jobId);
      if (job.input['method'] == 'quickConnect') {
        final ref = CredentialRef('media_source_login', job.jobId);
        _cleanup = _cleanup
            .then((_) => CredentialStore.instance.vault.delete(ref))
            .catchError((Object error) {
          CredentialStore.instance.report(ref, error);
        });
      }
    });
  }

  Future<void> close() async {
    await _jobs?.cancel();
    await _cleanup;
    await _tail;
    _passwords.clear();
  }

  final Map<String, String> _passwords = {};
  Future<void> _tail = Future.value();
  Future<void>? _ready;
  Future<void> ensureInitialized() => _ready ??= initialize();

  Future<T> serial<T>(Future<T> Function() run) {
    final result = _tail.then((_) => run());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  MediaServerServiceBase server(String type) => switch (type) {
        'jellyfin' => JellyfinService.instance,
        'emby' => EmbyService.instance,
        _ =>
          throw const Failure(FailureCode.invalidInput, 'Not a media server.'),
      };

  Future<void> initialize() async {
    await profiles.initialize();
    await smb.initialize();
    await webdav.initialize();
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

  Future<List<String>> selection(String sourceId) async {
    final prefs = await SharedPreferences.getInstance();
    final type = sourceId.split(':').first;
    if (type == 'jellyfin' || type == 'emby') {
      final service = server(type);
      if (service.currentProfile?.id == key(sourceId)) {
        return service.selectedLibraryIds;
      }
    }
    return prefs.getStringList('next.source.$sourceId.libraries') ?? [];
  }

  Future<List<JsonMap>> list() async {
    final result = <JsonMap>[];
    for (final profile in profiles.profiles) {
      final service = server(profile.serverType);
      result.add({
        'sourceId': '${profile.serverType}:${profile.id}',
        'type': profile.serverType,
        'name': profile.serverName,
        'url': profile.currentAddress!.normalizedUrl,
        'username': profile.username,
        'connected':
            service.currentProfile?.id == profile.id && service.isConnected,
      });
    }
    for (final c in smb.connections) {
      result.add({
        'sourceId': 'smb:${c.id}',
        'type': 'smb',
        'name': c.name,
        'url': 'smb://${c.host}:${c.port}',
        'username': c.username,
        'connected': c.isConnected
      });
    }
    for (final c in webdav.connections) {
      result.add({
        'sourceId': 'webdav:${c.id}',
        'type': 'webdav',
        'name': c.name,
        'url': c.url,
        'username': c.username,
        'connected': c.isConnected
      });
    }
    for (final host in shared?.hosts ?? []) {
      final uri = Uri.parse(host.baseUrl);
      final savedUsername = await shared!.hostUsername(host.id);
      result.add({
        'sourceId': 'nipaplay:${host.id}',
        'type': 'nipaplay',
        'name': host.displayName,
        'url': uri.replace(userInfo: '').toString(),
        'username': savedUsername.isNotEmpty
            ? savedUsername
            : Uri.decodeComponent(uri.userInfo.split(':').first),
        'connected': host.isOnline
      });
    }
    for (final source in result) {
      source['selectedLibraries'] =
          await selection(source['sourceId'] as String);
      source['connectionState'] =
          source['connected'] == true ? 'connected' : 'unverified';
    }
    return result;
  }

  Future<JsonMap> source(String id) async {
    for (final row in await list()) {
      if (row['sourceId'] == id) return row;
    }
    throw Failure(FailureCode.notFound, 'Unknown media source: $id');
  }

  String key(String id) => id.substring(id.indexOf(':') + 1);

  SharedRemoteLibraryProvider get sharing =>
      shared ??
      (throw const Failure(
          FailureCode.unavailable, 'The NipaPlay sharing UI is not attached.'));

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
          final host = input['host'] as String? ?? previous?.host;
          if (host == null ||
              host.trim().isEmpty ||
              host.contains('/') ||
              host.contains('@')) {
            throw const Failure(FailureCode.invalidInput,
                'SMB requires a host without credentials or path.');
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
                  domain: input['domain'] as String?,
                  credentialOrigin:
                      previous.credentialOrigin ?? previous.credentialAuthority,
                  isConnected: false) ??
              SMBConnection(
                  name: name,
                  host: host,
                  port: input['port'] as int? ?? 445,
                  username: username,
                  password: '',
                  domain: input['domain'] as String? ?? '');
          await smb.configureConnection(c);
          id = 'smb:${c.id}';
        } else if (type == 'webdav') {
          final previous = old == null
              ? null
              : webdav.getConnectionByIdOrName(key(old['sourceId'] as String))!;
          final url =
              validateUrl(input['url'] as String? ?? previous?.url ?? '');
          if (webdav.connections
              .any((c) => c.name == name && c.id != previous?.id)) {
            throw const Failure(
                FailureCode.conflict, 'WebDAV source name already exists.');
          }
          final c = previous?.copyWith(
                  name: name,
                  url: url,
                  username: username,
                  credentialOrigin:
                      previous.credentialOrigin ?? previous.credentialAuthority,
                  isConnected: false) ??
              WebDAVConnection(
                  name: name, url: url, username: username, password: '');
          await webdav.configureConnection(c);
          id = 'webdav:${c.id}';
        } else if (type == 'nipaplay') {
          final url = validateUrl(
              input['url'] as String? ?? old?['url'] as String? ?? '');
          if (old == null) {
            final host = await sharing.addHost(displayName: name, baseUrl: url);
            id = 'nipaplay:${host.id}';
            await sharing.configureHostCredentials(host.id, username);
          } else {
            id = old['sourceId'] as String;
            final host = sharing.hosts.firstWhere((h) => h.id == key(id));
            final legacy = Uri.parse(host.baseUrl);
            if (url != old['url'] && legacy.userInfo.isNotEmpty) {
              final separator = legacy.userInfo.indexOf(':');
              await sharing.configureHostCredentials(
                  host.id,
                  Uri.decodeComponent(separator < 0
                      ? legacy.userInfo
                      : legacy.userInfo.substring(0, separator)),
                  password: separator < 0
                      ? ''
                      : Uri.decodeComponent(
                          legacy.userInfo.substring(separator + 1)));
            }
            await sharing.renameHost(key(id), name);
            if (url != old['url']) await sharing.updateHostUrl(key(id), url);
            if (username != old['username']) {
              await sharing.configureHostCredentials(key(id), username);
            }
          }
        } else {
          final service = server(type);
          final url = validateUrl(
              input['url'] as String? ?? old?['url'] as String? ?? '');
          if (old == null) {
            final existing = profiles.findProfile(
                serverType: type, username: username, serverUrl: url);
            if (existing != null) {
              throw const Failure(FailureCode.conflict,
                  'Source already configured; use update.');
            }
            final profile = (await profiles.addProfile(
                serverName: name,
                serverType: type,
                url: url,
                username: username,
                serverId: await service.identifySource(url)))!;
            await profiles.persistProfiles();
            id = '$type:${profile.id}';
          } else {
            id = old['sourceId'] as String;
            final profile = profiles.getProfileById(key(id))!;
            final address = profile.currentAddress!;
            final changed = url != old['url'] || username != old['username'];
            if (changed) {
              final serverId = await service.identifySource(url);
              if (profile.addresses.length > 1 &&
                  serverId != profile.serverId) {
                throw const Failure(FailureCode.conflict,
                    'This profile has multiple addresses; add a separate source for another server.');
              }
              // A changed endpoint/account needs a new login; preserve the old vault entry.
              final replacement = ServerProfile(
                  id: profile.id,
                  serverName: name,
                  serverType: type,
                  username: username,
                  serverId: serverId,
                  addresses: [
                    for (final saved in profile.addresses)
                      saved.id == address.id ? saved.copyWith(url: url) : saved
                  ]);
              await profiles.updateProfile(replacement);
              await profiles.persistProfiles();
              if (service.currentProfile?.id == profile.id) {
                service.isConnected = false;
                service.isReady = false;
                service.accessToken = null;
                service.currentProfile = replacement;
                service.serverUrl = url;
                service.username = username;
              }
            } else {
              final replacement = profile.copyWith(serverName: name);
              await profiles.updateProfile(replacement);
              await profiles.persistProfiles();
              if (service.currentProfile?.id == profile.id) {
                service.currentProfile = replacement;
              }
            }
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
          case 'nipaplay':
            await sharing.removeHostCredentials(key(id));
            await sharing.removeHost(key(id));
          default:
            final service = server(row['type'] as String);
            if (service.currentProfile?.id == key(id)) {
              await service.disconnect();
            } else {
              await profiles.deleteProfile(key(id));
            }
            await profiles.persistProfiles();
        }
        await (await SharedPreferences.getInstance())
            .remove('next.source.$id.libraries');
        return {'sourceId': id, 'removed': true, 'indexedFilesPreserved': true};
      });

  Future<void> activate(JsonMap row) async {
    final type = row['type'] as String;
    final id = row['sourceId'] as String;
    if (type == 'jellyfin' || type == 'emby') {
      final service = server(type);
      if (service.currentProfile?.id != key(id) || !service.isConnected) {
        final selected = await selection(id);
        await service.activateProfile(profiles.getProfileById(key(id))!);
        await applySelection(type, selected);
      }
      if (!service.isConnected) {
        throw const Failure(
            FailureCode.unavailable, 'Login is required for this source.');
      }
    } else if (type == 'nipaplay') {
      if (sharing.activeHostId != key(id)) await sharing.setActiveHost(key(id));
    }
  }

  Future<JsonMap> libraries(String id) => serial(() async {
        final row = await source(id);
        await activate(row);
        final result = <JsonMap>[];
        switch (row['type']) {
          case 'jellyfin':
          case 'emby':
            for (final l
                in await server(row['type'] as String).catalogLibraries()) {
              result.add({
                'id': l['Id'],
                'name': l['Name'],
                'kind': l['CollectionType'] ?? 'mixed'
              });
            }
          case 'nipaplay':
            await sharing.refreshLibrary(userInitiated: true);
            if (!sharing.hasReachableActiveHost) {
              throw const Failure(
                  FailureCode.unavailable, 'Shared library is offline.');
            }
            for (final anime in sharing.animeSummaries) {
              result.add({
                'id': '${anime.animeId}',
                'name': anime.nameCn ?? anime.name,
                'kind': 'series'
              });
            }
          default:
            for (final entry in await _browse(row, '/',
                recursive: false, indexFiles: false)) {
              if (entry['isDirectory'] == true) {
                result.add({
                  'id': entry['id'],
                  'name': entry['name'],
                  'kind': 'folder'
                });
              }
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
      if (row['url'] != target['url'] ||
          row['username'] != target['username']) {
        throw const Failure(FailureCode.conflict,
            'Source changed while selecting libraries; select again.');
      }
      await (await SharedPreferences.getInstance())
          .setStringList('next.source.$id.libraries', ids);
      if (row['type'] == 'jellyfin' || row['type'] == 'emby') {
        await activate(row);
        await applySelection(row['type'] as String, ids);
      }
      return {'sourceId': id, 'selectedLibraries': ids};
    });
  }

  Future<JsonMap> check(String id) async {
    final target = await source(id);
    await libraries(id);
    return serial(() async {
      final row = await source(id);
      if (row['url'] != target['url'] ||
          row['username'] != target['username']) {
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
      return {'source': await source(id), 'checked': true};
    });
  }

  Future<void> applySelection(String type, List<String> ids) =>
      updateGuiSelection?.call(type, ids) ??
      server(type).updateSelectedLibraries(ids);

  Future<List<JsonMap>> _browse(JsonMap row, String? parent,
      {required bool recursive,
      bool indexFiles = true,
      List<String>? itemIds}) async {
    final id = row['sourceId'] as String;
    final type = row['type'] as String;
    final result = <JsonMap>[];
    if (type == 'jellyfin' || type == 'emby') {
      final items = await server(type)
          .browseCatalog(
              parentId: parent,
              recursive: recursive,
              fields: catalogMetadataFields,
              itemIds: itemIds);
      for (final item in items) {
        final folder = item['IsFolder'] == true ||
            {'CollectionFolder', 'Folder', 'Series', 'Season'}
                .contains(item['Type']);
        result.add({
          'id': item['Id'],
          'name': item['Name'],
          'kind': item['Type'],
          'isDirectory': folder,
          'size': null,
          'path': folder ? null : '$type://${item['Id']}',
          'parentId': item['ParentId'],
          'seriesId': item['SeriesId'],
          'seasonId': item['SeasonId'],
          'number': item['IndexNumber'],
          'seasonNumber': item['ParentIndexNumber'],
          'metadata': serverMetadata(item),
        });
      }
    } else if (type == 'nipaplay') {
      if (parent == null) {
        for (final anime in sharing.animeSummaries) {
          result.add({
            'id': '${anime.animeId}',
            'name': anime.nameCn ?? anime.name,
            'kind': 'Series',
            'isDirectory': true,
            'size': null,
            'path': null
          });
        }
      } else if (int.tryParse(parent) == null) {
        for (final entry in await sharing.browseRemoteDirectory(parent)) {
          if (!entry.isDirectory && !sharing.isRemoteFilePlayable(entry)) {
            continue;
          }
          result.add({
            'id': entry.path,
            'name': entry.name,
            'kind': entry.isDirectory ? 'Folder' : 'File',
            'isDirectory': entry.isDirectory,
            'size': entry.size,
            'path': entry.isDirectory
                ? null
                : sharing
                    .buildRemoteFileStreamUri(entry.path)
                    .replace(userInfo: '')
                    .toString()
          });
        }
      } else {
        final animeId = int.parse(parent);
        for (final episode
            in await sharing.loadAnimeEpisodes(animeId, force: true)) {
          result.add({
            'id': episode.shareId,
            'name': episode.title,
            'kind': 'Episode',
            'isDirectory': false,
            'size': episode.fileSize,
            'path':
                sharing.buildStreamUri(episode).replace(userInfo: '').toString()
          });
        }
      }
    } else {
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
              if (type == 'jellyfin' || type == 'emby')
                'serverId': server(type).currentProfile?.serverId,
              'itemId': entry['id'],
              'seriesId': entry['seriesId'],
              'seasonId': entry['seasonId'],
              'number': entry['number'],
              'name': entry['name'],
            });
    }
    return result;
  }

  Future<JsonMap> browse(String id, String? parent,
          {bool recursive = false, JsonMap? expected}) =>
      serial(() async {
        final row = await source(id);
        if (expected != null &&
            (row['url'] != expected['url'] ||
                row['username'] != expected['username'])) {
          throw const Failure(FailureCode.conflict,
              'Source changed during synchronization; submit a new sync.');
        }
        await activate(row);
        if (recursive && row['type'] != 'jellyfin' && row['type'] != 'emby') {
          throw const Failure(FailureCode.invalidInput,
              'Recursive directory discovery uses media.sources.sync.');
        }
        final entries = await _browse(row, parent, recursive: recursive);
        return {'sourceId': id, 'entries': entries, 'total': entries.length};
      });

  Future<JsonMap> query(String id, List<String> itemIds) => serial(() async {
        if (itemIds.isEmpty) {
          throw const Failure(FailureCode.invalidInput,
              'Supply nonempty itemIds.');
        }
        final row = await source(id);
        if (!{'jellyfin', 'emby', 'smb', 'webdav'}.contains(row['type'])) {
          throw const Failure(FailureCode.invalidInput,
              'Item query supports Jellyfin, Emby, SMB and WebDAV sources.');
        }
        await activate(row);
        final entries = <JsonMap>[];
        final wanted = itemIds.toSet();
        if (row['type'] == 'jellyfin' || row['type'] == 'emby') {
          if (itemIds.any((item) => item.contains(','))) {
            throw const Failure(FailureCode.invalidInput,
                'Media server item IDs cannot contain commas.');
          }
          final ids = wanted.toList();
          for (var start = 0; start < ids.length; start += 100) {
            entries.addAll(await _browse(row, null,
                recursive: true,
                indexFiles: false,
                itemIds: ids.sublist(start,
                    start + 100 < ids.length ? start + 100 : ids.length)));
          }
        } else {
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
            entries.addAll((await _browse(row, parent,
                    recursive: false, indexFiles: false))
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

  Future<JsonMap> login(JsonMap input) async {
    final row = await source(input['sourceId'] as String);
    var method = input['method'] as String? ?? 'auto';
    final password = input['password'] as String?;
    if (password != null) method = 'password';
    if (method == 'password' && password == null) {
      throw const Failure(FailureCode.invalidInput,
          'Password mode requires a user-provided password.');
    }
    if (row['type'] == 'nipaplay' &&
        row['username'] == '' &&
        password == null &&
        method == 'auto') {
      await serial(() => sharing.setActiveHost(key(row['sourceId'] as String)));
      return {
        'sourceId': row['sourceId'],
        'method': 'shared',
        'connected': sharing.hasReachableActiveHost
      };
    }
    final jobId = newMediaId('source-login');
    String? code;
    final vault = CredentialStore.instance.vault;
    if (method == 'auto' || method == 'quickConnect') {
      if (row['type'] == 'jellyfin') {
        final enabled = await JellyfinService.instance
            .quickConnectRequest(row['url'] as String, '/QuickConnect/Enabled');
        if (enabled['enabled'] == true) {
          final start = await JellyfinService.instance.quickConnectRequest(
              row['url'] as String, '/QuickConnect/Initiate',
              method: 'POST');
          await CredentialStore.instance.verifiedWrite(
              CredentialRef('media_source_login', jobId),
              start['Secret'] as String);
          code = start['Code'] as String;
          method = 'quickConnect';
        } else if (method == 'quickConnect') {
          throw const Failure(FailureCode.unavailable,
              'Quick Connect is disabled on this server.');
        } else {
          method = 'window';
        }
      } else if (method == 'quickConnect') {
        throw const Failure(
            FailureCode.invalidInput, 'Quick Connect requires Jellyfin.');
      } else {
        method = 'window';
      }
    }
    if (method == 'window' && requestPassword == null) {
      throw const Failure(FailureCode.unavailable,
          'The NipaPlay login window is not attached.');
    }
    if (password != null) {
      SecretRedactor.remember(
          CredentialRef('media_source_login', jobId), password);
      _passwords[jobId] = password;
    }
    try {
      final job = await engine.submit(
          type: 'media.sources.login',
          jobId: jobId,
          title: SecretRedactor.text('Log in to ${row['name']}'),
          input: {
            'sourceId': row['sourceId'],
            'method': method,
            'url': row['url'],
            'username': row['username'],
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 10))
                .toIso8601String()
          },
          details: {
            if (code != null) 'code': code
          });
      return {
        'sourceId': row['sourceId'],
        'method': method,
        'jobId': job.jobId,
        if (code != null) ...{
          'code': code,
          'approval': {
            'code': code,
            'message':
                'Give this code to the user to approve in Jellyfin. Await the approval result with the returned task.',
            'expiresAt': job.input['expiresAt'],
            'wait': {
              'action': 'task.wait',
              'input': {'jobId': job.jobId}
            }
          }
        }
      };
    } catch (_) {
      _passwords.remove(jobId);
      if (code != null) {
        await vault.delete(CredentialRef('media_source_login', jobId));
      }
      rethrow;
    }
  }

  Future<void> completeLogin(JobContext context) async {
    await ensureInitialized();
    final input = context.job.input;
    final id = input['sourceId'] as String;
    final ref = CredentialRef('media_source_login', context.job.jobId);
    final vault = CredentialStore.instance.vault;
    var stopped = false;
    context.stopRequested.then((_) => stopped = true);
    await context.running(
        phase: input['method'] == 'quickConnect'
            ? 'awaiting_approval'
            : 'awaiting_password');
    if (context.job.checkpoint['authenticated'] == true) {
      await serial(() async {
        await activate(await source(id));
      });
      await context.succeed(JobReceipt(
          verification: VerificationLevel.verified,
          details: {
            'sourceId': id,
            'connected': true,
            'method': input['method']
          }), phase: 'connected');
      return;
    }
    Future<JsonMap> unchanged() async {
      final row = await source(id);
      if (row['url'] != input['url'] || row['username'] != input['username']) {
        throw const Failure(FailureCode.conflict,
            'Source changed during login; start a new login.');
      }
      return row;
    }

    try {
      if (input['method'] == 'quickConnect') {
        final secret = await vault.read(ref);
        if (secret == null) {
          throw const Failure(FailureCode.unavailable,
              'Quick Connect expired; start a new login.');
        }
        while (!stopped &&
            DateTime.now()
                .toUtc()
                .isBefore(DateTime.parse(input['expiresAt'] as String))) {
          final row = await unchanged();
          final state = await JellyfinService.instance.quickConnectRequest(
              row['url'] as String,
              '/QuickConnect/Connect?${Uri(queryParameters: {
                    'secret': secret
                  }).query}');
          if (state['Authenticated'] == true) {
            await serial(() async {
              await unchanged();
              final selected = await selection(id);
              final auth = await JellyfinService.instance.quickConnectRequest(
                  row['url'] as String, '/Users/AuthenticateWithQuickConnect',
                  method: 'POST', body: {'Secret': secret});
              final user = auth['User'] as Map;
              await server('jellyfin').acceptSession(
                  profiles.getProfileById(key(id))!,
                  token: auth['AccessToken'] as String,
                  authenticatedUserId: user['Id'] as String,
                  authenticatedUsername: user['Name'] as String,
                  libraryIds: selected);
              await applySelection('jellyfin', selected);
            });
            await context
                .markSideEffectCommitted(checkpoint: {'authenticated': true});
            await context.succeed(JobReceipt(
                verification: VerificationLevel.verified,
                details: {
                  'sourceId': id,
                  'connected': true,
                  'method': input['method']
                }), phase: 'connected');
            return;
          }
          await Future.any([
            Future<void>.delayed(const Duration(seconds: 2)),
            context.stopRequested
          ]);
        }
        if (!stopped) {
          throw const Failure(FailureCode.unavailable,
              'Quick Connect approval timed out; start a new login.');
        }
      } else {
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
            if (type == 'jellyfin' || type == 'emby') {
              final service = server(type);
              final selected = await selection(id);
              await service.authenticateProfile(
                  profiles.getProfileById(key(id))!, password!,
                  libraryIds: selected);
              await applySelection(type, selected);
            } else if (type == 'smb') {
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
            } else if (type == 'nipaplay') {
              await sharing.configureHostCredentials(
                  key(id), current['username'] as String,
                  password: password);
              await sharing.setActiveHost(key(id));
              if (!sharing.hasReachableActiveHost) {
                throw const Failure(FailureCode.unavailable,
                    'NipaPlay shared library authentication failed.');
              }
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
          await context.succeed(JobReceipt(
              verification: VerificationLevel.verified,
              details: {
                'sourceId': id,
                'connected': true,
                'method': input['method']
              }), phase: 'connected');
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
    final selected = (context.job.input['libraries'] as List).cast<String>();
    var stopped = false;
    context.stopRequested.then((_) => stopped = true);
    await context.running(phase: 'discover');
    final fileIds = <String>{};
    final seen = <String>{};
    final pending = [...selected];
    while (pending.isNotEmpty && !stopped) {
      final parent = pending.removeAt(0);
      if (!seen.add(parent)) continue;
      final row = await source(id);
      final recursive = row['type'] == 'jellyfin' || row['type'] == 'emby';
      final entries = (await browse(id, parent,
          recursive: recursive,
          expected: context.job.input))['entries'] as List<JsonMap>;
      for (final entry in entries) {
        if (entry['fileId'] case final String fileId) fileIds.add(fileId);
        if (!recursive && entry['isDirectory'] == true) {
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
