import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui_data/service.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('journal-'));
  tearDown(() => root.delete(recursive: true));

  Map<String, Object?>? whole(File file, String origin) {
    Map<String, Object?>? last;
    for (final line in file.readAsLinesSync()) {
      if (line.isEmpty) continue;
      final row = jsonDecode(line) as Map<String, Object?>;
      if (row['event'] == 'chat.turn_boundary' && row['origin'] == origin) {
        last = row;
      }
    }
    return last;
  }

  test('the last boundary of an origin is the one a whole read finds',
      () async {
    final file = File('${root.path}/journal.jsonl');
    final out = StringBuffer();
    for (var i = 0; i < 6000; i++) {
      if (i % 700 == 3) {
        out.writeln(jsonEncode({
          'event': 'chat.turn_boundary',
          'origin': 'harness_cli:chat:${i % 1400 == 3 ? 'a' : 'b'}',
          'turnId': 't$i',
          'phase': i.isEven ? 'started' : 'completed',
        }));
      } else {
        // Invocation records, some mentioning the marker in their input, and
        // multi-byte text that lands across block boundaries.
        out.writeln(jsonEncode({
          'invocationId': 'inv-$i',
          'input': {'note': i % 9 == 0 ? 'chat.turn_boundary 字样' : '弹幕' * (i % 37)},
        }));
      }
    }
    file.writeAsStringSync(out.toString());
    expect(file.lengthSync(), greaterThan(4 * 65536));
    bool boundaryOf(Map<String, Object?> row, String origin) =>
        row['event'] == 'chat.turn_boundary' && row['origin'] == origin;
    for (final origin in ['harness_cli:chat:a', 'harness_cli:chat:b', 'x']) {
      expect(
          await lastJournalRow(
              file, 'chat.turn_boundary', (row) => boundaryOf(row, origin)),
          whole(file, origin));
    }

    // A final line without a newline, and CRLF line ends.
    file.writeAsStringSync(
        '\r\n${jsonEncode({'event': 'chat.turn_boundary', 'origin': 'x', 'turnId': 'crlf'})}\r\n'
        '${jsonEncode({'event': 'chat.turn_boundary', 'origin': 'y', 'turnId': 'last'})}',
        mode: FileMode.append);
    expect(
        (await lastJournalRow(file, 'chat.turn_boundary',
            (row) => boundaryOf(row, 'x')))?['turnId'],
        'crlf');
    expect(
        (await lastJournalRow(file, 'chat.turn_boundary',
            (row) => boundaryOf(row, 'y')))?['turnId'],
        'last');
    expect(
        await lastJournalRow(File('${root.path}/absent.jsonl'),
            'chat.turn_boundary', (row) => true),
        isNull);
  });
}
