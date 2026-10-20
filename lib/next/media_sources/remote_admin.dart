import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'service.dart';

const _text = StringSchema(minLength: 1);
const _output = ObjectSchema({}, additionalProperties: true);
const _folder = ObjectSchema({
  'path': _text,
  'scan': BooleanSchema(),
  'skipPreviouslyMatchedUnwatched': BooleanSchema(),
}, required: [
  'path'
]);
const _remoteConnection = ObjectSchema({
  'type': StringSchema(values: ['webdav', 'smb']),
  'name': _text,
  'url': StringSchema(),
  'wanUrl': StringSchema(),
  'host': StringSchema(),
  'port': IntegerSchema(minimum: 1, maximum: 65535),
  'wanHost': StringSchema(),
  'wanPort': IntegerSchema(minimum: 1, maximum: 65535),
  'username': StringSchema(),
  'domain': StringSchema()
}, required: [
  'type',
  'name'
]);

final class RemoteAdminCapability implements Capability {
  RemoteAdminCapability(MediaSourcesService service)
      : actions = [
          _Operation(
              'media.sources.addresses',
              'List or modify Classic server addresses in one batch. sourceId must be Jellyfin/Emby. Omit operations to list without connecting. Each operation: add(url,name), remove(addressId), switch(addressId), priority(addressId,priority), check(addressId). add verifies server identity. check probes public identity before reusing this profile session, records success/failure and does not switch. Cannot remove the last address; removing the current address first switches to a remaining enabled address. Results are in input order; failure stops the batch after earlier operations have applied.',
              const ObjectSchema({
                'sourceId': _text,
                'operations': ArraySchema(ObjectSchema({
                  'operation': StringSchema(
                      values: ['add', 'remove', 'switch', 'priority', 'check']),
                  'addressId': _text,
                  'url': _text,
                  'name': _text,
                  'priority': IntegerSchema()
                }, required: [
                  'operation'
                ]))
              }, required: [
                'sourceId'
              ]),
              service),
          _Operation(
              'media.sources.remote_admin.status',
              'Refresh the selected NipaPlay peer management state through the Classic provider: folders, saved WebDAV/SMB configurations (LAN url/host/port and WAN wanUrl/wanHost/wanPort, empty when not set) without passwords, scan phase and errors.',
              const ObjectSchema({'sourceId': _text}, required: ['sourceId']),
              service),
          _Operation(
              'media.sources.remote_admin.folders',
              'Manage peer scan roots in bulk. operation add takes folders[{path,scan=true,skipPreviouslyMatchedUnwatched=false}]; scan uses the same fields with scan=true. remove takes paths[]. rescan uses skipPreviouslyMatchedUnwatched=true by default; cleanup removes missing roots. These remove metadata, never disk files. No confirmation. Results are ordered; earlier successful operations remain if a later one fails.',
              const ObjectSchema({
                'sourceId': _text,
                'operation': StringSchema(
                    values: ['add', 'scan', 'remove', 'rescan', 'cleanup']),
                'folders': ArraySchema(_folder),
                'paths': ArraySchema(_text),
                'skipPreviouslyMatchedUnwatched': BooleanSchema()
              }, required: [
                'sourceId',
                'operation'
              ]),
              service),
          _Operation(
              'media.sources.remote_admin.connections',
              'Manage peer WebDAV/SMB connections. operation configure takes connections[{type,name,username,domain; WebDAV url and/or wanUrl; SMB host/port and/or wanHost/wanPort}] with at least one address per connection; a nonempty username opens NipaPlay for user credentials; an empty username configures anonymous access directly. Returns jobId (task.wait/cancel). Existing same-name connections are replaced like Classic after successful testing. Other operations take type and names[]: remove/test. browse/scan take type, name and paths[] (remote directories). browse forces fresh listing; scan uses Classic recognition. Passwords are never accepted or returned.',
              const ObjectSchema({
                'sourceId': _text,
                'operation': StringSchema(
                    values: ['configure', 'remove', 'test', 'browse', 'scan']),
                'connections': ArraySchema(_remoteConnection),
                'type': StringSchema(values: ['webdav', 'smb']),
                'names': ArraySchema(_text),
                'name': _text,
                'paths': ArraySchema(_text)
              }, required: [
                'sourceId',
                'operation'
              ]),
              service)
        ];
  @override
  final List<Action> actions;
}

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Operation extends Action<_Json, _Json> {
  const _Operation(this.id, this.description, this.input, this.service);
  final String id, description;
  final ObjectSchema input;
  final MediaSourcesService service;
  @override
  ActionSpec get spec => ActionSpec(
      id: id,
      title: switch (id) {
        'media.sources.addresses' => '管理服务器地址',
        'media.sources.remote_admin.status' => '查看共享媒体库',
        'media.sources.remote_admin.folders' => '管理共享文件夹',
        _ => '管理共享连接',
      },
      description: description,
      effect: Effect.write,
      input: input,
      output: _output);
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    try {
      await service.ensureInitialized();
      final result = await service.serial(() async {
        final row = await service.source(input.value['sourceId'] as String);
        if (id == 'media.sources.addresses') {
          return addresses(service, row, input.value);
        }
        if (row['type'] != 'nipaplay') {
          throw const Failure(FailureCode.invalidInput,
              'Remote administration requires a NipaPlay source.');
        }
        await service.activate(row);
        if (id.endsWith('.status')) {
          return remoteStatus(service);
        }
        if (id.endsWith('.folders')) {
          return folders(service, input.value);
        }
        return connections(service, row, input.value);
      });
      return Completed(_Json(SecretRedactor.json(result) as JsonMap));
    } on Failure {
      rethrow;
    } catch (e) {
      throw Failure(FailureCode.unavailable, SecretRedactor.text('$e'));
    }
  }
}

String requiredText(JsonMap input, String key) {
  final value = input[key];
  if (value is! String || value.isEmpty) {
    throw Failure(FailureCode.invalidInput, 'Supply $key for this operation.');
  }
  return value;
}

List requiredList(JsonMap input, String key) {
  final value = input[key];
  if (value is! List || value.isEmpty) {
    throw Failure(FailureCode.invalidInput,
        'Supply a nonempty $key list for this operation.');
  }
  return value;
}

Future<JsonMap> addresses(
    MediaSourcesService s, JsonMap row, JsonMap input) async {
  final type = row['type'] as String;
  final server = s.server(type);
  final ops = input['operations'] as List? ?? [];
  if (ops.isEmpty) {
    return {'source': row, 'results': <JsonMap>[]};
  }
  await s.activate(row);
  final results = <JsonMap>[];
  for (final raw in ops) {
    final op = Map<String, Object?>.from(raw as Map);
    final operation = op['operation'];
    if (operation == 'add') {
      if (!await server.addServerAddress(
          s.validateUrl(requiredText(op, 'url')), requiredText(op, 'name'))) {
        throw const Failure(
            FailureCode.unavailable, 'Classic could not add the address.');
      }
    } else {
      final addressId = requiredText(op, 'addressId');
      var profile = server.currentProfile!;
      final matches = profile.addresses.where((a) => a.id == addressId);
      if (matches.isEmpty) {
        throw const Failure(FailureCode.notFound, 'Unknown addressId.');
      }
      final address = matches.single;
      if (operation == 'remove') {
        if (profile.addresses.length == 1) {
          throw const Failure(
              FailureCode.conflict, 'Cannot remove the last address.');
        }
        if (server.currentAddressId == addressId) {
          final alternatives = profile.addresses
              .where((a) => a.id != addressId && a.isEnabled)
              .toList();
          if (alternatives.isEmpty ||
              !await server.switchToAddress(alternatives.first.id)) {
            throw const Failure(FailureCode.unavailable,
                'Cannot switch away from the current address.');
          }
        }
        if (!await server.removeServerAddress(addressId)) {
          throw const Failure(
              FailureCode.unavailable, 'Classic could not remove the address.');
        }
      } else if (operation == 'switch') {
        if (!await server.switchToAddress(addressId)) {
          throw const Failure(FailureCode.unavailable,
              'Classic could not switch to the address.');
        }
      } else if (operation == 'priority') {
        if (op['priority'] is! int) {
          throw const Failure(FailureCode.invalidInput, 'Supply priority.');
        }
        if (!await server.updateServerPriority(
            addressId, op['priority'] as int)) {
          throw const Failure(
              FailureCode.unavailable, 'Classic could not update priority.');
        }
      } else if (operation == 'check') {
        bool connected = false;
        String? error;
        try {
          final identity = await server.identifySource(address.normalizedUrl);
          if (identity != profile.serverId) {
            throw const Failure(
                FailureCode.conflict, 'Address belongs to a different server.');
          }
          connected = await server.probeAddress(address.normalizedUrl);
          if (!connected) {
            error = 'Authenticated probe failed.';
          }
        } catch (e) {
          error = SecretRedactor.text('$e');
        }
        profile = connected
            ? profile.copyWith(addresses: [
                for (final a in profile.addresses)
                  a.id == addressId
                      ? a.copyWith(
                          lastSuccessTime: DateTime.now(), failureCount: 0)
                      : a
              ])
            : profile.markAddressFailed(addressId);
        await s.profiles.updateProfile(profile);
        server.currentProfile = profile;
        results.add({
          'operation': operation,
          'addressId': addressId,
          'connected': connected,
          'error': error
        });
        continue;
      }
    }
    await s.profiles.persistProfiles();
    results.add({'operation': operation, 'applied': true});
  }
  await s.profiles.persistProfiles();
  return {
    'source': await s.source(row['sourceId'] as String),
    'results': results
  };
}

void managementSucceeded(MediaSourcesService s) {
  final error = s.sharing.managementErrorMessage;
  if (error != null) {
    throw Failure(FailureCode.unavailable, SecretRedactor.text(error));
  }
}

Future<JsonMap> remoteStatus(MediaSourcesService s) async {
  final p = s.sharing;
  await p.refreshManagement(userInitiated: true);
  managementSucceeded(s);
  return {
    'sourceId': 'nipaplay:${p.activeHostId}',
    'folders': [
      for (final f in p.scannedFolders)
        {'path': f.path, 'name': f.name, 'exists': f.exists}
    ],
    'webdav': [
      for (final c in p.webdavConnections)
        {
          'name': c.name,
          'url': c.url,
          'wanUrl': c.wanUrl,
          'username': c.username,
          'connected': c.isConnected
        }
    ],
    'smb': [
      for (final c in p.smbConnections)
        {
          'name': c.name,
          'host': c.host,
          'port': c.port,
          'wanHost': c.wanHost,
          'wanPort': c.wanPort,
          'username': c.username,
          'domain': c.domain,
          'connected': c.isConnected
        }
    ],
    'scan': p.scanStatus == null
        ? null
        : {
            'scanning': p.scanStatus!.isScanning,
            'progress': p.scanStatus!.progress,
            'message': p.scanStatus!.message,
            'totalFilesFound': p.scanStatus!.totalFilesFound
          }
  };
}

Future<JsonMap> folders(MediaSourcesService s, JsonMap input) async {
  final p = s.sharing;
  final results = <JsonMap>[];
  switch (input['operation']) {
    case 'add':
    case 'scan':
      for (final raw in requiredList(input, 'folders')) {
        final f = Map<String, Object?>.from(raw as Map);
        final path = requiredText(f, 'path');
        await p.addRemoteFolder(
            folderPath: path,
            scan: input['operation'] == 'scan' || f['scan'] != false,
            skipPreviouslyMatchedUnwatched:
                f['skipPreviouslyMatchedUnwatched'] == true);
        managementSucceeded(s);
        results.add({'path': path, 'applied': true});
      }
    case 'remove':
      for (final path in requiredList(input, 'paths').cast<String>()) {
        await p.removeRemoteFolder(path);
        managementSucceeded(s);
        results.add({'path': path, 'removed': true});
      }
    case 'rescan':
      await p.rescanRemoteAll(
          skipPreviouslyMatchedUnwatched:
              input['skipPreviouslyMatchedUnwatched'] != false);
      managementSucceeded(s);
    case 'cleanup':
      await remoteStatus(s);
      final removed = await p.cleanupMissingRemoteFolders();
      managementSucceeded(s);
      results.add({'removed': removed});
  }
  return {'results': results, 'state': await remoteStatus(s)};
}

Future<JsonMap> connections(
    MediaSourcesService s, JsonMap row, JsonMap input) async {
  final p = s.sharing;
  final op = input['operation'];
  if (op == 'configure') {
    final configs = requiredList(input, 'connections');
    for (final raw in configs) {
      final c = Map<String, Object?>.from(raw as Map);
      if (c['type'] == 'webdav') {
        final urls = [
          for (final field in ['url', 'wanUrl'])
            if ('${c[field] ?? ''}'.trim().isNotEmpty) '${c[field]}'
        ];
        if (urls.isEmpty) {
          throw const Failure(FailureCode.invalidInput,
              'WebDAV requires a url (LAN) or wanUrl (WAN).');
        }
        urls.forEach(s.validateUrl);
      } else {
        final hosts = [
          for (final field in ['host', 'wanHost'])
            if ('${c[field] ?? ''}'.trim().isNotEmpty) '${c[field]}'.trim()
        ];
        if (hosts.isEmpty) {
          throw const Failure(FailureCode.invalidInput,
              'SMB requires a host (LAN) or wanHost (WAN).');
        }
        if (hosts.any((host) => host.contains('/') || host.contains('@'))) {
          throw const Failure(FailureCode.invalidInput,
              'Use an SMB host without credentials or a path.');
        }
      }
    }
    if (s.requestPassword == null) {
      throw const Failure(FailureCode.unavailable,
          'The NipaPlay login window is not attached.');
    }
    final job = await s.engine.submit(
        type: 'media.sources.remote_admin.login',
        title: '连接共享端媒体来源',
        input: {...input, 'url': row['url']});
    return {'jobId': job.jobId};
  }
  final type = requiredText(input, 'type');
  final results = <JsonMap>[];
  if (op == 'remove' || op == 'test') {
    for (final name in requiredList(input, 'names').cast<String>()) {
      if (op == 'remove') {
        if (type == 'webdav') {
          await p.removeWebDAVConnection(name);
        } else {
          await p.removeSMBConnection(name);
        }
        managementSucceeded(s);
        results.add({'name': name, 'removed': true});
      } else {
        final connected = type == 'webdav'
            ? await p.testWebDAVConnection(name: name)
            : await p.testSMBConnection(name);
        results.add({'name': name, 'connected': connected});
      }
    }
  } else {
    final name = requiredText(input, 'name');
    for (final path in requiredList(input, 'paths').cast<String>()) {
      if (op == 'scan') {
        results.add({
          'path': path,
          'counts': type == 'webdav'
              ? await p.scanRemoteWebDAVFolder(name: name, path: path)
              : await p.scanRemoteSMBFolder(name: name, path: path)
        });
      } else if (type == 'webdav') {
        final files = await p.listRemoteWebDAVDirectory(
            name: name, path: path, forceRefresh: true);
        results.add({
          'path': path,
          'entries': [
            for (final f in files)
              {
                'name': f.name,
                'path': f.path,
                'isDirectory': f.isDirectory,
                'size': f.size
              }
          ]
        });
      } else {
        final files = await p.listRemoteSMBDirectory(
            name: name, path: path, forceRefresh: true);
        results.add({
          'path': path,
          'entries': [
            for (final f in files)
              {
                'name': f.name,
                'path': f.path,
                'isDirectory': f.isDirectory,
                'size': f.size
              }
          ]
        });
      }
    }
  }
  return {'results': results};
}

String _optionalUrl(MediaSourcesService s, Object? value) =>
    '${value ?? ''}'.trim().isEmpty ? '' : s.validateUrl('$value');

String _promptAddress(Map<String, Object?> c) {
  for (final field in ['url', 'wanUrl']) {
    if ('${c[field] ?? ''}'.trim().isNotEmpty) return '${c[field]}';
  }
  final wan = '${c['host'] ?? ''}'.trim().isEmpty;
  return wan
      ? 'smb://${c['wanHost']}:${c['wanPort'] ?? 445}'
      : 'smb://${c['host']}:${c['port'] ?? 445}';
}

final class RemoteConnectionExecutor implements JobExecutor {
  const RemoteConnectionExecutor(this.s);
  final MediaSourcesService s;
  @override
  String get type => 'media.sources.remote_admin.login';
  @override
  Future<void> execute(JobContext context) async {
    try {
      await context.running(phase: 'awaiting_password');
      final input = context.job.input;
      final id = input['sourceId'] as String;
      final completed = <String>[];
      for (final raw in input['connections'] as List) {
        final c = Map<String, Object?>.from(raw as Map);
        final prompt = s.requestPassword;
        if (prompt == null) {
          throw const Failure(FailureCode.unavailable,
              'The NipaPlay login window is not attached.');
        }
        final password = (c['username'] as String? ?? '').isEmpty
            ? ''
            : await prompt({
                'name': c['name'],
                'type': c['type'],
                'url': _promptAddress(c),
                'username': c['username'] ?? ''
              }, context.stopRequested);
        if (password == null ||
            (await context.snapshot()).cancelRequestedAt != null) {
          await s.engine.cancel(context.job.jobId);
          await context.cancelled(JobReceipt(
              verification: VerificationLevel.acknowledged,
              details: {'configured': completed}));
          return;
        }
        await s.serial(() async {
          final row = await s.source(id);
          if (row['url'] != input['url']) {
            throw const Failure(
                FailureCode.conflict, 'Peer changed during login.');
          }
          await s.activate(row);
          if (c['type'] == 'webdav') {
            await s.sharing.addWebDAVConnection(WebDAVConnection(
                name: c['name'] as String,
                url: _optionalUrl(s, c['url']),
                wanUrl: _optionalUrl(s, c['wanUrl']),
                username: c['username'] as String? ?? '',
                password: password));
          } else {
            await s.sharing.addSMBConnection(SMBConnection(
                name: c['name'] as String,
                host: (c['host'] as String? ?? '').trim(),
                port: c['port'] as int? ?? 445,
                wanHost: (c['wanHost'] as String? ?? '').trim(),
                wanPort: c['wanPort'] as int? ?? 445,
                username: c['username'] as String? ?? '',
                domain: c['domain'] as String? ?? '',
                password: password));
          }
          managementSucceeded(s);
        });
        completed.add(c['name'] as String);
        await context
            .markSideEffectCommitted(checkpoint: {'configured': completed});
      }
      await context.succeed(JobReceipt(
          verification: VerificationLevel.verified,
          details: {'sourceId': id, 'configured': completed}));
    } on Failure {
      rethrow;
    } catch (e) {
      throw Failure(FailureCode.unavailable, SecretRedactor.text('$e'));
    }
  }

  @override
  Future<void> recover(JobContext context) async {
    throw const Failure(FailureCode.unavailable,
        'Peer connection setup was interrupted; start a new configure call. Earlier configured connections remain.');
  }
}
