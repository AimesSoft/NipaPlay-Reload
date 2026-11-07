import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../../security/secret_redactor.dart';
import 'configuration.dart';
import 'speech_decoder.dart';

/// Direct provider connections. Audio is kept only for this recording, at most
/// three minutes of 16 kHz mono PCM16; there is no app-operated speech service.
class CloudSpeechDecoder implements SpeechDecoder {
  CloudSpeechDecoder(this.config, this.apiKey,
      {required this.onText, required this.onError});
  final VoiceConfiguration config;
  final String apiKey;
  final void Function(String) onText;
  final void Function(Object) onError;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final _task = const Uuid().v4();
  final _audio = BytesBuilder(copy: false);
  final _sentences = <String, String>{};
  final _started = Completer<void>();
  final _finished = Completer<void>();
  WebSocket? _socket;
  StreamSubscription? _events;
  bool _closed = false;
  Object? _failure;
  int _bytes = 0;
  String get _text => _sentences.values.join('');

  Future<void> open() async {
    SecretRedactor.remember(config.credential, apiKey);
    if (config.provider == 'azure') return;
    try {
      final socket = await WebSocket.connect(config.endpoint,
              headers: {'Authorization': 'Bearer $apiKey'},
              customClient: _client)
          .then((socket) {
        if (_closed) unawaited(socket.close());
        return socket;
      }).timeout(const Duration(seconds: 15));
      if (_closed) {
        unawaited(socket.close());
        throw StateError('语音输入已取消');
      }
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 20);
      _events = socket.listen(_event, onError: _fail, onDone: () {
        if (!_closed && !_finished.isCompleted) {
          _fail(StateError('语音连接在结果完成前断开'));
        }
      });
      socket.add(jsonEncode({
        'header': {
          'action': 'run-task',
          'task_id': _task,
          'streaming': 'duplex'
        },
        'payload': {
          'task_group': 'audio',
          'task': 'asr',
          'function': 'recognition',
          'model': config.model,
          'parameters': {
            'format': 'pcm',
            'sample_rate': 16000,
            if (config.language.isNotEmpty) 'language_hints': [config.language]
          },
          'input': {}
        }
      }));
      await _started.future.timeout(const Duration(seconds: 15));
      _check();
    } catch (e) {
      cancel();
      rethrow;
    }
  }

  void _check() {
    if (_failure != null) throw _failure!;
    if (_closed) throw StateError('语音输入已取消');
  }

  void _event(dynamic data) {
    if (_closed) return;
    try {
      final event = jsonDecode(data as String) as Map;
      final header = event['header'] as Map;
      if (header['task_id'] != _task) return;
      switch (header['event']) {
        case 'task-started':
          if (!_started.isCompleted) _started.complete();
        case 'result-generated':
          final sentence =
              (event['payload'] as Map?)?['output']?['sentence'] as Map?;
          if (sentence == null || sentence['heartbeat'] == true) return;
          final id = sentence['sentence_id'] ?? sentence['begin_time'];
          if (id == null) {
            throw const FormatException('转写结果缺少 sentence_id / begin_time');
          }
          _sentences['$id'] = sentence['text'] as String? ?? '';
          onText(_text);
        case 'task-finished':
          if (!_finished.isCompleted) _finished.complete();
        case 'task-failed':
          _fail(StateError(
              '${header['error_code']}: ${header['error_message']}'));
      }
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object error) {
    if (_closed || _failure != null) return;
    _failure = StateError(SecretRedactor.text('$error'));
    // Complete signals normally and throw from the waiting operation. A failure
    // before finish() must not create an unhandled Future error.
    if (!_started.isCompleted) _started.complete();
    if (!_finished.isCompleted) _finished.complete();
    onError(_failure!);
  }

  @override
  Future<String> accept(Uint8List pcm) async {
    _check();
    _bytes += pcm.length;
    if (_bytes > 16000 * 2 * 180) throw StateError('语音输入最长 3 分钟');
    if (config.provider == 'azure') {
      _audio.add(pcm);
    } else {
      _socket!.add(pcm);
    }
    return _text;
  }

  @override
  Future<String> finish() async {
    _check();
    if (_bytes == 0) return '';
    if (config.provider == 'azure') {
      try {
        return await _azure().timeout(const Duration(seconds: 60));
      } finally {
        _client.close(force: true);
      }
    }
    _socket!.add(jsonEncode({
      'header': {
        'action': 'finish-task',
        'task_id': _task,
        'streaming': 'duplex'
      },
      'payload': {'input': {}}
    }));
    await _finished.future.timeout(const Duration(seconds: 30));
    _check();
    return _text;
  }

  Future<String> _azure() async {
    final uri = Uri.parse(config.endpoint).replace(
        path: '/speechtotext/transcriptions:transcribe',
        queryParameters: {'api-version': '2025-10-15'});
    final boundary = 'nipa-$_task';
    final request = await _client.postUrl(uri);
    _check();
    request.followRedirects = false;
    request.headers.set('Ocp-Apim-Subscription-Key', apiKey);
    request.headers.set(HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary');
    final definition = jsonEncode({
      'locales': [if (config.language.isNotEmpty) config.language]
    });
    final prefix = utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="definition"\r\nContent-Type: application/json\r\n\r\n$definition\r\n'
        '--$boundary\r\nContent-Disposition: form-data; name="audio"; filename="voice.wav"\r\nContent-Type: audio/wav\r\n\r\n');
    final suffix = utf8.encode('\r\n--$boundary--\r\n');
    final pcm = _audio.takeBytes();
    request.contentLength = prefix.length + 44 + pcm.length + suffix.length;
    request.add(prefix);
    request.add(pcmWavHeader(pcm.length));
    request.add(pcm);
    request.add(suffix);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    _check();
    if (response.statusCode != 200) {
      throw HttpException(
          SecretRedactor.text('Azure HTTP ${response.statusCode}: $body'));
    }
    final result = jsonDecode(body) as Map;
    final phrases = result['combinedPhrases'];
    if (phrases is! List) {
      throw const FormatException('Azure 响应缺少 combinedPhrases');
    }
    return phrases.map((p) => p['text'] as String).join('\n');
  }

  @override
  void cancel() {
    if (_closed) return;
    _closed = true;
    _audio.clear();
    _client.close(force: true);
    unawaited(_socket?.close());
    if (!_started.isCompleted) _started.complete();
    if (!_finished.isCompleted) _finished.complete();
  }

  @override
  Future<void> close() async {
    cancel();
    await _events?.cancel();
  }
}

Uint8List pcmWavHeader(int bytes) {
  final header = Uint8List(44);
  void text(int offset, String s) =>
      header.setRange(offset, offset + s.length, s.codeUnits);
  final data = ByteData.sublistView(header);
  text(0, 'RIFF');
  data.setUint32(4, bytes + 36, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, bytes, Endian.little);
  return header;
}
