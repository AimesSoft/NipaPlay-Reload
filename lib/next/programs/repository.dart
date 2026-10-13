import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import '../capabilities/classic_action.dart';
import 'runtime.dart';

/// A content-addressed bundle, transported in bounded authenticated frames.
/// This receives objects; checkout/merge remains a caller decision.
final class ProgramRepository implements Capability {
  ProgramRepository(this.runtime) {
    actions = [
      ClassicAction(
          const ActionSpec(
              id: 'program.repository.receive',
              title: '接收 harness Git bundle',
              description:
                  'Receive a caller-selected Git bundle in ordered base64 chunks (max 384 KiB decoded each, 64 MiB total). Requires target-host program permission. SHA-256 and offset bind the upload; repeated identical chunks are idempotent. Stored inside target harness records/mesh-bundles; does not checkout, merge or overwrite harness files. No Git remote credentials/config or caller environment are included. nipa sync-repository prepares and uploads a committed revision.',
              effect: Effect.write,
              input: ObjectSchema({
                'sha256': StringSchema(minLength: 64),
                'offset': IntegerSchema(minimum: 0),
                'totalBytes': IntegerSchema(minimum: 1, maximum: 67108864),
                'data': StringSchema(minLength: 1, secret: true),
              }, required: [
                'sha256',
                'offset',
                'totalBytes',
                'data'
              ]),
              output: ObjectSchema({}, additionalProperties: true)),
          receive)
    ];
  }
  final ProgramRuntime runtime;
  @override
  late final List<Action> actions;
  Future<void> _pending = Future.value();
  Future<JsonMap> receive(JsonMap input, Invocation invocation) {
    final result = _pending.then((_) => _receive(input, invocation));
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<JsonMap> _receive(JsonMap input, Invocation invocation) async {
    runtime.requireEnabled();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(input['sha256'] as String) ||
        (input['data'] as String).length > 524288) {
      throw const Failure(
          FailureCode.invalidInput, 'Invalid bundle digest or frame size.');
    }
    await runtime.location.ready;
    final bytes = base64Decode(input['data'] as String);
    final offset = input['offset'] as int, total = input['totalBytes'] as int;
    if (bytes.isEmpty ||
        bytes.length > 393216 ||
        offset + bytes.length > total) {
      throw const Failure(
          FailureCode.invalidInput, 'Invalid bundle chunk size.');
    }
    final caller = sha256.convert(utf8.encode(invocation.origin)).toString();
    final directory =
        await Directory('${runtime.location.path}/records/mesh-bundles/$caller')
            .create(recursive: true);
    final digest = input['sha256'] as String;
    final file = File('${directory.path}/$digest.bundle');
    final partial = File('${file.path}.partial');
    if (await file.exists()) {
      if (await file.length() != total ||
          sha256.convert(await file.readAsBytes()).toString() != digest) {
        throw const Failure(
            FailureCode.conflict, 'Saved bundle content changed.');
      }
      return {
        'complete': true,
        'receivedBytes': total,
        'path': file.path,
        'sha256': digest
      };
    }
    final received = await partial.exists() ? await partial.length() : 0;
    if (offset < received) {
      final reader = await partial.open();
      try {
        await reader.setPosition(offset);
        final old = await reader.read(bytes.length);
        if (old.length != bytes.length ||
            List.generate(bytes.length, (i) => old[i] == bytes[i])
                .contains(false)) {
          throw const Failure(
              FailureCode.conflict, 'Bundle chunk differs from received data.');
        }
      } finally {
        await reader.close();
      }
    } else if (offset == received) {
      await partial.writeAsBytes(bytes, mode: FileMode.append, flush: true);
    } else {
      throw Failure(FailureCode.conflict, 'Expected bundle offset $received.');
    }
    final length = await partial.length();
    if (length == total) {
      if (sha256.convert(await partial.readAsBytes()).toString() != digest) {
        throw const Failure(
            FailureCode.invalidInput, 'Bundle SHA-256 mismatch.');
      }
      await partial.rename(file.path);
      return {
        'complete': true,
        'receivedBytes': length,
        'path': file.path,
        'sha256': digest
      };
    }
    return {'complete': false, 'receivedBytes': length, 'sha256': digest};
  }

  Future<void> drain() => _pending;
}
