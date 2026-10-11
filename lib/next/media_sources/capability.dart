import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/secret_redactor.dart';

import 'service.dart';

const _text = StringSchema(minLength: 1);
const _sourceId = ObjectSchema({'sourceId': _text}, required: ['sourceId']);
const _source = ObjectSchema({
  'sourceId': _text,
  'type': _text,
  'name': _text,
  'url': _text,
  'username': StringSchema(),
  'connected': BooleanSchema(),
  'connectionState':
      StringSchema(values: ['connected', 'unverified', 'failed']),
  'selectedLibraries': ArraySchema(_text),
}, required: [
  'sourceId',
  'type',
  'name',
  'url',
  'username',
  'connected',
  'connectionState',
  'selectedLibraries'
], additionalProperties: true);
const _configuration = {
  'name': _text,
  'url': _text,
  'username': StringSchema(),
  'host': _text,
  'port': IntegerSchema(minimum: 1, maximum: 65535),
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
  'Name': StringSchema(nullable: true),
  'SeriesName': StringSchema(nullable: true),
  'SeasonName': StringSchema(nullable: true),
  'IndexNumber': IntegerSchema(nullable: true),
  'ParentIndexNumber': IntegerSchema(nullable: true),
  'ProductionYear': IntegerSchema(nullable: true),
  'OriginalTitle': StringSchema(nullable: true),
  'Overview': StringSchema(nullable: true),
  'Path': StringSchema(nullable: true),
  'Container': StringSchema(nullable: true),
  'Size': IntegerSchema(nullable: true, description: 'Bytes, as reported.'),
  'LastModified': StringSchema(nullable: true, description: 'UTC ISO 8601.'),
  'RunTimeTicks': IntegerSchema(
      nullable: true, description: 'Server runtime in 100 nanosecond ticks.'),
  'ProviderIds': ObjectSchema({},
      additionalProperties: true,
      nullable: true,
      description: 'IDs of this item only; native provider keys and values.'),
  'MediaSources':
      ArraySchema(ObjectSchema({}, additionalProperties: true), nullable: true),
  'MediaStreams':
      ArraySchema(ObjectSchema({}, additionalProperties: true), nullable: true),
},
    additionalProperties: true,
    description:
        'Facts supplied by provenance server, retaining native keys and values. Missing fields mean the server did not supply them; no parent IDs are inherited or recognition inferred. Playback credential URLs/headers are excluded. Entry path is the Classic locator; metadata.Path is the server file path.');
const _entry = ObjectSchema({
  'id': _text,
  'name': StringSchema(),
  'kind': _text,
  'isDirectory': BooleanSchema(),
  'size': IntegerSchema(nullable: true),
  'path': StringSchema(nullable: true),
  'fileId': StringSchema(nullable: true),
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
      id: 'media.sources.sort',
      title: '设置媒体库排序',
      description:
          'Save a batch of Jellyfin/Emby Classic per-library sorting preferences. sorts[] contains libraryId, sortBy (server field names, comma separated), sortOrder Ascending/Descending. Uses Classic Provider and persistence, applies to subsequent Classic library loads. Empty sorts is invalid. For temporary request ordering use browse sortBy/sortOrder.',
      effect: Effect.write,
      input: ObjectSchema({
        'sourceId': _text,
        'sorts': ArraySchema(ObjectSchema({
          'libraryId': _text,
          'sortBy': _text,
          'sortOrder': StringSchema(values: ['Ascending', 'Descending'])
        }, required: [
          'libraryId',
          'sortBy',
          'sortOrder'
        ]))
      }, required: [
        'sourceId',
        'sorts'
      ]),
      output: ObjectSchema({}, additionalProperties: true)),
  const ActionSpec(
      id: 'media.sources.scrape',
      title: '识别远程媒体',
      description:
          'Submit Classic WebDAV/SMB recursive video recognition from explicit paths[]. Uses Classic remote byte/hash matching, saved credentials and history. Requires the Classic Dandanplay matching account to be logged in. Preserves existing progress and migrates only previously cleared episode progress. Returns jobId; task.wait returns per-directory total/matched/failed counts. Cancellation stops between directories. This writes Classic matching/history; media.sources.sync only discovers files.',
      effect: Effect.write,
      input: ObjectSchema({'sourceId': _text, 'paths': ArraySchema(_text)},
          required: ['sourceId', 'paths']),
      output: ObjectSchema({'jobId': _text}, required: ['jobId'])),
  const ActionSpec(
      id: 'media.sources.play',
      title: '播放远程影片',
      description:
          'Play itemId returned by browse/query in the context of sourceId. Activates that Classic source first. Dandanplay remote and NipaPlay shared items retain Classic episode identity and resume context; credentials remain internal. Optional startPositionMs overrides resume. Returns the Classic player snapshot. Does not open a password prompt; log in first.',
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
          'With sourceId, perform an authenticated live catalog request through Classic and persist success/failure status. With type plus url (or SMB host/port/domain), test temporary configuration without saving it or requesting credentials. Temporary Jellyfin/Emby/Dandanplay tests probe public identity/welcome, WebDAV/SMB use anonymous credentials, NipaPlay uses existing same-origin host credentials if available. No passwords are accepted. Failure to authenticate temporary settings means use add then login. Listing sources itself never probes the network.',
      effect: Effect.write,
      input: ObjectSchema({
        'sourceId': _text,
        'type': StringSchema(values: [
          'jellyfin',
          'emby',
          'smb',
          'webdav',
          'nipaplay',
          'dandanplay_remote'
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
        'serverId': _text,
        'tokenRequired': BooleanSchema(),
        'version': _text
      }, additionalProperties: true)),
  const ActionSpec(
      id: 'media.sources.list',
      title: 'List media sources',
      description:
          'List Classic sources and last observed connection status without reading credentials or contacting servers. Unverified does not mean offline.',
      effect: Effect.read,
      input: ObjectSchema({}),
      output: ObjectSchema({'sources': ArraySchema(_source)},
          required: ['sources'])),
  const ActionSpec(
      id: 'media.sources.add',
      title: 'Configure a media source',
      description:
          'Add a Classic Jellyfin, Emby, SMB, WebDAV, NipaPlay shared or dandanplay_remote source. HTTP sources require url; SMB requires host and optionally port/domain. Saves address and username; use login separately. Classic has one dandanplay_remote source, use update to replace its address. NipaPlay sharing uses the existing paired-host client.',
      effect: Effect.write,
      input: ObjectSchema({
        'type': StringSchema(values: [
          'jellyfin',
          'emby',
          'smb',
          'webdav',
          'nipaplay',
          'dandanplay_remote'
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
          'Update the named source using Classic configuration. Omitted fields and saved password references are retained. Changed server/account requires login. Does not delete indexed files.',
      effect: Effect.write,
      input: ObjectSchema({'sourceId': _text, ..._configuration},
          required: ['sourceId']),
      output: ObjectSchema({'source': _source}, required: ['source'])),
  const ActionSpec(
      id: 'media.sources.remove',
      title: 'Remove a media source',
      description:
          'Remove a Classic source connection immediately, without deleting disk files. Indexed file identities, bindings and playback history remain. No confirmation parameter.',
      effect: Effect.write,
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
          'Auto uses Jellyfin Quick Connect when enabled, otherwise opens NipaPlay with address and username prefilled. Only the user enters the password or dandanplay_remote API token in that window. A quickConnect result contains a code to give the user and jobId for task.wait. Approval expires after ten minutes. No secrets are accepted as tool inputs. An unauthenticated NipaPlay shared source can connect directly.',
      effect: Effect.write,
      input: ObjectSchema({
        'sourceId': _text,
        'method': StringSchema(values: ['auto', 'quickConnect', 'window']),
      }, required: [
        'sourceId'
      ]),
      output: ObjectSchema({
        'sourceId': _text,
        'method': _text,
        'jobId': _text,
        'code': _text,
        'approval': ObjectSchema({
          'code': _text,
          'message': _text,
          'expiresAt': _text,
          'wait': ObjectSchema({
            'action': _text,
            'input': ObjectSchema({'jobId': _text}, required: ['jobId'])
          }, required: [
            'action',
            'input'
          ])
        }, required: [
          'code',
          'message',
          'expiresAt',
          'wait'
        ]),
        'connected': BooleanSchema()
      }, required: [
        'sourceId',
        'method'
      ])),
  const ActionSpec(
      id: 'media.sources.libraries',
      title: 'List available source libraries',
      description:
          'Fetch available libraries, SMB shares, WebDAV root folders, or shared series via Classic clients. Uses only this source credentials. Returns IDs for selection.',
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
          'Replace sync selection with library IDs from libraries. Empty selection stops source sync. Jellyfin/Emby selection uses the Classic service preferences. Does not remove files or change identities.',
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
          'Discover a source root or parentId (library/folder/series/season) including never-played items. Jellyfin/Emby searchTerm is server-side and can span all libraries; use recursive=true for playable results. sortBy (server field names, comma separated) and sortOrder Ascending/Descending control that request. Other source types filter names in the requested directory or series. Dandanplay remote root returns series; parentId is animeId or unmatched. Returns complete metadata and source provenance using Classic pagination. Directory recursion uses sync. Play with media.sources.play {sourceId,itemId}. Each playable result enters the unified file index. No inferred identity or watch history.',
      effect: Effect.write,
      input: ObjectSchema({
        'sourceId': _text,
        'parentId': _text,
        'recursive': BooleanSchema(),
        'searchTerm': _text,
        'sortBy': _text,
        'sortOrder': StringSchema(values: ['Ascending', 'Descending'])
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
          'Fetch live facts for a batch of Jellyfin/Emby item IDs, SMB/WebDAV entry paths, or Dandanplay remote/NipaPlay shared episode IDs returned by browse. Includes metadata, source provenance and shared peer progress; missingItemIds lists IDs not returned by the server. Query series/season IDs explicitly for their ProviderIds; no inheritance or recognition. Does not register files or write bindings; fileId is null.',
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
          'Submit a cancellable task to recursively discover libraries and register playable files in the unified index. Optional parentIds[] starts from explicit library/series IDs or SMB/WebDAV directories; otherwise uses select. Empty selections are invalid. Repeated sync preserves file IDs and bindings; missing items are not deleted. Use task.wait for completion. Recognition is media.sources.scrape.',
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
        case 'media.sources.sort':
          result = await service.sort(json);
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
          result = await service.serial(() async {
            final source = await service.source(json['sourceId'] as String);
            await service.activate(source);
            final play = service.playItem;
            if (play == null) {
              throw const Failure(FailureCode.unavailable,
                  'The NipaPlay player is not attached.');
            }
            return play(source, json['itemId'] as String,
                json['startPositionMs'] as int?);
          });
        case 'media.sources.check':
          result = json['sourceId'] == null
              ? await service.testConfiguration(json)
              : await service.check(json['sourceId'] as String);
        case 'media.sources.list':
          result = {'sources': await service.list()};
        case 'media.sources.add':
          result = await service.configure(json);
        case 'media.sources.update':
          result = await service.configure(json, update: true);
        case 'media.sources.remove':
          result = await service.remove(json['sourceId'] as String);
        case 'media.sources.login':
          result = await service.login(json);
        case 'media.sources.libraries':
          result = await service.libraries(json['sourceId'] as String);
        case 'media.sources.select':
          result = await service.select(json['sourceId'] as String,
              (json['libraries'] as List).cast<String>());
        case 'media.sources.browse':
          result = await service.browse(
              json['sourceId'] as String, json['parentId'] as String?,
              recursive: json['recursive'] == true,
              searchTerm: json['searchTerm'] as String?,
              sortBy: json['sortBy'] as String? ?? 'SortName',
              sortOrder: json['sortOrder'] as String? ?? 'Ascending');
        case 'media.sources.query':
          result = await service.query(json['sourceId'] as String,
              (json['itemIds'] as List).cast<String>());
        case 'media.sources.sync':
          final id = json['sourceId'] as String;
          final source = await service.source(id);
          final selected = json['parentIds'] == null
              ? await service.selection(id)
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
                'url': source['url'],
                'username': source['username']
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
