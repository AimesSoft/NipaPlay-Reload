import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/voice/cloud_decoder.dart';
import 'package:nipaplay/next/voice/configuration.dart';

void main() {
  late HttpServer server;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    await server.close(force: true);
  });

  test('Azure uploads PCM WAV only on finish and reads combined transcript',
      () async {
    var requests = 0;
    final received = Completer<void>();
    server.listen((request) async {
      requests++;
      expect(request.uri.path, '/speechtotext/transcriptions:transcribe');
      expect(request.uri.queryParameters['api-version'], '2025-10-15');
      expect(
          request.headers.value('Ocp-Apim-Subscription-Key'), 'fixture-secret');
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      final content = latin1.decode(body);
      expect(content, contains('"locales":["zh-CN"]'));
      final header = content.indexOf('RIFF');
      expect(header, greaterThan(0));
      final wav = ByteData.sublistView(
          Uint8List.fromList(body.sublist(header, header + 44)));
      expect(wav.getUint32(24, Endian.little), 16000);
      expect(wav.getUint32(40, Endian.little), 4);
      expect(body.sublist(header + 44, header + 48), [1, 2, 3, 4]);
      request.response.write(jsonEncode({
        'combinedPhrases': [
          {'text': '你好。'}
        ]
      }));
      await request.response.close();
      received.complete();
    });
    final decoder = CloudSpeechDecoder(
        VoiceConfiguration(
            provider: 'azure',
            endpoint: 'http://127.0.0.1:${server.port}',
            language: 'zh-CN'),
        'fixture-secret',
        onText: (_) {},
        onError: (e) => fail('$e'));
    await decoder.open();
    await decoder.accept(Uint8List.fromList([1, 2, 3, 4]));
    expect(requests, 0);
    expect(await decoder.finish(), '你好。');
    await received.future;
    await decoder.close();
  });

  test(
      'streaming revises partial sentences and waits for final text after stop',
      () async {
    final gotAudio = Completer<void>();
    final texts = <String>[];
    server.listen((request) async {
      expect(request.headers.value('authorization'), 'Bearer stream-secret');
      final socket = await WebSocketTransformer.upgrade(request);
      String? task;
      void send(String event, [Map? sentence]) => socket.add(jsonEncode({
            'header': {'task_id': task, 'event': event},
            if (sentence != null)
              'payload': {
                'output': {'sentence': sentence}
              }
          }));
      socket.listen((message) {
        if (message is List<int>) {
          expect(message, [1, 2]);
          send('result-generated', {'sentence_id': 1, 'text': '你'});
          send('result-generated',
              {'sentence_id': 1, 'text': '你好', 'sentence_end': true});
          gotAudio.complete();
        } else {
          final value = jsonDecode(message as String) as Map;
          task = value['header']['task_id'] as String;
          if (value['header']['action'] == 'run-task') {
            expect(value['payload']['parameters']['sample_rate'], 16000);
            send('task-started');
          } else {
            send('result-generated',
                {'sentence_id': 2, 'text': '世界。', 'sentence_end': true});
            send('task-finished');
          }
        }
      });
    });
    final decoder = CloudSpeechDecoder(
        VoiceConfiguration(
            provider: 'dashscope', endpoint: 'ws://127.0.0.1:${server.port}'),
        'stream-secret',
        onText: texts.add,
        onError: (e) => fail('$e'));
    await decoder.open();
    await decoder.accept(Uint8List.fromList([1, 2]));
    await gotAudio.future;
    expect(await decoder.finish(), '你好世界。');
    expect(texts, ['你', '你好', '你好世界。']);
    await decoder.close();
  });

  test('cancel aborts an Azure request without waiting for provider timeout',
      () async {
    final received = Completer<void>();
    server.listen((request) async {
      await request.drain<void>();
      received.complete();
    });
    final decoder = CloudSpeechDecoder(
        VoiceConfiguration(
            provider: 'azure', endpoint: 'http://127.0.0.1:${server.port}'),
        'cancel-secret',
        onText: (_) => fail('cancelled recording published text'),
        onError: (_) {});
    await decoder.open();
    await decoder.accept(Uint8List.fromList([0, 0]));
    final finished = expectLater(decoder.finish(), throwsA(anything));
    await received.future;
    decoder.cancel();
    await finished.timeout(const Duration(seconds: 2));
    await decoder.close();
  });

  test('provider failures preserve the reason but redact credentials',
      () async {
    final failed = Completer<Object>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) {
        final task = jsonDecode(message as String)['header']['task_id'];
        socket.add(jsonEncode({
          'header': {
            'task_id': task,
            'event': 'task-failed',
            'error_code': 'InvalidApiKey',
            'error_message': 'rejected test-sensitive-value'
          }
        }));
      });
    });
    final decoder = CloudSpeechDecoder(
        VoiceConfiguration(
            provider: 'dashscope', endpoint: 'ws://127.0.0.1:${server.port}'),
        'test-sensitive-value',
        onText: (_) {},
        onError: failed.complete);
    await expectLater(decoder.open(), throwsStateError);
    final error = '${await failed.future}';
    expect(error, contains('InvalidApiKey'));
    expect(error, isNot(contains('test-sensitive-value')));
    await decoder.close();
  });
}
