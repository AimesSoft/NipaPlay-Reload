import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import '../capabilities/classic_action.dart';
import 'operations.dart';

const _text = StringSchema(minLength: 1);

final class SubtitleCapability implements Capability {
  SubtitleCapability(SubtitleOperations library)
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'subtitle.tracks',
                  title: '读取文件字幕事实',
                  description:
                      'Read persistent per-file embedded and external subtitle tracks, language, title, format, provenance, availability, probe status and default selection. Omit fileIds to read all indexed subtitle facts. No video probing.',
                  effect: Effect.read,
                  input: ObjectSchema({'fileIds': ArraySchema(_text)}),
                  output: ObjectSchema({}, additionalProperties: true)),
              (input, invocation) async {
            final ids = input['fileIds'] as List? ??
                (await library.db.query('file_subtitles'))
                    .map((r) => r['file_id'])
                    .toList();
            return {
              'files': [for (final id in ids) await library.facts(id as String)]
            };
          }),
          ClassicAction(
              const ActionSpec(
                  id: 'subtitle.import',
                  title: '交入并保存字幕',
                  description:
                      'Copy local subtitle files into NipaPlay storage for indexed local fileIds, with declared BCP-47 language and source. Originals can be deleted afterwards; read-only video directories need no writes. Batch entries are saved individually; the reply gives every saved track. Supports ass/ssa/srt/vtt/sub/sup/idx (VobSub pair required). Saved tracks are restored next playback. Use subtitle.select for a persistent explicit default.',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'entries': ArraySchema(ObjectSchema({
                      'fileId': _text,
                      'filePath': _text,
                      'language': _text,
                      'title': _text,
                      'source': ObjectSchema({'label': _text, 'url': _text},
                          required: ['label'])
                    }, required: [
                      'fileId',
                      'filePath',
                      'language',
                      'source'
                    ]))
                  }, required: [
                    'entries'
                  ]),
                  output: ObjectSchema({}, additionalProperties: true)),
              (input, invocation) async {
            final entries = (input['entries'] as List).cast<JsonMap>();
            if (entries.isEmpty) {
              throw const Failure(
                  FailureCode.invalidInput, 'entries must not be empty.');
            }
            final results = <JsonMap>[];
            for (final entry in entries) {
              try {
                results.add(await library.importSubtitle(entry, invocation));
              } on Failure catch (error) {
                results.add({
                  'fileId': entry['fileId'],
                  'saved': false,
                  'error': error.message
                });
              } on FileSystemException catch (error) {
                results.add({
                  'fileId': entry['fileId'],
                  'saved': false,
                  'error': error.message
                });
              } on FormatException catch (error) {
                results.add({
                  'fileId': entry['fileId'],
                  'saved': false,
                  'error': error.message
                });
              }
            }
            return {'entries': results};
          }),
          ClassicAction(
              const ActionSpec(
                  id: 'subtitle.select',
                  title: '记录默认字幕',
                  description:
                      'Persist an explicit subtitle choice for a file, including disable (trackId:null). Applied on the next playback; survives language preference and discovery changes.',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'fileId': _text,
                    'trackId': StringSchema(nullable: true)
                  }, required: [
                    'fileId',
                    'trackId'
                  ]),
                  output: ObjectSchema({}, additionalProperties: true)),
              (input, invocation) async {
            await library.select(
                input['fileId'] as String, input['trackId'] as String?);
            return await library.facts(input['fileId'] as String);
          }),
        ];
  @override
  final List<Action> actions;
}
