import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'configuration.dart';
import '../../security/credential_store.dart';
import '../../security/secret_redactor.dart';
import '../../utils/globals.dart' as globals;

/// Settings and model preparation only. Enabling never opens a microphone.
class VoiceModelStore extends ChangeNotifier {
  static final instance = VoiceModelStore();
  static bool get supported =>
      !kIsWeb &&
      !globals.isTvOS &&
      (Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isIOS);
  static const enabledKey = 'next_voice_enabled';
  static const modelKey = 'next_voice_model';
  static const configurationKey = 'next_voice_configuration';
  VoiceConfiguration configuration = const VoiceConfiguration();
  bool keyConfigured = false;
  String recordingPhase = 'idle';
  int audioBytes = 0;
  String? recordingError;
  bool get ready => configuration.local ? installed : keyConfigured;

  void recordingStatus(String phase, int bytes, String? failure) {
    recordingPhase = phase;
    audioBytes = bytes;
    recordingError = failure == null ? null : SecretRedactor.text(failure);
  }

  Future<String> cloudKey() async {
    final key =
        await CredentialStore.instance.vault.read(configuration.credential);
    if (key == null || key.isEmpty) throw StateError('请在实验室设置配置语音服务密钥。');
    SecretRedactor.remember(configuration.credential, key);
    return key;
  }

  Future<void> configure(VoiceConfiguration value,
      {String? apiKey, bool clearCredential = false}) async {
    value.validate();
    await load();
    _requireSupported();
    await stopRecording?.call();
    final vault = CredentialStore.instance.vault;
    if (clearCredential) {
      await vault.delete(value.credential);
    } else if (apiKey != null && apiKey.isNotEmpty) {
      SecretRedactor.remember(value.credential, apiKey);
      await vault.write(value.credential, apiKey);
    }
    final configured = !value.local &&
        (await vault.read(value.credential))?.isNotEmpty == true;
    await (await SharedPreferences.getInstance())
        .setString(configurationKey, jsonEncode(value.toJson()));
    _cancelDownload();
    configuration = value;
    keyConfigured = configured;
    phase = installed ? 'ready' : 'not_downloaded';
    error = null;
    notifyListeners();
    if (enabled && value.local) prepare();
  }

  bool enabled = false;
  bool downloadRequested = false;
  bool recording = false;
  static String get defaultModelId =>
      Platform.isIOS ? voiceModels.last.id : voiceModels.first.id;
  String modelId = defaultModelId;
  String phase = 'not_downloaded';
  String? error;
  int received = 0;
  Directory? _root;
  Future<void>? _loading;
  Future<void> _preparing = Future.value();
  HttpClient? _client;
  int _generation = 0;
  Future<void> Function()? stopRecording;

  VoiceModel get model => voiceModel(modelId);
  String pathFor(VoiceModel m) => p.join(_root!.path, m.id);
  bool get installed => _root != null && _installed(model);
  bool _installed(VoiceModel m) =>
      File(p.join(pathFor(m), 'complete')).existsSync() &&
      File(p.join(pathFor(m), 'complete')).readAsStringSync() == m.sha256 &&
      m.files.every((f) => File(p.join(pathFor(m), f)).existsSync());

  Map<String, Object?> get status => {
        'supported': supported,
        'configuration': {
          ...configuration.toJson(),
          'keyConfigured': keyConfigured
        },
        'ready': ready,
        'recordingPhase': recordingPhase,
        'receivedAudioBytes': audioBytes,
        'recordingError': recordingError,
        'enabled': enabled,
        'model': modelId,
        'phase': phase,
        'installed': installed,
        'downloadedBytes': received,
        'downloadBytes': model.bytes,
        if (error != null) 'error': error,
        'recording': recording,
        'downloadRequested': downloadRequested,
      };

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    if (!supported) return;
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(enabledKey) ?? false;
    final saved = prefs.getString(configurationKey);
    if (saved != null) {
      configuration = VoiceConfiguration.fromJson(
          (jsonDecode(saved) as Map).cast<String, Object?>());
      configuration.validate();
      if (!configuration.local) {
        try {
          keyConfigured = (await CredentialStore.instance.vault
                      .read(configuration.credential))
                  ?.isNotEmpty ==
              true;
        } catch (e) {
          error = SecretRedactor.text('$e');
        }
      }
    }
    final selected = prefs.getString(modelKey);
    if (voiceModels.any((m) => m.id == selected)) modelId = selected!;
    _root = Directory(p.join(
        (await getApplicationSupportDirectory()).path, 'next', 'voice_models'));
    phase = installed ? 'ready' : 'not_downloaded';
    notifyListeners();
    if (enabled && configuration.local && !installed) prepare();
  }

  Future<void> setEnabled(bool value) async {
    await load();
    _requireSupported();
    await stopRecording?.call();
    await (await SharedPreferences.getInstance()).setBool(enabledKey, value);
    enabled = value;
    if (value && configuration.local) {
      prepare();
    } else {
      _cancelDownload();
      phase = installed ? 'ready' : 'not_downloaded';
      error = null;
      notifyListeners();
    }
  }

  Future<void> select(String id) async {
    voiceModel(id); // Reject unknown IDs before touching preferences.
    await load();
    _requireSupported();
    await stopRecording?.call();
    _cancelDownload();
    await (await SharedPreferences.getInstance()).setString(modelKey, id);
    modelId = id;
    phase = installed ? 'ready' : 'not_downloaded';
    received = 0;
    error = null;
    notifyListeners();
    if (enabled && configuration.local) prepare();
  }

  void _requireSupported() {
    if (!supported) {
      throw UnsupportedError('语音输入目前支持 macOS、Windows、Linux、iPhone 和 iPad。');
    }
  }

  void _cancelDownload() {
    downloadRequested = false;
    _generation++;
    _client?.close(force: true);
    _client = null;
  }

  /// Queues work and returns immediately, including for Agent settings writes.
  void prepare() {
    _requireSupported();
    downloadRequested = true;
    if (installed) {
      phase = 'ready';
      error = null;
      notifyListeners();
      return;
    }
    if (phase == 'downloading' || phase == 'installing') return;
    final generation = ++_generation;
    final chosen = model;
    phase = 'downloading';
    error = null;
    received = 0;
    notifyListeners();
    _preparing = _preparing
        .then((_) => _download(chosen, generation))
        .catchError((Object e) {
      if (generation == _generation) {
        phase = 'failed';
        error = e.toString();
        notifyListeners();
      }
    });
  }

  Future<void> remove() async {
    await setEnabled(false);
    await _preparing;
    final dir = Directory(pathFor(model));
    if (await dir.exists()) await dir.delete(recursive: true);
    phase = 'not_downloaded';
    notifyListeners();
  }

  Future<void> _download(VoiceModel chosen, int generation) async {
    if (generation != _generation) return;
    final stage = Directory('${pathFor(chosen)}.partial');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _client = client;
    try {
      if (await stage.exists()) await stage.delete(recursive: true);
      await stage.create(recursive: true);
      final archive = File(p.join(stage.path, 'model.tar.bz2'));
      final request = await client.getUrl(Uri.parse(chosen.url));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('模型下载 HTTP ${response.statusCode}',
            uri: Uri.parse(chosen.url));
      }
      final sink = archive.openWrite();
      var lastUpdate = DateTime.now();
      try {
        await for (final chunk
            in response.timeout(const Duration(seconds: 30))) {
          if (generation != _generation) return;
          received += chunk.length;
          if (received > chosen.bytes) {
            throw const FormatException('模型文件大小与发布清单不符。');
          }
          sink.add(chunk);
          // Flush periodically: backpressure also bounds the file sink's queue.
          if (DateTime.now().difference(lastUpdate).inMilliseconds >= 200) {
            await sink.flush();
            notifyListeners();
            lastUpdate = DateTime.now();
          }
        }
      } finally {
        await sink.close();
      }
      if (generation != _generation) return;
      phase = 'installing';
      notifyListeners();
      await Isolate.run(() => unpackVoiceModel(chosen, stage.path));
      if (generation != _generation) return;
      final target = Directory(pathFor(chosen));
      if (await target.exists()) await target.delete(recursive: true);
      await stage.rename(target.path);
      phase = 'ready';
    } catch (e) {
      if (generation == _generation) {
        phase = 'failed';
        error = e.toString();
      }
    } finally {
      client.close(force: true);
      if (identical(client, _client)) _client = null;
      if (await stage.exists()) await stage.delete(recursive: true);
      if (generation == _generation) notifyListeners();
    }
  }
}

/// Runs off the UI isolate. Only known model files are extracted, into a
/// staging directory; a verified complete model replaces the old directory.
void unpackVoiceModel(VoiceModel model, String directory) {
  final archive = File(p.join(directory, 'model.tar.bz2'));
  if (archive.lengthSync() != model.bytes) {
    throw const FormatException('模型下载不完整。');
  }
  final input = InputFileStream(archive.path);
  final tarPath = p.join(directory, 'model.tar');
  final output = OutputFileStream(tarPath);
  try {
    // Stream the hash to avoid holding the archive and decoded model in RAM.
    final bytes = archive.openSync();
    final hashes = _DigestSink();
    final hash = sha256.startChunkedConversion(hashes);
    try {
      while (true) {
        final chunk = bytes.readSync(1024 * 1024);
        if (chunk.isEmpty) break;
        hash.add(chunk);
      }
    } finally {
      bytes.closeSync();
      hash.close();
    }
    if (hashes.value.toString() != model.sha256) {
      throw const FormatException('模型 SHA-256 校验失败，请重新下载。');
    }
    BZip2Decoder().decodeStream(input, output);
  } finally {
    input.closeSync();
    output.closeSync();
  }
  final tar = InputFileStream(tarPath);
  try {
    final contents = TarDecoder().decodeStream(tar);
    for (final entry in contents) {
      final name = p.posix.basename(entry.name);
      if (!entry.isFile || !model.files.contains(name)) continue;
      final file = OutputFileStream(p.join(directory, name));
      try {
        entry.writeContent(file);
      } finally {
        file.closeSync();
      }
    }
    for (final name in model.files) {
      if (!File(p.join(directory, name)).existsSync()) {
        throw FormatException('模型缺少文件：$name');
      }
    }
    File(p.join(directory, 'complete')).writeAsStringSync(model.sha256);
  } finally {
    tar.closeSync();
    archive.deleteSync();
    File(tarPath).deleteSync();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
