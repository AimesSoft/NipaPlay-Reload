import 'dart:io';
import 'dart:isolate';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/danmaku_parser.dart';
import 'package:nipaplay/utils/danmaku_xml_parse.dart';
import 'package:nipaplay/utils/local_danmaku_bytes.dart';

import 'source.dart';

Future<List<DanmakuEntry>> readImportedDanmaku(
        String path, String platform, String videoId) =>
    Isolate.run(() async {
      try {
        final data = parseLocalDanmakuBytes(await File(path).readAsBytes());
        final comments = data['comments'] as List;
        final rows = parseDanmakuListInBackground(comments);
        if (rows.isNotEmpty) {
          return [
            for (var index = 0; index < rows.length; index++)
              classicDanmakuEntry(rows[index], index, platform, videoId)
          ];
        }
        // Keep the acquisition JSON contract alongside Classic's local formats.
        final normalized = comments.any((row) =>
            row is Map &&
            !row.containsKey('content') &&
            !row.containsKey('c') &&
            (row.containsKey('text') ||
                row.containsKey('mode') ||
                row.containsKey('sourceTimeMs') ||
                row.containsKey('colorRgb')));
        if (!normalized) {
          throw const FormatException('弹幕文件中没有可解析的弹幕数据');
        }
        final entries = <DanmakuEntry>[];
        for (var index = 0; index < comments.length; index++) {
          final row = comments[index];
          if (row is! Map<String, dynamic>) {
            throw FormatException('Comment at index $index must be an object.');
          }
          if (row['sourceTimeMs'] is! int ||
              (row['sourceTimeMs'] as int) < 0 ||
              row['text'] is! String ||
              row['mode'] is! int ||
              (row['mode'] as int) < 1 ||
              row['colorRgb'] is! int ||
              (row['colorRgb'] as int) < 0 ||
              row['fontSize'] != null &&
                  (row['fontSize'] is! int || (row['fontSize'] as int) <= 0) ||
              [
                'platformId',
                'sourceEntryId',
                'originSource',
                'sender',
                'sentAt'
              ].any((key) => row[key] != null && row[key] is! String)) {
            throw FormatException('Invalid comment at index $index.');
          }
          entries.add(DanmakuEntry.fromJson({
            ...row,
            'colorRgb': parseDanmakuColorToInt(row['colorRgb']),
            'sourceId': platform,
            'videoId': videoId,
            'platform': platform,
            'originVideoId': videoId,
          }));
        }
        return entries;
      } on FileSystemException {
        throw const Failure(
            FailureCode.notFound, 'Cannot read the danmaku file.');
      } on FormatException catch (error) {
        throw Failure(FailureCode.invalidInput, error.message.toString());
      } on TypeError catch (error) {
        throw Failure(FailureCode.invalidInput, error.toString());
      }
    });

DanmakuEntry classicDanmakuEntry(
    Map<String, dynamic> row, int index, String sourceId, String videoId,
    {String? platform, String? originVideoId, bool preserveDeclaredOrigin = false}) {
  final seconds = row['time'] as num;
  if (!seconds.isFinite) {
    throw FormatException('Comment time at index $index must be finite.');
  }
  final type = row['type'];
  final mode = row['originalType'] ?? row['originalMode'] ?? type;
  return DanmakuEntry(
    sourceId: sourceId,
    videoId: videoId,
    platform: platform ?? sourceId,
    originVideoId: preserveDeclaredOrigin ? originVideoId : videoId,
    sourceTimeMs: (seconds * 1000).round(),
    text: row['content'] as String,
    mode: mode is int
        ? mode
        : type == 'top'
            ? 5
            : type == 'bottom'
                ? 4
                : 1,
    colorRgb: parseDanmakuColorToInt(row['color']),
    platformId: row['platformDanmakuId']?.toString(),
    sourceEntryId: row['sourceEntryId']?.toString(),
    originSource: row['originSource']?.toString(),
    sender: row['senderId'] as String?,
    fontSize: int.tryParse(row['fontSize']?.toString() ?? ''),
    sentAt: (row['sentAt'] ?? row['timestamp'])?.toString(),
  );
}
