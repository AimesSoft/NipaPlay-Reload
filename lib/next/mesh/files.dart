import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'runtime.dart';

/// File operations have the permissions of this process. Joining Mesh grants
/// peer access; overwrites and deletion remain explicit destructive decisions.
final class MeshFiles {
  MeshFiles(this.mesh, this.readable, this.localDeviceId);
  final MeshRuntime mesh;
  final Future<JsonMap> Function(String, JsonMap) readable;
  final String localDeviceId;
  final _uploads = <String, JsonMap>{};
  final _decisions = <String, JsonMap>{};
  Future<void> _tail = Future.value();
  String get own => mesh.identity?.deviceId ?? localDeviceId;
  static String absolute(String path) {
    if (!p.isAbsolute(path) || path.contains('\u0000')) {
      throw const Failure(FailureCode.invalidInput,
          'Supply an absolute file path on the target device.');
    }
    return p.normalize(path);
  }

  String _token() =>
      base64Url.encode(List.generate(24, (_) => Random.secure().nextInt(256)));
  Future<String> _signature(String path) async {
    final file = File(path);
    if (!await file.exists()) return 'absent';
    final stat = await file.stat();
    return '${await file.resolveSymbolicLinks()}:${stat.size}:${stat.modified.microsecondsSinceEpoch}:${await sha256.bind(file.openRead()).first}';
  }

  Future<JsonMap> call(String operation, JsonMap input) async {
    final peer = input['deviceId'] as String? ?? own;
    if (operation == 'readable')
      return readable(peer, {'path': absolute(input['path'] as String)});
    return peer == own
        ? request(operation, input, own)
        : mesh.rpc(peer, 'mesh/library/files/$operation', input);
  }

  Future<JsonMap> request(String operation, JsonMap input, String peer) {
    // Serialize mutations, including chunks and confirmation, so two calls
    // cannot truncate or publish the same transfer concurrently.
    final result = _tail.then((_) => _request(operation, input, peer));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  JsonMap _upload(String id, String peer) {
    final value = _uploads[id];
    if (value == null || value['peer'] != peer)
      throw const Failure(FailureCode.notFound, 'Unknown transfer.');
    return value;
  }

  Future<JsonMap> _decision(String peer, List<JsonMap> entries) async {
    final id = _token();
    _decisions[id] = {'peer': peer, 'entries': entries};
    return {
      'decisionId': id,
      'affected': [
        for (final e in entries)
          {'path': e['path'], 'operation': e['operation']}
      ]
    };
  }

  Future<void> _publish(JsonMap upload, {required bool replace}) async {
    final destination = File(upload['path'] as String);
    if (!replace) await destination.create(exclusive: true);
    // On both Windows and POSIX rename publishes a completed file. For a new
    // destination the exclusive create prevents accidental overwrite by a
    // concurrent transfer in this process.
    await File(upload['temporary'] as String).rename(destination.path);
    _uploads.remove(upload['id']);
  }

  Future<JsonMap> _request(String operation, JsonMap input, String peer) async {
    switch (operation) {
      case 'begin':
        final path = absolute(input['path'] as String);
        final parent = await Directory(p.dirname(path)).resolveSymbolicLinks();
        final real = p.join(parent, p.basename(path));
        final size = input['size'];
        if (size is! int || size < 0)
          throw const Failure(
              FailureCode.invalidInput, 'Supply final byte size.');
        final id = _token(),
            temporary = File(p.join(parent, '.nipa-transfer-$id'));
        await temporary.create(exclusive: true);
        _uploads[id] = {
          'id': id,
          'peer': peer,
          'path': real,
          'temporary': temporary.path,
          'size': size,
          'received': 0
        };
        return {'transferId': id, 'chunkBytes': 524288, 'received': 0};
      case 'chunk':
        final upload = _upload(input['transferId'] as String, peer);
        final bytes = base64Decode(input['data'] as String),
            offset = input['offset'];
        if (offset is! int ||
            offset < 0 ||
            bytes.length > 524288 ||
            offset + bytes.length > (upload['size'] as int)) {
          throw const Failure(
              FailureCode.invalidInput, 'Invalid upload chunk.');
        }
        final file = File(upload['temporary'] as String);
        final received = upload['received'] as int;
        if (offset < received && offset + bytes.length <= received) {
          final previous = await file.open();
          try {
            await previous.setPosition(offset);
            if (sha256.convert(await previous.read(bytes.length)) !=
                sha256.convert(bytes)) {
              throw const Failure(FailureCode.conflict, 'Retry bytes differ.');
            }
          } finally {
            await previous.close();
          }
        } else {
          if (offset != received)
            throw const Failure(FailureCode.conflict,
                'Chunk offset differs from received bytes.');
          final output = await file.open(mode: FileMode.append);
          try {
            await output.writeFrom(bytes);
            await output.flush();
          } finally {
            await output.close();
          }
          upload['received'] = offset + bytes.length;
        }
        return {'transferId': upload['id'], 'received': upload['received']};
      case 'finish':
        final upload = _upload(input['transferId'] as String, peer);
        if (upload['received'] != upload['size'])
          throw const Failure(FailureCode.conflict, 'Transfer is incomplete.');
        final digest = (await sha256
                .bind(File(upload['temporary'] as String).openRead())
                .first)
            .toString();
        if (input['sha256'] != null && input['sha256'] != digest)
          throw const Failure(FailureCode.conflict, 'Transfer digest differs.');
        final signature = await _signature(upload['path'] as String);
        if (signature != 'absent')
          return _decision(peer, [
            {
              'operation': 'replace',
              'path': upload['path'],
              'signature': signature,
              'transferId': upload['id']
            }
          ]);
        await _publish(upload, replace: false);
        return {
          'path': upload['path'],
          'size': upload['size'],
          'sha256': digest
        };
      case 'delete':
        final entries = <JsonMap>[];
        for (final path in (input['paths'] as List).cast<String>()) {
          final real = absolute(path), signature = await _signature(real);
          if (signature == 'absent')
            throw const Failure(FailureCode.notFound, 'File does not exist.');
          entries.add(
              {'operation': 'delete', 'path': real, 'signature': signature});
        }
        if (entries.isEmpty)
          throw const Failure(
              FailureCode.invalidInput, 'Supply files to delete.');
        return _decision(peer, entries);
      case 'confirm':
        final id = input['decisionId'] as String, decision = _decisions[id];
        if (decision == null || decision['peer'] != peer)
          throw const Failure(FailureCode.notFound, 'Unknown decision.');
        final entries = (decision['entries'] as List).cast<JsonMap>();
        for (final entry in entries) {
          if (await _signature(entry['path'] as String) != entry['signature'])
            throw const Failure(FailureCode.conflict,
                'File changed after preview; request a new decision.');
          if (entry['operation'] == 'replace')
            _upload(entry['transferId'] as String, peer);
        }
        _decisions.remove(id);
        for (final entry in entries) {
          if (entry['operation'] == 'delete')
            await File(entry['path'] as String).delete();
          else
            await _publish(_upload(entry['transferId'] as String, peer),
                replace: true);
        }
        return {'updated': entries.length};
      case 'cancel':
        final upload = _upload(input['transferId'] as String, peer);
        await File(upload['temporary'] as String).delete();
        _uploads.remove(upload['id']);
        return {'cancelled': true};
      default:
        throw const Failure(
            FailureCode.invalidInput, 'Unknown file operation.');
    }
  }

  Future<void> close() async {
    await _tail;
    for (final upload in _uploads.values)
      await File(upload['temporary'] as String).delete();
    _uploads.clear();
    _decisions.clear();
  }
}

final class MeshFilesCapability implements Capability {
  MeshFilesCapability(MeshFiles files)
      : actions = [
          for (final op in [
            'readable',
            'begin',
            'chunk',
            'finish',
            'delete',
            'confirm',
            'cancel'
          ])
            _FileAction(files, op)
        ];
  @override
  final List<Action> actions;
}

final class _FileAction extends Action<MeshJson, MeshJson> {
  const _FileAction(this.files, this.operation);
  final MeshFiles files;
  final String operation;
  @override
  ActionSpec get spec => ActionSpec(
      id: 'media.mesh_files.$operation',
      title: '设备文件 $operation',
      description:
          'File primitive on this process or deviceId (same-account authenticated Mesh). Any absolute path the target process can access; no library membership required. readable gives local path or receiving-process 127.0.0.1 HTTP Range url over direct mTLS. begin stages size bytes beside path; chunk appends at offset (base64 data, maximum 524288 decoded bytes, identical retries accepted); finish verifies optional sha256 and publishes, returning NeedsDecision for overwrite. delete previews paths and returns NeedsDecision. The NeedsDecision of delete and of an overwriting finish is resolved by the caller itself with confirm: NipaPlay shows the user no confirmation, so do not call confirm before they have agreed. To delete files of a download use download.delete (fileIndices for some of its files), which asks the user in NipaPlay. confirm executes the chosen destructive decision only while files match preview. cancel discards a staged transfer. Existing parents must exist. Transfers/decision IDs last until process exit; cancel unused transfers.',
      effect: operation == 'readable'
          ? Effect.read
          : operation == 'confirm'
              ? Effect.destructive
              : Effect.write,
      input: ObjectSchema({
        'deviceId': const StringSchema(),
        ...switch (operation) {
          'readable' => {
              'entries': const ArraySchema(ObjectSchema({
                'path': StringSchema(minLength: 1),
                'deviceId': StringSchema()
              }, required: [
                'path'
              ]))
            },
          'begin' => {
              'path': const StringSchema(minLength: 1),
              'size': const IntegerSchema(minimum: 0)
            },
          'chunk' => {
              'transferId': const StringSchema(),
              'offset': const IntegerSchema(minimum: 0),
              'data': const StringSchema(secret: true)
            },
          'finish' => {
              'transferId': const StringSchema(),
              'sha256': const StringSchema()
            },
          'delete' => {'paths': const ArraySchema(StringSchema(minLength: 1))},
          'confirm' => {'decisionId': const StringSchema()},
          _ => {'transferId': const StringSchema()},
        }
      },
          required: switch (operation) {
            'readable' => ['entries'],
            'begin' => ['path', 'size'],
            'chunk' => ['transferId', 'offset', 'data'],
            'delete' => ['paths'],
            'confirm' => ['decisionId'],
            _ => ['transferId']
          }),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  MeshJson decodeInput(JsonMap input) => MeshJson(input);
  @override
  Future<Outcome<MeshJson>> run(MeshJson input, Invocation invocation) async {
    if (operation == 'readable') {
      final results = <JsonMap>[];
      for (final entry in (input.json['entries'] as List).cast<JsonMap>()) {
        try {
          results.add(await files.call(operation, {
            ...entry,
            if (entry['deviceId'] == null && input.json['deviceId'] != null)
              'deviceId': input.json['deviceId']
          }));
        } on Failure catch (e) {
          results.add({'path': entry['path'], 'error': e.toJson()});
        }
      }
      return Completed(MeshJson({'entries': results}));
    }
    final result = await files.call(operation, input.json);
    if (result['decisionId'] != null)
      return NeedsDecision(Decision(
          prompt: '确认删除或覆盖这些文件：${jsonEncode(result['affected'])}',
          options: [
            DecisionOption(
                label: '确认',
                call: ActionCall('media.mesh_files.confirm', {
                  'decisionId': result['decisionId'],
                  if (input.json['deviceId'] != null)
                    'deviceId': input.json['deviceId']
                }))
          ]));
    return Completed(MeshJson(result));
  }
}
