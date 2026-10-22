import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/chat/chat_line_reader.dart';
import 'package:nipaplay/next/harness_redaction.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/secret_redactor.dart';

/// Writes [text] in pieces of [size] bytes, cutting lines and characters.
Stream<List<int>> _pieces(String text, int size) async* {
  final bytes = utf8.encode(text);
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('lines arrive whole, in order, decoded exactly and redacted', () async {
    const known = 'remembered-before-start-0123456789';
    SecretRedactor.remember(const CredentialRef('test', 'before'), known);
    final messages = [
      for (var i = 0; i < 300; i++)
        {
          'id': i,
          'method': i.isEven ? 'item/completed' : 'item/agentMessage/delta',
          'params': {
            'threadId': 't',
            'delta': '第 $i 段 password=hunter$i',
            'item': {'aggregatedOutput': '输出 $i $known token=abc$i'}
          }
        }
    ];
    final text = '${messages.map(jsonEncode).join('\n')}\n';
    final reader = ChatLineReader.start(_pieces(text, 7),
        rpc: true, streamDeltaMethods: {'item/agentMessage/delta'});
    final lines = await reader.lines.toList();
    expect(lines, hasLength(300));
    for (var i = 0; i < 300; i++) {
      final line = lines[i];
      expect(line.error, isNull);
      expect(line.text, jsonEncode(messages[i]));
      expect(line.decoded, messages[i]);
      final expected = redactHarnessJson(i.isEven
          ? messages[i]
          : {
              ...messages[i],
              'params': {...messages[i]['params'] as Map, 'delta': ''}
            });
      expect(line.redacted, expected);
      expect(jsonEncode(line.redacted), isNot(contains(known)));
      expect(jsonEncode(line.redacted), isNot(contains('hunter')));
    }
    await reader.close();
  });

  test('a value remembered while reading is redacted from later output',
      () async {
    final output = StreamController<List<int>>();
    final reader = ChatLineReader.start(output.stream, rpc: false);
    final received = <ChatLine>[];
    final done = reader.lines.forEach(received.add);
    output.add(utf8.encode('first line\n'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    const later = 'remembered-while-reading-9876543210';
    SecretRedactor.remember(const CredentialRef('test', 'later'), later);
    output.add(utf8.encode('it is $later now\n'));
    await output.close();
    await done;
    expect(received.map((l) => l.text), ['first line', 'it is $later now']);
    expect(received.last.redactedText, isNot(contains(later)));
    expect(received.last.redactedText, contains('CredentialRef(test, later)'));
  });

  test('nothing is read after a line that is not an RPC object', () async {
    final reader = ChatLineReader.start(
        Stream.value(utf8.encode('{"id":1}\nnot json token=s3cr3t\n{"id":2}\n')),
        rpc: true);
    final lines = await reader.lines.toList();
    expect(lines, hasLength(2));
    expect(lines.first.decoded, {'id': 1});
    expect(lines.last.text, 'not json token=s3cr3t');
    expect(lines.last.error, contains('FormatException'));
    expect(lines.last.error, isNot(contains('s3cr3t')));
    expect(
        (await ChatLineReader.start(Stream.value(utf8.encode('[1]\n')),
                    rpc: true)
                .lines
                .single)
            .error,
        contains('Expected RPC object'));
  });

  test('a final line without a newline is delivered, then the stream ends',
      () async {
    final reader = ChatLineReader.start(
        Stream.value(utf8.encode('{"id":1}\n{"id":2}')),
        rpc: true);
    expect((await reader.lines.toList()).map((l) => l.decoded), [
      {'id': 1},
      {'id': 2}
    ]);
  });

  test('a large output is read without holding the main isolate', () async {
    final big = jsonEncode({
      'method': 'item/completed',
      'params': {
        'item': {
          'aggregatedOutput':
              List.filled(200000, 'webToken: "x" token=abc 中文').join('\n')
        }
      }
    });
    final ticks = <int>[];
    final clock = Stopwatch()..start();
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      ticks.add(clock.elapsedMilliseconds);
    });
    final reader =
        ChatLineReader.start(_pieces('$big\n', 1 << 16), rpc: true);
    final line = (await reader.lines.toList()).single;
    timer.cancel();
    expect(line.error, isNull);
    expect(jsonEncode(line.redacted), isNot(contains('token=abc')));
    var longest = 0;
    for (var i = 1; i < ticks.length; i++) {
      if (ticks[i] - ticks[i - 1] > longest) longest = ticks[i] - ticks[i - 1];
    }
    // ignore: avoid_print
    print('${big.length} chars in ${clock.elapsedMilliseconds} ms; '
        'longest main-isolate gap $longest ms');
    expect(longest, lessThan(250));
  });
}
