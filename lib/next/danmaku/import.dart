import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:xml/xml.dart';

import 'source.dart';

Future<List<DanmakuEntry>> readImportedDanmaku(
        String path, String platform, String videoId) =>
    Isolate.run(() async {
      try {
        final content = (await File(path).readAsString())
            .replaceFirst(RegExp(r'^\uFEFF'), '')
            .trimLeft();
        final rows = <JsonMap>[];
        if (content.startsWith('<')) {
          final document = XmlDocument.parse(content);
          if (document.rootElement.name.local != 'i') {
            throw const FormatException(
                'Expected a Bilibili-standard XML pool with an i root.');
          }
          for (final element in document.findAllElements('d')) {
            final p = (element.getAttribute('p') ?? '').split(',');
            if (p.length < 4) {
              throw const FormatException(
                  'XML comment requires time, mode, font size and color.');
            }
            final seconds = double.parse(p[0]);
            if (!seconds.isFinite || seconds < 0) {
              throw const FormatException(
                  'Comment time must be finite and nonnegative.');
            }
            rows.add({
              'sourceTimeMs': (seconds * 1000).round(),
              'text': element.innerText,
              'mode': int.parse(p[1]),
              'fontSize': int.parse(p[2]),
              'colorRgb': int.parse(p[3]),
              if (p.length > 4) 'sentAt': p[4],
              if (p.length > 6 && p[6] != '0') 'sender': p[6],
              if (p.length > 7 && p[7] != '0') 'platformId': p[7],
            });
          }
        } else {
          final decoded = jsonDecode(content);
          final comments = decoded is Map ? decoded['comments'] : decoded;
          if (comments is! List) {
            throw const FormatException(
                'JSON requires an array or a comments array.');
          }
          for (final comment in comments) {
            if (comment is! Map<String, dynamic>) {
              throw const FormatException('Each comment must be an object.');
            }
            rows.add(comment);
          }
        }
        final entries = <DanmakuEntry>[];
        for (var index = 0; index < rows.length; index++) {
          final row = rows[index];
          if (row['sourceTimeMs'] is! int ||
              (row['sourceTimeMs'] as int) < 0 ||
              row['text'] is! String ||
              row['mode'] is! int ||
              (row['mode'] as int) < 1 ||
              row['colorRgb'] is! int ||
              (row['colorRgb'] as int) < 0 ||
              (row['colorRgb'] as int) > 0xffffff ||
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
      }
    });
