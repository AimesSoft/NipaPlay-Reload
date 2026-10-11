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
  'connectionState': StringSchema(values: ['connected', 'unverified']),
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
]);
const _configuration = {
  'name': _text,
  'url': _text,
  'username': StringSchema(),
  'host': _text,
  'port': IntegerSchema(minimum: 1, maximum: 65535),
  'domain': StringSchema(),
};
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
}, required: [
  'id',
  'name',
  'kind',
  'isDirectory',
  'size',
  'path',
  'fileId'
]);

final class MediaSourcesCapability implements Capability {
  MediaSourcesCapability(MediaSourcesService service)
      : actions = [for (final spec in _specs) _SourceAction(spec, service)];
  @override
  final List<Action> actions;
}

final _specs = [
  const ActionSpec(
      id: 'media.sources.check',
      title: 'Check a media source connection',
      description:
          'Perform an authenticated live catalog request through the Classic client for this source and update its last observed connection state. Credential denial or connection failure returns a failure. Listing sources itself never reads secrets or probes the network.',
      effect: Effect.write,
      input: _sourceId,
      output: ObjectSchema({'source': _source, 'checked': BooleanSchema()},
          required: ['source', 'checked'])),
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
          'Add a Classic Jellyfin, Emby, SMB, WebDAV or NipaPlay shared source. HTTP sources require url; SMB requires host and optionally port/domain. Saves address and username; use login separately. NipaPlay sharing uses the existing paired-host client.',
      effect: Effect.write,
      input: ObjectSchema({
        'type': StringSchema(
            values: ['jellyfin', 'emby', 'smb', 'webdav', 'nipaplay']),
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
          'Preview or remove a source connection. Indexed file identities, bindings and playback history remain.',
      effect: Effect.destructive,
      input: ObjectSchema({'sourceId': _text, 'confirm': BooleanSchema()},
          required: ['sourceId']),
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
          'Auto uses Jellyfin Quick Connect when enabled, otherwise opens NipaPlay with address and username prefilled; the user enters only the password. Quick Connect returns code and a jobId; approve elsewhere and use tasks.wait. If the user supplied a password in conversation, pass password (secret, never journaled); it is used only in memory, the saved session goes into the vault. Use window to force a password dialog. Approval expires after ten minutes.',
      effect: Effect.write,
      input: ObjectSchema({
        'sourceId': _text,
        'method': StringSchema(
            values: ['auto', 'quickConnect', 'window', 'password']),
        'password': StringSchema(secret: true)
      }, required: [
        'sourceId'
      ]),
      output: ObjectSchema({
        'sourceId': _text,
        'method': _text,
        'jobId': _text,
        'code': _text,
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
          'Discover a source root or parentId (library/folder/series/season) including never-played items. Returns full list using Classic pagination. recursive is available for Jellyfin/Emby; directory recursion uses sync. Each playable result enters the unified file index with the same Classic path and fileId; titles and server hierarchy remain source facts, no inferred identity or watch history.',
      effect: Effect.write,
      input: ObjectSchema(
          {'sourceId': _text, 'parentId': _text, 'recursive': BooleanSchema()},
          required: ['sourceId']),
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
      id: 'media.sources.sync',
      title: 'Synchronize source discovery',
      description:
          'Submit a cancellable task to recursively discover selected libraries and register all playable files in the unified index. Repeated sync preserves file IDs and bindings; missing items are not deleted. Use tasks.wait for completion.',
      effect: Effect.write,
      input: _sourceId,
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
        case 'media.sources.check':
          result = await service.check(json['sourceId'] as String);
        case 'media.sources.list':
          result = {'sources': await service.list()};
        case 'media.sources.add':
          result = await service.configure(json);
        case 'media.sources.update':
          result = await service.configure(json, update: true);
        case 'media.sources.remove':
          final id = json['sourceId'] as String;
          result = json['confirm'] == true
              ? await service.remove(id)
              : {
                  'sourceId': id,
                  'removed': false,
                  'indexedFilesPreserved': true,
                  'source': await service.source(id)
                };
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
              recursive: json['recursive'] == true);
        case 'media.sources.sync':
          final id = json['sourceId'] as String;
          final source = await service.source(id);
          final selected = await service.selection(id);
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
