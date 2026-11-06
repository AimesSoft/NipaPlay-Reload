import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/ui/settings/settings_layout.dart';
import 'package:nipaplay/next/voice/model_store.dart';
import 'package:nipaplay/next/voice/models.dart';
import 'package:nipaplay/next/voice/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('GUI and agent share device settings; enable does not record', () async {
    final root = await Directory.systemTemp.createTemp('nipa-voice-settings-');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => root.path);
    sqfliteFfiInit();
    final db = await openNextDatabase(root, factory: databaseFactoryFfi);
    final store = VoiceModelStore();
    final registry = SettingsRegistry(db, voiceSettings(modelStore: store));
    final agent = Invocation(origin: 'agent');
    try {
      await store.load();
      expect(store.enabled, false);
      expect(store.status['recording'], false);
      await registry.set('labs.voiceModel', voiceModels.last.id, agent);
      expect(store.phase,
          'not_downloaded'); // Selecting while off never downloads.
      final model = store.model;
      final dir = await Directory(store.pathFor(model)).create(recursive: true);
      for (final file in model.files) {
        await File('${dir.path}/$file').writeAsString('fixture');
      }
      await File('${dir.path}/complete').writeAsString(model.sha256);
      await registry.set('labs.voiceEnabled', true, agent);
      expect(store.phase, 'ready');
      final row = await registry.get('labs.voiceStatus');
      final status = jsonDecode(row['value'] as String) as Map;
      expect(status['recording'], false);
      expect(status['installed'], true);
      expect(status['enabled'], true);
      await registry.set('labs.voiceEnabled', false, agent);
      expect(
          store.installed, true); // Turning off retains the downloaded model.
      await registry.set('labs.voiceModelDownload', false, agent);
      expect(store.installed, false);
      expect(store.enabled, false);
      expect(
          SettingsLayout.sectionOf('labs.voiceEnabled'), SettingsSection.labs);
      expect(SettingsLayout.sectionOf('labs.enableImmersiveAnimeDetail'),
          SettingsSection.labs);
      await expectLater(() => registry.set('labs.voiceModel', 'unknown', agent),
          throwsA(isA<Failure>()));
      await expectLater(() => registry.set('labs.voiceStatus', '{}', agent),
          throwsA(isA<Failure>()));
    } finally {
      await registry.drain();
      await db.close();
      store.dispose();
      await root.delete(recursive: true);
    }
  });

  test(
      'verified model extracts off the UI isolate and publishes a completion marker',
      () async {
    final root = await Directory.systemTemp.createTemp('nipa-voice-install-');
    try {
      final archive = Archive()
        ..addFile(ArchiveFile.string('upstream/model.onnx', 'model-data'))
        ..addFile(ArchiveFile.string('upstream/tokens.txt', 'tokens'))
        ..addFile(ArchiveFile.string('upstream/test.wav', 'not-installed'));
      final bytes =
          BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(archive));
      final model = VoiceModel('fixture', 'fixture', 'fixture', bytes.length,
          sha256.convert(bytes).toString(), ['model.onnx', 'tokens.txt']);
      await File('${root.path}/model.tar.bz2').writeAsBytes(bytes);
      final path = root.path;
      await Isolate.run(() => unpackVoiceModel(model, path));
      expect(await File('$path/model.onnx').readAsString(), 'model-data');
      expect(await File('$path/complete').readAsString(), model.sha256);
      expect(File('$path/test.wav').existsSync(), false);
      expect(File('$path/model.tar.bz2').existsSync(), false);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('corrupt download never becomes an installed model', () async {
    final root = await Directory.systemTemp.createTemp('nipa-voice-corrupt-');
    try {
      await File('${root.path}/model.tar.bz2').writeAsString('truncated');
      expect(() => unpackVoiceModel(voiceModels.last, root.path),
          throwsFormatException);
      expect(File('${root.path}/complete').existsSync(), false);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
