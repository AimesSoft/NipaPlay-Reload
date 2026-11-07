import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'models.dart';
import 'speech_decoder.dart';

/// One native recognizer, owned and freed by one worker isolate per recording.
class VoiceDecoder implements SpeechDecoder {
  VoiceDecoder._(this._isolate, this._commands);
  final Isolate _isolate;
  final SendPort _commands;

  static Future<VoiceDecoder> open(VoiceModel model, String path) async {
    final ready = ReceivePort();
    final worker =
        await Isolate.spawn(_decodeWorker, (ready.sendPort, model, path));
    try {
      final result = await ready.first.timeout(const Duration(seconds: 30));
      if (result is String) throw StateError(result);
      return VoiceDecoder._(worker, result as SendPort);
    } catch (_) {
      worker.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      ready.close();
    }
  }

  Future<String> _request(String command, [Uint8List? bytes]) async {
    final reply = ReceivePort();
    _commands.send((command, bytes, reply.sendPort));
    try {
      final result =
          await reply.first.timeout(const Duration(seconds: 15)) as Map;
      if (result['error'] case final String error) throw StateError(error);
      return result['text'] as String;
    } finally {
      reply.close();
    }
  }

  @override
  Future<String> accept(Uint8List pcm) => _request('audio', pcm);
  @override
  Future<String> finish() => _request('finish');
  @override
  void cancel() {}

  @override
  Future<void> close() async {
    // Native free happens on the owner, before the worker exits.
    try {
      await _request('close');
    } finally {
      _isolate.kill();
    }
  }
}

void _decodeWorker((SendPort, VoiceModel, String) args) async {
  final (ready, model, directory) = args;
  sherpa.OnlineRecognizer? recognizer;
  sherpa.OnlineStream? stream;
  final commands = ReceivePort();
  try {
    sherpa.initBindings();
    String file(String name) => p.join(directory, name);
    recognizer = sherpa.OnlineRecognizer(sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: model.ctc
            ? const sherpa.OnlineTransducerModelConfig()
            : sherpa.OnlineTransducerModelConfig(
                encoder: file(model.files[0]),
                decoder: file(model.files[1]),
                joiner: file(model.files[2])),
        zipformer2Ctc: model.ctc
            ? sherpa.OnlineZipformer2CtcModelConfig(model: file(model.files[0]))
            : const sherpa.OnlineZipformer2CtcModelConfig(),
        tokens: file('tokens.txt'),
        numThreads: 2,
        provider: 'cpu',
      ),
    ));
    stream = recognizer.createStream();
    ready.send(commands.sendPort);
    var committed = '';
    int? remainder;
    await for (final message in commands) {
      final (command, bytes, reply) = message as (String, Uint8List?, SendPort);
      try {
        if (command == 'close') {
          stream?.free();
          stream = null;
          recognizer?.free();
          recognizer = null;
          reply.send({'text': ''});
          break;
        }
        if (bytes != null) {
          final samples =
              Float32List((bytes.length + (remainder == null ? 0 : 1)) ~/ 2);
          var index = 0, offset = 0;
          if (remainder != null && bytes.isNotEmpty) {
            final value = remainder | (bytes[0] << 8);
            samples[index++] = value.toSigned(16) / 32768.0;
            offset = 1;
            remainder = null;
          }
          for (; offset + 1 < bytes.length; offset += 2) {
            final value = bytes[offset] | (bytes[offset + 1] << 8);
            samples[index++] = value.toSigned(16) / 32768.0;
          }
          if (offset < bytes.length) remainder = bytes[offset];
          stream!.acceptWaveform(samples: samples, sampleRate: 16000);
        }
        if (command == 'finish') {
          stream!
              .acceptWaveform(samples: Float32List(12800), sampleRate: 16000);
          stream.inputFinished();
        }
        while (recognizer!.isReady(stream!)) {
          recognizer.decode(stream);
        }
        final current = recognizer.getResult(stream).text.trim();
        final text = [committed, current].where((s) => s.isNotEmpty).join(' ');
        if (recognizer.isEndpoint(stream)) {
          committed = text;
          recognizer.reset(stream);
        }
        reply.send({'text': text});
      } catch (e) {
        reply.send({'error': e.toString()});
      }
    }
  } catch (e) {
    ready.send(e.toString());
  } finally {
    stream?.free();
    recognizer?.free();
    commands.close();
  }
}
