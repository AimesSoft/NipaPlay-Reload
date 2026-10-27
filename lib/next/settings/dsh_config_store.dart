import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../chat/dsh_config.dart';
import '../ui_data/host_settings.dart';

/// User-owned source; dsh/nipa-patch.json remains generated and disposable.
final class DshConfigStore {
  DshConfigStore(this.root);
  final Directory root;
  File get file => File('${root.path}/dsh-config.json');
  String _revision(String text) => sha256.convert(utf8.encode(text)).toString();

  Future<String> _text() async =>
      await file.exists() ? file.readAsString() : DshConfig.starter;

  Future<DshConfig> load() async => DshConfig.parse(await _text());

  Future<UiDshConfig> read({String? activeFingerprint}) async {
    final text = await _text();
    String? fingerprint, error;
    try {
      fingerprint = DshConfig.parse(text).fingerprint;
    } on FormatException catch (e) {
      error = e.message;
    }
    return UiDshConfig(
        path: file.absolute.path,
        text: text,
        revision: _revision(text),
        fingerprint: fingerprint,
        activeFingerprint: activeFingerprint,
        error: error);
  }

  Future<void> save(String text, {required String expectedRevision}) async {
    DshConfig.parse(text);
    if (_revision(await _text()) != expectedRevision) {
      throw StateError('配置文件已在外部修改，请先重新读取再保存');
    }
    await root.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(text, flush: true);
    // Check again after IO; an external editor is not governed by our queue.
    if (_revision(await _text()) != expectedRevision) {
      await pending.delete();
      throw StateError('配置文件已在外部修改，请先重新读取再保存');
    }
    await pending.rename(file.path);
  }

  Future<void> open() async {
    if (!await file.exists()) {
      await root.create(recursive: true);
      // Exclusive creation leaves a concurrently created user file untouched.
      try {
        await file.create(exclusive: true);
        await file.writeAsString(DshConfig.starter, flush: true);
      } on FileSystemException {
        if (!await file.exists()) rethrow;
      }
    }
    if (Platform.isWindows) {
      await Process.start('notepad.exe', [file.absolute.path],
          mode: ProcessStartMode.detached);
    } else {
      final result = await Process.run(Platform.isMacOS ? 'open' : 'xdg-open',
          [if (Platform.isMacOS) '-t', file.absolute.path]);
      if (result.exitCode != 0) throw StateError('无法打开配置文件：${result.stderr}');
    }
  }
}
