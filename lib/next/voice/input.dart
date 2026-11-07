import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import 'decoder.dart';
import 'speech_decoder.dart';
import 'cloud_decoder.dart';
import '../../security/secret_redactor.dart';
import 'model_store.dart';

/// Microphone access is initiated only by the local user's input gesture.
class VoiceInput extends ChangeNotifier {
  VoiceInput({required this.onText});
  final void Function(String) onText;
  bool active = false;
  bool busy = false;
  String? error;
  bool _cancelled = false, _discard = false, _disposed = false;
  static const _audioSession = MethodChannel('nipaplay/voice_audio_session');
  bool _iosSession = false;
  AudioRecorder? _recorder;
  SpeechDecoder? _decoder;
  String label = '本机离线识别';
  StreamSubscription? _audio;
  Future<void>? _starting, _stopping;
  Future<void> _tail = Future.value();
  int _queued = 0;
  int _receivedBytes = 0;
  String _transcript = '';
  Timer? _limit;
  final _store = VoiceModelStore.instance;

  void _changed() {
    _store.recordingStatus(
        busy && !active
            ? 'preparing'
            : active
                ? 'recording'
                : 'idle',
        _receivedBytes,
        error);
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (active || busy || _stopping != null) return;
    busy = true;
    error = null;
    _queued = 0;
    _receivedBytes = 0;
    _transcript = '';
    _tail = Future.value();
    _cancelled = false;
    _discard = false;
    _changed();
    _starting = _start();
    await _starting;
  }

  Future<void> _start() async {
    try {
      await _store.load();
      if (!_store.enabled || !_store.ready) {
        throw StateError('请先在设置 › 实验室启用语音输入，下载本机模型或配置云端服务。');
      }
      await _store.stopRecording?.call();
      if (_cancelled || !_store.enabled || !_store.ready) return;
      _store.stopRecording = cancel;
      final recorder = _recorder = AudioRecorder();
      if (!await recorder.hasPermission()) {
        throw StateError('麦克风权限未开启，请在系统隐私设置中允许 NipaPlay 使用麦克风。');
      }
      if (_cancelled) return;
      final config = _store.configuration;
      label = config.label;
      if (config.local) {
        _decoder =
            await VoiceDecoder.open(_store.model, _store.pathFor(_store.model));
      } else {
        final key = await _store.cloudKey();
        if (_cancelled) return;
        final cloud =
            CloudSpeechDecoder(config, key, onText: _acceptText, onError: (e) {
          if (_discard) return;
          error = SecretRedactor.text('$e');
          unawaited(cancel());
        });
        _decoder = cloud;
        await cloud.open();
      }
      if (_cancelled) return;
      if (Platform.isIOS) {
        await _audioSession.invokeMethod<void>('begin');
        _iosSession = true;
        if (_cancelled) return;
      }
      final audio = await recorder.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        iosConfig: const IosRecordConfig(categoryOptions: [
          IosAudioCategoryOption.mixWithOthers,
          IosAudioCategoryOption.defaultToSpeaker,
          IosAudioCategoryOption.allowBluetooth,
          IosAudioCategoryOption.allowBluetoothA2DP,
        ]),
        streamBufferSize: 6400,
        // On macOS this enables a duplex VoiceProcessingIO graph. Dictation
        // only captures input; the unused output can fail with invalid sample
        // timestamps. Use plain microphone PCM instead.
        echoCancel: !Platform.isMacOS,
        noiseSuppress: !Platform.isMacOS,
      ));
      if (_cancelled) return;
      active = true;
      _store.recording = true;
      _audio = audio.listen((bytes) {
        if (_cancelled) return;
        _receivedBytes += bytes.length;
        _store.recordingStatus('recording', _receivedBytes, error);
        _queued += bytes.length;
        if (_queued > 16000 * 2 * 5) {
          error = '语音处理速度跟不上录音，请检查服务连接或更换本机模型。';
          unawaited(cancel());
          return;
        }
        _tail = _tail.then((_) async {
          try {
            if (_discard) return;
            final text = await _decoder!.accept(bytes);
            _acceptText(text);
          } catch (e) {
            if (!_discard) error = SecretRedactor.text('$e');
            unawaited(cancel());
          } finally {
            _queued -= bytes.length;
          }
        });
      }, onError: (Object e) {
        error = SecretRedactor.text('$e');
        unawaited(cancel());
      }, onDone: () {
        if (!_cancelled) unawaited(stop());
      });
      _limit = Timer(const Duration(minutes: 3), () => unawaited(stop()));
    } catch (e) {
      if (!_discard) error = SecretRedactor.text('$e');
      unawaited(cancel());
    } finally {
      busy = _stopping != null;
      _changed();
    }
  }

  void _acceptText(String text) {
    if (_discard || _disposed) return;
    _transcript = text;
    onText(text);
  }

  Future<void> cancel() {
    _discard = true;
    _decoder?.cancel();
    return stop();
  }

  Future<void> stop() {
    _cancelled = true;
    return _stopping ??= _stop().whenComplete(() => _stopping = null);
  }

  Future<void> _stop() async {
    busy = true;
    _changed();
    try {
      await _starting;
      _limit?.cancel();
      await _recorder?.stop();
      await _audio?.cancel();
      _audio = null;
      await _tail;
      active = false;
      _store.recordingStatus('transcribing', _receivedBytes, error);
      if (!_disposed) notifyListeners();
      if (!_discard && _decoder != null) {
        final text = await _decoder!.finish();
        if (!_discard) {
          if (text.isNotEmpty) _transcript = text;
          onText(_transcript);
          if (_transcript.isEmpty) {
            error = _receivedBytes == 0
                ? '未收到麦克风音频，请检查系统声音设置中的输入设备后重试。'
                : '未识别到语音，请检查麦克风输入音量后重试。';
          }
        }
      }
    } catch (e) {
      if (!_discard) error = SecretRedactor.text('$e');
    } finally {
      try {
        await _decoder?.close();
      } catch (e) {
        error ??= SecretRedactor.text('$e');
      }
      _decoder = null;
      try {
        await _recorder?.dispose();
      } catch (e) {
        error ??= SecretRedactor.text('$e');
      }
      _recorder = null;
      if (_iosSession) {
        _iosSession = false;
        try {
          await _audioSession.invokeMethod<void>('end');
        } catch (e) {
          error ??= SecretRedactor.text('$e');
        }
      }
      if (_store.stopRecording == cancel) _store.stopRecording = null;
      active = false;
      _store.recording = false;
      busy = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel());
    super.dispose();
  }
}
