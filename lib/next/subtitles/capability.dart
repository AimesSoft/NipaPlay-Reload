import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import '../capabilities/classic_action.dart';
import 'operations.dart';
import 'edit_capability.dart';

const _text = StringSchema(minLength: 1);

final class SubtitleCapability implements Capability {
  SubtitleCapability(SubtitleOperations library)
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'subtitle.tracks',
                  title: '读取文件字幕事实',
                  description:
                      'Read persistent per-file embedded and external subtitle tracks, language, title, format, provenance, availability, probe status and default selection. Omit fileIds to read indexed facts ordered by fileId. Optional limit (1–200) and afterFileId provide keyset pagination; nextAfterFileId is null at the end. Without limit retains the full-result contract. No video probing.',
                  effect: Effect.read,
                  input: ObjectSchema({
                    'fileIds': ArraySchema(_text),
                    'limit': IntegerSchema(minimum: 1, maximum: 200),
                    'afterFileId': _text,
                  }),
                  output: ObjectSchema({}, additionalProperties: true)),
              (input, invocation) async {
            final requested = input['fileIds'] as List?;
            final after = input['afterFileId'] as String?;
            if (requested != null && after != null) {
              throw const Failure(FailureCode.invalidInput,
                  'afterFileId applies only when fileIds is omitted.');
            }
            final limit = input['limit'] as int?;
            if (requested != null && limit != null) {
              throw const Failure(FailureCode.invalidInput,
                  'limit applies only when fileIds is omitted.');
            }
            final ids = requested ??
                (await library.db.query('file_subtitles',
                    where: after == null ? null : 'file_id > ?',
                    whereArgs: after == null ? null : [after],
                    orderBy: 'file_id',
                    limit: limit == null ? null : limit + 1))
                    .map((r) => r['file_id'])
                    .toList();
            final page = limit == null ? ids : ids.take(limit).toList();
            return {
              'files': [for (final id in page) await library.facts(id as String)],
              'nextAfterFileId': requested == null && limit != null && ids.length > limit
                  ? page.last : null,
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
            for (var index = 0; index < entries.length; index++) {
              final entry = entries[index];
              try {
                results.add({'index': index, ...await library.importSubtitle(entry, invocation)});
              } on Failure catch (error) {
                results.add({
                  'fileId': entry['fileId'],
                  'saved': false,
                  'index': index, 'inputTrackRef': entry['filePath'],
                  'error': {...error.toJson(), 'recoveryAction': 'subtitle.tracks'}
                });
              } on FileSystemException {
                results.add({
                  'fileId': entry['fileId'],
                  'saved': false,
                  'index': index, 'inputTrackRef': entry['filePath'],
                  'error': {'code': 'file_unreadable', 'message': 'Cannot read subtitle file.', 'retryable': true, 'recoveryAction': 'subtitle.import'}
                });
              } on FormatException catch (error) {
                results.add({
                  'fileId': entry['fileId'],
                  'saved': false,
                  'index': index, 'inputTrackRef': entry['filePath'],
                  'error': {'code': 'invalid_subtitle', 'message': error.message, 'retryable': false, 'recoveryAction': 'subtitle.import'}
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
          ...SubtitleEditCapability(library).actions,
        ];
  @override
  final List<Action> actions;
}
