import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/secret_redactor.dart';

import 'service.dart';
import '../capabilities/user_authorization.dart';

const _text = StringSchema(minLength: 1);
const _sourceId = ObjectSchema({'sourceId': _text}, required: ['sourceId']);
const _source = ObjectSchema({
  'sourceId': _text,
  'type': _text,
  'name': _text,
  'url': StringSchema(
      description:
          'LAN address (WebDAV url, SMB smb://host:port); empty when only a WAN address is configured. '),
  'wanUrl': StringSchema(
      description:
          'WebDAV/SMB WAN address; empty when none is configured. Absent on other types.'),
  'address': _text,
  'host': StringSchema(),
  'port': IntegerSchema(minimum: 1, maximum: 65535),
  'wanHost': StringSchema(),
  'wanPort': IntegerSchema(minimum: 1, maximum: 65535),
  'username': StringSchema(),
  'connected': BooleanSchema(),
  'connectionState':
      StringSchema(values: ['connected', 'unverified', 'failed']),
  'selectedLibraries': ArraySchema(_text),
  'addresses': ArraySchema(
      ObjectSchema({
        'role': StringSchema(description: 'lan or wan for SMB and WebDAV; '),
        'label': StringSchema(description: 'Address name, when it has one.'),
        'address': StringSchema(),
        'enabled': BooleanSchema(),
        'reachability': StringSchema(
            values: ['reachable', 'unreachable', 'unknown'],
            description:
                'Result of the last attempt on this address; unknown when none was observed.'),
        'lastAttemptAt': StringSchema(nullable: true),
        'lastSuccessAt': StringSchema(nullable: true),
        'lastFailureAt': StringSchema(nullable: true),
        'errorCode': StringSchema(nullable: true),
        'latencyMs': IntegerSchema(nullable: true),
      }, additionalProperties: true),
      description:
          'Every configured address with the last attempt on it. Observed facts, kept across restarts.'),
  'lastCheck': ObjectSchema({}, additionalProperties: true, nullable: true),
  'sync': ObjectSchema({}, additionalProperties: true),
  'lastError': ObjectSchema({}, additionalProperties: true, nullable: true),
  'credential': ObjectSchema({}, additionalProperties: true),
}, required: [
  'sourceId',
  'type',
  'name',
  'url',
  'address',
  'username',
  'connected',
  'connectionState',
  'selectedLibraries'
], additionalProperties: true);
const _configuration = {
  'name': _text,
  'url': StringSchema(),
  'wanUrl': StringSchema(),
  'username': StringSchema(),
  'host': StringSchema(),
  'port': IntegerSchema(minimum: 1, maximum: 65535),
  'wanHost': StringSchema(),
  'wanPort': IntegerSchema(minimum: 1, maximum: 65535),
  'domain': StringSchema(),
};
const _provenance = ObjectSchema({
  'sourceId': _text,
  'type': _text,
  'name': StringSchema(),
  'url': _text,
  'itemId': _text,
  'observedAt': _text,
}, required: [
  'sourceId',
  'type',
  'name',
  'url',
  'itemId',
  'observedAt'
]);
const _metadata = ObjectSchema({
  'Path': StringSchema(nullable: true),
  'Size': IntegerSchema(nullable: true),
  'LastModified': StringSchema(nullable: true),
}, additionalProperties: true, description: 'Observed file facts.');
const _entry = ObjectSchema({
  'id': _text,
  'name': StringSchema(),
  'kind': _text,
  'isDirectory': BooleanSchema(),
  'size': IntegerSchema(nullable: true),
  'path': StringSchema(nullable: true),
  'fileId': StringSchema(nullable: true),
  'workId': StringSchema(nullable: true),
  'episodeId': StringSchema(nullable: true),
  'serverId': StringSchema(nullable: true),
  'parentId': StringSchema(nullable: true),
  'seriesId': StringSchema(nullable: true),
  'seasonId': StringSchema(nullable: true),
  'number': IntegerSchema(nullable: true),
  'seasonNumber': IntegerSchema(nullable: true),
  'provenance': _provenance,
  'metadata': _metadata,
}, required: [
  'id',
  'name',
  'kind',
  'isDirectory',
  'size',
  'path',
  'fileId',
  'provenance',
]);

final class MediaSourcesCapability implements Capability {
  MediaSourcesCapability(MediaSourcesService service)
      : actions = [for (final spec in _specs) _SourceAction(spec, service)];
  @override
  final List<Action> actions;
}

final _specs = [
  const ActionSpec(
      id: 'media.sources.search',
      title: '只读搜索媒体来源',
      description:
          'Search previously indexed SMB/WebDAV file names and paths. Results are independently reported per source with basis=indexed. Never browse, enumerate or register files. limit bounds each source; omitted sourceIds selects configured sources.',
      effect: Effect.read,
      input: ObjectSchema({
        'query': _text,
        'sourceIds': ArraySchema(_text),
        'limit': IntegerSchema(minimum: 1, maximum: 100),
      }, required: [
        'query'
      ]),
      output: ObjectSchema({
        'sources': ArraySchema(ObjectSchema({}, additionalProperties: true))
      }, required: [
        'sources'
      ])),
  const ActionSpec(
      id: 'media.sources.scrape',
      title: '识别远程媒体',
      description:
          'Submit Classic WebDAV/SMB recursive video recognition from explicit paths[]. Uses Classic remote byte/hash matching, saved credentials and history. Requires the Classic Dandanplay matching account to be logged in. Preserves existing progress and migrates only previously cleared episode progress. Returns jobId; task.wait returns per-directory total/matched/failed counts. Cancellation stops between directories. This writes Classic matching/history; media.sources.sync discovers files and persists source-native catalogue metadata without Classic matching.',
      effect: Effect.write,
      input: ObjectSchema({'sourceId': _text, 'paths': ArraySchema(_text)},
          required: ['sourceId', 'paths']),
      output: ObjectSchema({'jobId': _text}, required: ['jobId'])),
  const ActionSpec(
      id: 'media.sources.play',
      title: '播放远程影片',
      description:
          'Play a discovered SMB/WebDAV itemId in sourceId using the Next player. Optional startPositionMs overrides resume. Credentials stay internal; log in first.',
      effect: Effect.write,
      input: ObjectSchema({
        'sourceId': _text,
        'itemId': _text,
        'startPositionMs': IntegerSchema(minimum: 0)
      }, required: [
        'sourceId',
        'itemId'
      ]),
      output: ObjectSchema({}, additionalProperties: true)),
  const ActionSpec(
      id: 'media.sources.check',
      title: 'Check a media source connection',
      description:
          'Check a configured SMB/WebDAV source, or test temporary configuration with anonymous credentials. Does not save temporary settings. Listing itself never probes the network.',
      effect: Effect.write,
      input: ObjectSchema({
        'sourceId': _text,
        'type': StringSchema(values: [
          'smb',
          'webdav',
        ]),
        ..._configuration
      }, oneOfRequired: [
        ['sourceId'],
        ['type']
      ]),
      output: ObjectSchema({
        'source': _source,
        'checked': BooleanSchema(),
        'connected': BooleanSchema(),
        'authenticated': BooleanSchema(),
      }, additionalProperties: true)),
  const ActionSpec(
      id: 'media.sources.list',
      title: 'List media sources',
      description:
          'List Classic sources and last observed connection status without reading credentials or contacting servers. Unverified does not mean offline. Besides the current fields each source carries observed facts that survive a restart, each with the time it was observed and null where nothing was: addresses[] (every configured address with role, reachability reachable/unreachable/unknown, lastAttemptAt, lastSuccessAt, lastFailureAt, errorCode, latencyMs; Classic probes SMB/WebDAV addresses at startup and when connections are tested, observations remain until refreshed); lastCheck {at, result, errorCode, latencyMs} of the last media.sources.check; sync {result running/succeeded/failed/cancelled/interrupted or null, jobId, startedAt, finishedAt, lastSuccessAt, indexed, errorCode}; lastError {code, at, message}; credential {state none (needs no login)/saved (a login is on record; the vault is not read, so an entry that has gone shows as credential_missing when used)/missing/rejected, lastRejectedAt, lastRejectedCode, lastVerifiedAt}, which never holds the credential. rejected means the source refused the saved login after the last time it accepted it. errorCode is a stable code such as timeout, connection_refused, dns_failed, network_unreachable, tls_failed, auth_failed, login_required, credential_missing, http_<status>, connection_failed. address is the address in use now. WebDAV and SMB can have a LAN and a WAN address: WebDAV url (LAN) and wanUrl (WAN); SMB host/port and wanHost/wanPort, also given as smb:// url and wanUrl. At least one is non-empty; an empty one is not configured. Classic prefers LAN when both are set, so address can change between LAN and WAN without any edit.',
      effect: Effect.read,
      input: ObjectSchema({}),
      output: ObjectSchema({'sources': ArraySchema(_source)},
          required: ['sources'])),
  const ActionSpec(
      id: 'media.sources.add',
      title: 'Configure a media source',
      description:
          'Configure an SMB or WebDAV source. Save addresses and username; use login separately. WebDAV accepts url and wanUrl; SMB accepts host/port and wanHost/wanPort, plus domain. At least one address is required.',
      effect: Effect.write,
      input: ObjectSchema({
        'type': StringSchema(values: [
          'smb',
          'webdav',
        ]),
        ..._configuration
      }, required: [
        'type',
        'name'
      ]),
      output: ObjectSchema({'source': _source}, required: ['source'])),
  const ActionSpec(
      id: 'media.sources.update',
      title: 'Update a media source',
      description:
          'Update the named source using Classic configuration. Omitted fields, including the other of the LAN/WAN addresses, and saved password references are retained; an empty string clears the WebDAV url/wanUrl or SMB host/wanHost, and at least one address must remain. A saved password is bound to the addresses it was saved for: removing an address or switching between them keeps it, while a new or different address, or another account, requires login. Does not delete indexed files.',
      effect: Effect.write,
      input: ObjectSchema({'sourceId': _text, ..._configuration},
          required: ['sourceId']),
      output: ObjectSchema({'source': _source}, required: ['source'])),
  const ActionSpec(
      id: 'media.sources.remove',
      title: 'Remove a media source',
      description:
          'Remove a source connection without confirmation. Indexed file identities, bindings and playback history remain; no disk files are deleted.',
      effect: Effect.destructive,
      input: ObjectSchema({'sourceId': _text}, required: ['sourceId']),
      output: ObjectSchema({
        'sourceId': _text,
        'removed': BooleanSchema(),
        'indexedFilesPreserved': BooleanSchema(),
        'source': _source
      }, required: [
        'sourceId',
        'removed',
        'indexedFilesPreserved'
      ])),
  const ActionSpec(
      id: 'media.sources.login',
      title: 'Initiate media source login',
      description:
          'Authenticate an SMB/WebDAV source. With explicit userAuthorization, supply a user-provided password. Without a password, auto opens the login window. Secrets stay out of task inputs and receipts. User-completed outcomes return to the asking conversation. Login expires after ten minutes.',
      effect: Effect.write,
      input: ObjectSchema({
        'sourceId': _text,
        'method': StringSchema(values: ['auto', 'window', 'password']),
        'password': StringSchema(secret: true),
        'userAuthorization': userAuthorizationSchema,
      }, required: [
        'sourceId'
      ]),
      output: ObjectSchema({
        'sourceId': _text,
        'method': _text,
        'jobId': _text,
        'connected': BooleanSchema()
      }, required: [
        'sourceId',
        'method'
      ])),
  const ActionSpec(
      id: 'media.sources.libraries',
      title: 'List available source libraries',
      description:
          'List SMB shares or WebDAV root folders using this source credentials. Returns IDs for selection.',
      effect: Effect.read,
      input: _sourceId,
      output: ObjectSchema({
        'sourceId': _text,
        'libraries': ArraySchema(ObjectSchema(
            {'id': _text, 'name': StringSchema(), 'kind': _text},
            required: ['id', 'name', 'kind'])),
        'selectedLibraries': ArraySchema(_text)
      }, required: [
        'sourceId',
        'libraries',
        'selectedLibraries'
      ])),
  const ActionSpec(
      id: 'media.sources.select',
      title: 'Select source libraries',
      description:
          'Replace sync selection with folder IDs returned by libraries. Empty selection uses the source root. Does not remove files or change identities.',
      effect: Effect.write,
      input: ObjectSchema({'sourceId': _text, 'libraries': ArraySchema(_text)},
          required: ['sourceId', 'libraries']),
      output: ObjectSchema(
          {'sourceId': _text, 'selectedLibraries': ArraySchema(_text)},
          required: ['sourceId', 'selectedLibraries'])),
  const ActionSpec(
      id: 'media.sources.browse',
      title: 'Browse remote content',
      description:
          'Browse an SMB/WebDAV root or parent folder and register discovered files and source-native catalogue facts. Recursion uses media.sources.sync. Metadata contains file facts; matching is explicit. Existing assignments and edits are preserved.',
      effect: Effect.write,
      input: ObjectSchema({
        'sourceId': _text,
        'parentId': _text,
      }, required: [
        'sourceId'
      ]),
      output: ObjectSchema({
        'sourceId': _text,
        'entries': ArraySchema(_entry),
        'total': IntegerSchema(minimum: 0)
      }, required: [
        'sourceId',
        'entries',
        'total'
      ])),
  const ActionSpec(
      id: 'media.sources.query',
      title: 'Query remote item metadata',
      description:
          'Read live SMB/WebDAV file facts for entry paths returned by browse. Does not register files or write bindings. missingItemIds reports entries absent from the response.',
      effect: Effect.read,
      input: ObjectSchema({'sourceId': _text, 'itemIds': ArraySchema(_text)},
          required: ['sourceId', 'itemIds']),
      output: ObjectSchema({
        'sourceId': _text,
        'entries': ArraySchema(_entry),
        'total': IntegerSchema(minimum: 0),
        'missingItemIds': ArraySchema(_text),
      }, required: [
        'sourceId',
        'entries',
        'total',
        'missingItemIds'
      ])),
  const ActionSpec(
      id: 'media.sources.sync',
      title: 'Synchronize source discovery',
      description:
          'Submit a cancellable task to discover SMB/WebDAV directories, register files and persist source-native facts. Optional parentIds narrows discovery; otherwise use selected folders or the root. Existing assignments and edits survive refresh. Missing files are not deleted.',
      effect: Effect.write,
      input: ObjectSchema({'sourceId': _text, 'parentIds': ArraySchema(_text)},
          required: ['sourceId']),
      output: ObjectSchema({'sourceId': _text, 'jobId': _text},
          required: ['sourceId', 'jobId'])),
];

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _SourceAction extends Action<_Json, _Json> {
  const _SourceAction(this.spec, this.service);
  @override
  final ActionSpec spec;
  final MediaSourcesService service;
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final json = input.value;
    try {
      await service.ensureInitialized();
      final JsonMap result;
      switch (spec.id) {
        case 'media.sources.search':
          result = await service.search(json['query'] as String,
              sourceIds: (json['sourceIds'] as List?)?.cast<String>(),
              limit: json['limit'] as int? ?? 12);
        case 'media.sources.scrape':
          final row = await service.source(json['sourceId'] as String);
          if (!{'webdav', 'smb'}.contains(row['type']) ||
              (json['paths'] as List).isEmpty) {
            throw const Failure(FailureCode.invalidInput,
                'Choose a WebDAV/SMB source and nonempty paths.');
          }
          final job = await service.engine.submit(
              type: 'media.sources.scrape', title: '识别远程媒体', input: json);
          result = {'jobId': job.jobId};
        case 'media.sources.play':
          result = await service.play(
              json['sourceId'] as String, json['itemId'] as String,
              startPositionMs: json['startPositionMs'] as int?);
        case 'media.sources.check':
          result = json['sourceId'] == null
              ? await service.testConfiguration(json)
              : await service.check(json['sourceId'] as String);
        case 'media.sources.list':
          result = {'sources': await service.list(withFacts: true)};
        case 'media.sources.add':
          result = await service.configure(json);
        case 'media.sources.update':
          result = await service.configure(json, update: true);
        case 'media.sources.remove':
          result = await service.remove(json['sourceId'] as String);
        case 'media.sources.login':
          result = await service.login(json, invocation: invocation);
        case 'media.sources.libraries':
          result = await service.libraries(json['sourceId'] as String);
        case 'media.sources.select':
          result = await service.select(json['sourceId'] as String,
              (json['libraries'] as List).cast<String>());
        case 'media.sources.browse':
          result = await service.browse(
            json['sourceId'] as String,
            json['parentId'] as String?,
          );
        case 'media.sources.query':
          result = await service.query(json['sourceId'] as String,
              (json['itemIds'] as List).cast<String>());
        case 'media.sources.sync':
          final id = json['sourceId'] as String;
          final source = await service.source(id);
          final selected = json['parentIds'] == null
              ? await service.syncRoots(id)
              : (json['parentIds'] as List).cast<String>();
          if (selected.isEmpty) {
            throw const Failure(FailureCode.invalidInput,
                'Select libraries before synchronizing.');
          }
          final job = await service.engine.submit(
              type: 'media.sources.sync',
              title: 'Discover selected media libraries',
              input: {
                'sourceId': id,
                'libraries': selected,
                ...service.endpointOf(source)
              });
          result = {'sourceId': id, 'jobId': job.jobId};
        default:
          throw StateError(spec.id);
      }
      return Completed(_Json(_public(result) as JsonMap));
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureCode.unavailable, SecretRedactor.text('$error'));
    }
  }
}

Object? _public(Object? value) {
  if (value is String) return SecretRedactor.text(value);
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _public(entry.value)
    };
  }
  if (value is List) return [for (final entry in value) _public(entry)];
  return value;
}

List<JobExecutor> mediaSourcesExecutors(MediaSourcesService service) => [
      _Executor('media.sources.login', service.completeLogin),
      _Executor('media.sources.sync', service.synchronize),
      _Executor('media.sources.scrape', service.scrape),
    ];

final class _Executor implements JobExecutor {
  const _Executor(this.type, this.run);
  @override
  final String type;
  final Future<void> Function(JobContext) run;
  @override
  Future<void> execute(JobContext context) async {
    try {
      await run(context);
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureCode.unavailable, SecretRedactor.text('$error'));
    }
  }

  @override
  Future<void> recover(JobContext context) => execute(context);
}
