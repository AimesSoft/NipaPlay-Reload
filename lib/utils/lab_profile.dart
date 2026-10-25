import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver;
import 'package:path/path.dart' as p;
// Use the installed plugin interfaces; lab profiles add no dependencies.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'lab_window_stub.dart'
    if (dart.library.ffi) 'lab_window_native.dart';

/// A debug process profile. Never reads or migrates the normal instance's state.
abstract final class LabProfile {
  static final String? name = parseName(
      kIsWeb || !kDebugMode ? null : Platform.environment['NIPAPLAY_PROFILE']);
  static String? _root;
  static bool get active => name != null;

  /// Lab instances run beside the user's work: they start behind other
  /// windows and never take focus, unless NIPAPLAY_LAB_QUIET=0 (a demo).
  static bool get quiet =>
      active && Platform.environment['NIPAPLAY_LAB_QUIET'] != '0';

  /// window_manager's macOS show() always activates the app, so a quiet
  /// instance shows its window natively, behind everything.
  static Future<void> showBehind() async {
    if (!Platform.isWindows) {
      return const MethodChannel('nipaplay/instance')
          .invokeMethod('showBehind');
    }
    // The Windows runner has no native channel, and window_manager's show()
    // takes the foreground.
    showWindowWithoutActivating(title('NipaPlay'));
  }

  /// A quiet instance's window is on no screen, so macOS reports the app
  /// hidden and Flutter would stop drawing; it keeps drawing, for the tools
  /// that look at and operate it.
  static void keepDrawing() {
    if (quiet) WidgetsBinding.instance.addObserver(_KeepDrawing());
  }
  static String get root => _root!;
  static String location(String child) => p.join(root, child);
  static String title(String title) => active ? '$title · LAB [$name]' : title;

  static String? parseName(String? value) {
    if (value == null) return null;
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(value)) {
      throw ArgumentError(
          'NIPAPLAY_PROFILE must be 1–64 lowercase ASCII letters, digits, _ or -, starting with a letter or digit.');
    }
    return value;
  }

  static Future<void> initialize() async {
    if (!active) return;
    if (Platform.isWindows) {
      // No native write sandbox here: the profile lives under the directory
      // named by NIPAPLAY_LAB_ROOT, and every path the app asks for is
      // redirected into it (the launcher also points APPDATA and
      // LOCALAPPDATA there). External files are not enforced read-only.
      final base = Platform.environment['NIPAPLAY_LAB_ROOT'];
      if (base == null || !p.isAbsolute(base)) {
        throw StateError(
            'NIPAPLAY_LAB_ROOT must name an absolute directory for lab profiles on Windows.');
      }
      _root = p.join(base, name!);
      await Directory(_root!).create(recursive: true);
    } else {
      if (!Platform.isMacOS) {
        throw UnsupportedError('Lab profiles require the macOS write sandbox.');
      }
      final info = await const MethodChannel('security_bookmark')
          .invokeMapMethod<String, Object?>('labProfileInfo');
      if (info?['name'] != name || info?['writeSandbox'] != true) {
        throw StateError('Native lab profile isolation was not installed.');
      }
      _root = info!['root'] as String;
    }
    await File(location('lab-profile.json')).writeAsString(
        jsonEncode({
          'profile': name,
          'endpointFile': location('endpoint.json'),
        }),
        flush: true);
    PathProviderPlatform.instance = LabPaths(root);
    SharedPreferencesStorePlatform.instance =
        LabPreferences(File(location('preferences.json')));
    debugPrint('LAB [$name] root=$root; external files are read-only');
  }
}

final class LabPaths extends PathProviderPlatform {
  LabPaths(this.root);
  final String root;
  Future<String> _directory(String child) async =>
      (await Directory(p.join(root, child)).create(recursive: true)).path;
  @override
  Future<String?> getTemporaryPath() => _directory('temp');
  @override
  Future<String?> getApplicationSupportPath() => _directory('support');
  @override
  Future<String?> getLibraryPath() => _directory('library');
  @override
  Future<String?> getApplicationDocumentsPath() => _directory('documents');
  @override
  Future<String?> getApplicationCachePath() => _directory('cache');
  @override
  Future<String?> getDownloadsPath() => _directory('data/downloads');
}

/// Serial writes preserve simultaneous Classic and Next preference updates.
/// The file is read once; this instance is its only writer while the lab
/// runs, so later reads and writes start from what it last wrote, and each
/// write is encoded and stored on a background isolate.
final class LabPreferences extends SharedPreferencesStorePlatform {
  LabPreferences(this.file);
  final File file;
  Future<void> _pending = Future.value();
  Map<String, Object>? _values;

  Map<String, Object> _read() => _values ??= file.existsSync()
      ? Map<String, Object>.from(jsonDecode(file.readAsStringSync()) as Map)
      : {};

  Future<bool> _update(void Function(Map<String, Object>) operation) {
    final result = _pending.then((_) async {
      final values = _read();
      operation(values);
      await _store(file.path, values);
      return true;
    });
    _pending = result.then<void>((_) {});
    return result;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _update((values) => values[key] = value);
  @override
  Future<bool> remove(String key) => _update((values) => values.remove(key));
  @override
  Future<bool> clear() => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));
  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      _update((values) => values.removeWhere((key, _) =>
          key.startsWith(parameters.filter.prefix) &&
          (parameters.filter.allowList == null ||
              parameters.filter.allowList!.contains(key))));
  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));
  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    await _pending;
    return Map.of(_read())
      ..removeWhere((key, _) =>
          !key.startsWith(parameters.filter.prefix) ||
          (parameters.filter.allowList != null &&
              !parameters.filter.allowList!.contains(key)));
  }
}

class _KeepDrawing with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      // Lab-only (debug builds): stand in for the engine's lifecycle report.
      final binding = SchedulerBinding.instance;
      scheduleMicrotask(() =>
          // ignore: invalid_use_of_protected_member
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive));
    }
  }
}

Future<void> _store(String path, Map<String, Object> values) =>
    Isolate.run(() {
      final staging = File('$path.pending');
      staging.writeAsStringSync(jsonEncode(values), flush: true);
      staging.renameSync(path);
    });
