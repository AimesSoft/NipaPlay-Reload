import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import '../capabilities/classic_action.dart';
import 'operations.dart';
import 'storage_lock.dart';

const _text = StringSchema(minLength: 1);

final class SubtitleEditCapability implements Capability {
  SubtitleEditCapability(SubtitleOperations library)
      : actions = [
          for (final operation in ['update', 'remove', 'reset_selection'])
            ClassicAction(
                ActionSpec(
                    id: 'subtitle.$operation',
                    title: '修改字幕事实：$operation',
                    description: operation == 'update'
                        ? 'Batch 1–100 imported tracks; edit language/title/source with file facts expectedRevision. Each item commits independently, returns index and structured error. Persistent and current player facts are updated together.'
                        : operation == 'remove'
                            ? 'Batch 1–100 imported subtitle associations; each item commits independently and returns an indexed result or error (atomic:false). Retains copies on disk and provenance in activity. Selected removed track falls back to automatic choice. Use copy_delete separately to delete unreferenced copies.'
                            : 'Batch 1–100 entries; each item commits independently and returns an indexed result or error (atomic:false). Clear explicit defaults and restore automatic language/Classic selection. Does not disable subtitles. Current player is updated. Headless selection becomes null because it has no Classic language preferences.',
                    effect: Effect.write,
                    input: ObjectSchema({
                      'entries': ArraySchema(ObjectSchema({
                        'fileId': _text,
                        if (operation != 'reset_selection') 'trackId': _text,
                        if (operation != 'reset_selection')
                          'expectedRevision': const IntegerSchema(minimum: 0),
                        if (operation == 'update')
                          'patch': const ObjectSchema({
                            'language': _text,
                            'title': _text,
                            'source': ObjectSchema(
                                {'label': _text, 'url': _text},
                                required: ['label'])
                          }),
                      }, required: [
                        'fileId',
                        if (operation != 'reset_selection') ...[
                          'trackId',
                          'expectedRevision'
                        ],
                        if (operation == 'update') 'patch'
                      ]))
                    }, required: [
                      'entries'
                    ]),
                    output: const ObjectSchema({}, additionalProperties: true)),
                (input, invocation) async {
              final results = <JsonMap>[];
              final entries = (input['entries'] as List).cast<JsonMap>();
              if (entries.isEmpty || entries.length > 100) {
                throw const Failure(FailureCode.invalidInput,
                    'Batch must contain 1 to 100 entries.');
              }
              for (var index = 0; index < entries.length; index++) {
                final e = entries[index];
                try {
                  results.add({
                    'index': index,
                    ...await library.mutateFacts(
                        e['fileId'] as String, operation, e, invocation)
                  });
                } on Failure catch (error) {
                  results.add({
                    'index': index,
                    'fileId': e['fileId'],
                    'trackId': e['trackId'],
                    'error': error.toJson()
                  });
                }
              }
              return {'atomic': false, 'entries': results};
            }),
          ClassicAction(
              const ActionSpec(
                  id: 'subtitle.select_batch',
                  title: '批量记录默认字幕',
                  description:
                      'Apply explicit defaults or disable with null for multiple files. Each item commits independently and updates current playback; returns every result.',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'entries': ArraySchema(ObjectSchema({
                      'fileId': _text,
                      'trackId': StringSchema(nullable: true)
                    }, required: [
                      'fileId',
                      'trackId'
                    ]))
                  }, required: [
                    'entries'
                  ]),
                  output: ObjectSchema({}, additionalProperties: true)),
              (input, _) async {
            final results = <JsonMap>[];
            if ((input['entries'] as List).isEmpty ||
                (input['entries'] as List).length > 100) {
              throw const Failure(FailureCode.invalidInput,
                  'Batch must contain 1 to 100 entries.');
            }
            for (final e in (input['entries'] as List).cast<JsonMap>()) {
              try {
                await library.select(
                    e['fileId'] as String, e['trackId'] as String?);
                results.add(await library.facts(e['fileId'] as String));
              } on Failure catch (error) {
                results.add({'fileId': e['fileId'], 'error': error.toJson()});
              }
            }
            return {'atomic': false, 'entries': results};
          }),
          _DeleteCopies(library),
        ];
  @override
  final List<Action> actions;
}

final class _DeleteCopies extends Action<ClassicActionData, ClassicActionData> {
  const _DeleteCopies(this.library);
  final SubtitleOperations library;
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'subtitle.copy_delete',
      title: '删除未引用字幕副本',
      description:
          'Destructive disk cleanup of explicit managed copy paths only. Returns NeedsDecision with exact paths and SHA-256 fingerprint; confirm:true requires that fingerprint. Refuses any copy referenced by any file track, including VobSub companions and converted WebVTT. Never deletes source files outside managed subtitles directory.',
      effect: Effect.destructive,
      input: ObjectSchema({
        'paths': ArraySchema(_text),
        'confirm': BooleanSchema(),
        'expectedFingerprint': _text
      }, required: [
        'paths'
      ]),
      output: ObjectSchema({}, additionalProperties: true));
  @override
  ClassicActionData decodeInput(JsonMap json) => ClassicActionData(json);
  @override
  Future<Outcome<ClassicActionData>> run(
          ClassicActionData input, Invocation invocation) =>
      withSubtitleStorage(library.root, () => _run(input, invocation));
  Future<Outcome<ClassicActionData>> _run(
      ClassicActionData input, Invocation invocation) async {
    final paths = (input.value['paths'] as List).cast<String>().toSet().toList()
      ..sort();
    if (paths.isEmpty || paths.length > 100) {
      throw const Failure(
          FailureCode.invalidInput, 'Batch must contain 1 to 100 paths.');
    }
    final directory = await Directory('${library.root.path}/subtitles')
        .resolveSymbolicLinks();
    final references = <String>{};
    for (final row in await library.db.query('file_subtitles')) {
      final facts = jsonDecode(row['facts'] as String) as Map;
      for (final t in facts['tracks'] as List) {
        for (final key in ['path', 'playbackPath']) {
          if (t[key] is String) {
            final path = t[key] as String;
            references.add(path);
            if (p.extension(path) == '.idx') {
              references.add(p.setExtension(path, '.sub'));
            }
          }
        }
      }
    }
    final hashes = <JsonMap>[];
    for (final path in paths) {
      if (!p.isWithin(p.join(library.root.absolute.path, 'subtitles'), path) ||
          await FileSystemEntity.isLink(path) ||
          !await File(path).exists()) {
        throw const Failure(FailureCode.invalidInput,
            'Use existing managed subtitle copies, without symlinks.');
      }
      final real = await File(path).resolveSymbolicLinks();
      if (!p.isWithin(directory, real) ||
          references.contains(path) ||
          references.contains(real)) {
        throw const Failure(FailureCode.conflict,
            'Subtitle copy is referenced or outside managed storage.');
      }
      hashes.add({
        'path': path,
        'sha256': sha256.convert(await File(path).readAsBytes()).toString()
      });
    }
    final fingerprint =
        sha256.convert(utf8.encode(jsonEncode(hashes))).toString();
    if (input.value['confirm'] != true) {
      return NeedsDecision(Decision(
          prompt: 'Delete these unreferenced subtitle copies from disk?',
          options: [
            DecisionOption(
                label: 'Delete copies',
                detail: paths.join('\n'),
                call: ActionCall(spec.id, {
                  'paths': paths,
                  'confirm': true,
                  'expectedFingerprint': fingerprint
                }))
          ]));
    }
    if (input.value['expectedFingerprint'] != fingerprint) {
      throw const Failure(
          FailureCode.conflict, 'Subtitle copies changed after preview.');
    }
    for (final path in paths) {
      await File(path).delete();
    }
    return Completed(ClassicActionData({'deleted': paths}));
  }
}
