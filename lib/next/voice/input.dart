import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import 'decoder.dart';
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
  VoiceDecoder? _decoder;
  StreamSubscription? _audio;
  Future<void>? _starting, _stopping;
  Future<void> _tail = Future.value();
  int _queued = 0;
  Timer? _limit;
  final _store = VoiceModelStore.instance;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (active || busy || _stopping != null) return;
    busy = true;
    error = null;
    _queued = 0;
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
      if (!_store.enabled || !_store.installed) {
        throw StateError('请先在设置 › 实验室启用语音输入并下载模型。');
      }
      await _store.stopRecording?.call();
      if (_cancelled || !_store.enabled || !_store.installed) return;
      _store.stopRecording = cancel;
      final recorder = _recorder = AudioRecorder();
      if (!await recorder.hasPermission()) {
        throw StateError('麦克风权限未开启，请在系统隐私设置中允许 NipaPlay 使用麦克风。');
      }
      if (_cancelled) return;
      _decoder =
          await VoiceDecoder.open(_store.model, _store.pathFor(_store.model));
      if (_cancelled) return;
      if (Platform.isIOS) {
        await _audioSession.invokeMethod<void>('begin');
        _iosSession = true;
        if (_cancelled) return;
      }
      final audio = await recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        iosConfig: IosRecordConfig(categoryOptions: [
          IosAudioCategoryOption.mixWithOthers,
          IosAudioCategoryOption.defaultToSpeaker,
          IosAudioCategoryOption.allowBluetooth,
          IosAudioCategoryOption.allowBluetoothA2DP,
        ]),
        streamBufferSize: 6400,
        echoCancel: true,
        noiseSuppress: true,
      ));
      if (_cancelled) return;
      active = true;
      _store.recording = true;
      _audio = audio.listen((bytes) {
        if (_cancelled) return;
        _queued += bytes.length;
        if (_queued > 16000 * 2 * 5) {
          error = '本机识别速度跟不上录音，请改用中文轻量模型。';
          unawaited(cancel());
          return;
        }
        _tail = _tail.then((_) async {
          try {
            if (_discard) return;
            final text = await _decoder!.accept(bytes);
            if (!_discard) onText(text);
          } catch (e) {
            error = e.toString();
            unawaited(cancel());
          } finally {
            _queued -= bytes.length;
          }
        });
      }, onError: (Object e) {
        error = e.toString();
        unawaited(cancel());
      }, onDone: () {
        if (!_cancelled) unawaited(stop());
      });
      _limit = Timer(const Duration(minutes: 3), () => unawaited(stop()));
    } catch (e) {
      error = e.toString();
      unawaited(cancel());
    } finally {
      busy = _stopping != null;
      _changed();
    }
  }

  Future<void> cancel() {
    _discard = true;
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
      if (!_discard && _decoder != null) {
        final text = await _decoder!.finish();
        if (!_discard) onText(text);
      }
    } catch (e) {
      error = e.toString();
    } finally {
      try {
        await _decoder?.close();
      } catch (e) {
        error ??= e.toString();
      }
      _decoder = null;
      try {
        await _recorder?.dispose();
      } catch (e) {
        error ??= e.toString();
      }
      _recorder = null;
      if (_iosSession) {
        _iosSession = false;
        try {
          await _audioSession.invokeMethod<void>('end');
        } catch (e) {
          error ??= e.toString();
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
