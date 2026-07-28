import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nipaplay/cpp_native/bindings/example_calculator.dart';
import 'package:nipaplay/plugins/js_runtime_ohos.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:nipaplay/src/rust/api/media_metadata.dart';
import 'package:nipaplay/src/rust/rust_init.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final results = <String>[];
  await _runCheck(results, 'C++', () async {
    final calculator = ExampleCalculator();
    try {
      final sum = calculator.add(19, 23);
      final text = calculator.processText('HarmonyOS').requireValue;
      if (sum != 42 || text != '[NpNative] HARMONYOS') {
        throw StateError('unexpected result: sum=$sum, text=$text');
      }
      return 'add=$sum, text=$text';
    } finally {
      calculator.dispose();
    }
  });

  await _runCheck(results, 'QuickJS', () async {
    final runtime = HarmonyQuickJsRuntimeAdapter();
    try {
      runtime.setupBridge('PluginBridge', (args) {
        return (args['value'] as int) + 2;
      });
      const script = 'sendMessage("PluginBridge", JSON.stringify({value: 40}))';
      final value = runtime.evaluate(script);
      if (value != '42') {
        throw StateError('unexpected result: $value');
      }
      return 'bridge=$value';
    } finally {
      runtime.dispose();
    }
  });

  await _runCheck(results, 'Rust FRB', () async {
    await ensureRustInitialized();
    final value = mediaBaseNameWithoutExtension(
      pathOrName: '/tmp/Show.S01E02.mkv',
    );
    if (value != 'Show.S01E02') {
      throw StateError('unexpected result: $value');
    }
    return 'basename=$value';
  });

  await _runCheck(results, 'Torrent session', () async {
    final service = TorrentDownloadService.instance;
    await service.initialize();
    final tasks = await service.listTasks();
    return 'tasks=${tasks.length}';
  });

  await _runCheck(results, 'Path provider', () async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, '.nipaplay_ohos_smoke'));
    try {
      await file.writeAsString('HarmonyOS');
      final value = await file.readAsString();
      if (value != 'HarmonyOS') {
        throw StateError('unexpected file content: $value');
      }
      return directory.path;
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  });

  await _runCheck(results, 'SharedPreferences', () async {
    const key = 'nipaplay_ohos_smoke';
    final preferences = await SharedPreferences.getInstance();
    try {
      if (!await preferences.setInt(key, 42)) {
        throw StateError('setInt returned false');
      }
      await preferences.reload();
      final value = preferences.getInt(key);
      if (value != 42) {
        throw StateError('unexpected persisted value: $value');
      }
      return 'value=$value';
    } finally {
      await preferences.remove(key);
    }
  });

  await _runCheck(results, 'SQLite', () async {
    final databasePath = p.join(
      await getDatabasesPath(),
      'nipaplay_ohos_smoke.db',
    );
    await deleteDatabase(databasePath);
    final database = await openDatabase(databasePath);
    try {
      await database.execute(
        'CREATE TABLE smoke (id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
      );
      await database.insert('smoke', {'id': 1, 'value': 'HarmonyOS'});
      final rows =
          await database.query('smoke', where: 'id = ?', whereArgs: [1]);
      final value = rows.single['value'];
      if (value != 'HarmonyOS') {
        throw StateError('unexpected row: $rows');
      }
      return 'row=$value';
    } finally {
      await database.close();
      await deleteDatabase(databasePath);
    }
  });

  await _runCheck(results, 'Package and permission', () async {
    final packageInfo = await PackageInfo.fromPlatform();
    final cameraStatus = await Permission.camera.status;
    if (packageInfo.packageName.isEmpty) {
      throw StateError('empty package name');
    }
    return '${packageInfo.packageName}, camera=$cameraStatus';
  });

  await _runCheck(results, 'Screen brightness', () async {
    final brightness = await ScreenBrightness().application;
    if (brightness < 0 || brightness > 1) {
      throw StateError('invalid brightness: $brightness');
    }
    return 'value=${brightness.toStringAsFixed(2)}';
  });

  await _runCheck(results, 'System volume', () async {
    final volume = await VolumeController.instance.getVolume();
    if (volume < 0 || volume > 1) {
      throw StateError('invalid volume: $volume');
    }
    return 'value=${volume.toStringAsFixed(2)}';
  });

  await _runCheck(results, 'Wakelock', () async {
    final wasEnabled = await WakelockPlus.enabled;
    try {
      await WakelockPlus.enable();
      if (!await WakelockPlus.enabled) {
        throw StateError('wakelock did not become enabled');
      }
    } finally {
      await WakelockPlus.toggle(enable: wasEnabled);
    }
    return 'roundtrip=true';
  });

  final passed = results.every((result) => result.contains(' PASS '));
  // ignore: avoid_print
  print('[OHOS_SMOKE] COMPLETE ${passed ? 'PASS' : 'FAIL'}');
  runApp(_SmokeResultApp(results: results, passed: passed));
}

Future<void> _runCheck(
  List<String> results,
  String name,
  Future<String> Function() check,
) async {
  try {
    final detail = await check();
    final result = '$name PASS $detail';
    results.add(result);
    // ignore: avoid_print
    print('[OHOS_SMOKE] $result');
  } catch (error, stackTrace) {
    final result = '$name FAIL $error';
    results.add(result);
    // ignore: avoid_print
    print('[OHOS_SMOKE] $result');
    // ignore: avoid_print
    print(stackTrace);
  }
}

class _SmokeResultApp extends StatelessWidget {
  const _SmokeResultApp({
    required this.results,
    required this.passed,
  });

  final List<String> results;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('HarmonyOS native smoke test')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                passed ? 'PASS' : 'FAIL',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: passed ? Colors.green : Colors.red,
                    ),
              ),
              const SizedBox(height: 24),
              for (final result in results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(result),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
