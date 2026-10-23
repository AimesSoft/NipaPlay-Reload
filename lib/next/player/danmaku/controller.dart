import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../danmaku/source.dart';
import '../../settings/registry.dart';
import '../perf/budget.dart';
import 'native_sink.dart';
import 'settings.dart';
import 'timeline_build.dart';
import 'worker.dart';

/// Session-owned Dart snapshots. No kernel reads and no O(comment count)
/// work here: the timeline worker owns all source and inspection traversal.
final class SessionDanmakuController extends ChangeNotifier
    implements NextDanmakuSettingsTarget {
  SessionDanmakuController({Map<String, Object?>? initialSettings})
      : settings = {...NextDanmakuSettings.defaults, ...?initialSettings};

  final Map<String, Object?> settings;
  final _worker = DanmakuWorker();
  DanmakuTimeline timeline = DanmakuTimeline.empty;
  int version = 0;
  int _revision = 0;
  int _generation = 0;
  int durationMs = 0;
  String? sessionId;
  List<Map<String, dynamic>> chapters = const [];
  Future<void> _mutations = Future.value();
  Future<void>? _building;
  bool _dirty = false, _closed = false;
  SessionNativeDanmakuSink? _native;
  String? error;

  bool get native => _native != null;
  bool get visible => settings['danmaku.visible'] == true;
  double number(String key) => (settings[key] as num).toDouble();
  double get offset => number('danmaku.manualOffset');
  double get fontSize => number('danmaku.fontSize') <= 0
      ? 30 : number('danmaku.fontSize');
  double get scrollSeconds => 10 / number('danmaku.speedMultiplier');

  Future<void> loadSettings() async {
    final loaded = await NextDanmakuSettings.load();
    if (_closed) return;
    settings.addAll(loaded);
    notifyListeners();
    await rebuild();
  }

  void bind(String? id, {SessionNativeDanmakuSink? sink}) {
    if (_closed || id == sessionId && identical(sink, _native)) return;
    sessionId = id;
    _native = sink;
    _generation++;
    _revision++;
    timeline = DanmakuTimeline.empty;
    version++;
    durationMs = 0;
    chapters = const [];
    if (settings['danmaku.rememberOffset'] != true) {
      settings['danmaku.manualOffset'] = 0.0;
    }
    _enqueue(() => _worker.request<Object?>('clear', {}));
    notifyListeners();
  }

  /// Remove the native endpoint synchronously at the release fence.
  void fence() => _native = null;

  void attachNative(SessionNativeDanmakuSink sink) {
    if (_closed || identical(sink, _native)) return;
    _native = sink;
    unawaited(rebuild());
  }

  void inputs({required int duration,
      List<Map<String, dynamic>>? chapterFacts}) {
    if (_closed) return;
    if (duration == durationMs &&
        (chapterFacts == null || identical(chapterFacts, chapters))) return;
    durationMs = duration;
    if (chapterFacts != null) chapters = chapterFacts;
    unawaited(rebuild());
  }

  void _enqueue(Future<Object?> Function() run) {
    final generation = _generation;
    _mutations = _mutations.then((_) async {
      if (!_closed && generation == _generation) await run();
    }).catchError((Object e, StackTrace s) {
      if (!_closed) {
        error = e.toString();
        debugPrint('[NextDanmaku] $e');
      }
    });
  }

  void install(String id, JsonMap binding, List<DanmakuEntry> entries,
      {int startMs = 0, int? endMs}) {
    _enqueue(() => _worker.install(id, binding, entries, startMs, endMs));
    unawaited(rebuild());
  }

  void update(String id, JsonMap binding) {
    _enqueue(() => _worker.request<Object?>('update',
        {'id': id, 'binding': binding}));
    unawaited(rebuild());
  }

  void remove(String id) {
    _enqueue(() => _worker.request<Object?>('remove', {'id': id}));
    unawaited(rebuild());
  }

  Future<void> rebuild() {
    if (_closed) return Future.value();
    _revision++;
    _dirty = true;
    return _building ??= _drain().whenComplete(() => _building = null);
  }

  Future<void> _drain() async {
    while (_dirty && !_closed) {
      _dirty = false;
      final generation = _generation;
      final revision = _revision;
      // Any mutation queued while the previous one awaited must also finish.
      Future<void> pending;
      do {
        pending = _mutations;
        await pending;
      } while (!identical(pending, _mutations));
      if (_closed || generation != _generation) continue;
      try {
        final result = await _worker.request<DanmakuTimeline>('build', {
          'settings': settings, 'durationMs': durationMs,
          'chapters': chapters, 'version': version + 1,
        });
        if (_closed || generation != _generation || revision != _revision) {
          _dirty = true;
          continue;
        }
        PlayerPerf.span('danmaku.publish', () {
          timeline = result;
          version++;
          error = null;
          notifyListeners();
        });
        PlayerPerf.latency('danmaku.backgroundBuild',
            Duration(microseconds: result.buildUs));
        final sink = _native;
        if (sink != null) {
          await sink.configureDanmaku(Map.of(settings));
          if (identical(sink, _native)) {
            await sink.replaceDanmaku(result.entries);
          }
        }
      } catch (e) {
        if (!_closed) {
          error = e.toString();
          debugPrint('[NextDanmaku] $e');
        }
      }
    }
  }

  Future<void> get settled async {
    await _mutations;
    await _building;
  }

  Future<T> prepareLayout<T>(String renderer, Map<String, Object?> configuration) =>
      _worker.request<T>('layout.$renderer', configuration);

  Future<JsonMap> entries(JsonMap input, int positionMs) async {
    final expected = input['expectedListVersion'];
    final atVersion = version;
    final atSession = sessionId;
    if (expected != null && expected != atVersion) _conflict();
    final position = input['positionMs'] as int? ?? positionMs;
    final window = input['windowMs'] as int? ?? 5000;
    final start = input['startMs'] as int? ?? position - window;
    final end = input['endMs'] as int? ?? position + window;
    if (end < start) {
      throw const Failure(FailureCode.invalidInput, 'endMs must be >= startMs.');
    }
    if (sessionId == null) return {'sessionId': null, 'listVersion': version,
      'view': 'display_timeline', 'positionMs': position,
      'items': <JsonMap>[], 'nextCursor': null, 'total': 0};
    final result = await _worker.request<JsonMap>('page', {
      'input': {...input, 'positionMs': position}, 'version': atVersion,
      'sessionId': atSession, 'offset': offset,
    });
    if (version != atVersion || sessionId != atSession || result['conflict'] == true) {
      _conflict();
    }
    return result;
  }

  Never _conflict() => throw const Failure(FailureCode.conflict,
      'Danmaku timeline changed; restart pagination.');

  @override
  Object? readSetting(String key) => settings[key];

  @override
  Future<void> writeSetting(String key, Object? value) async {
    if (_closed) return;
    settings[key] = value;
    // Presentation changes are synchronous; comment filtering follows in the
    // worker and atomically replaces the timeline, never partially publishes.
    notifyListeners();
    if (key == 'danmaku.outlineWidth') {
      if (value == 0) settings['danmaku.outlineStyle'] = 'none';
      else if (settings['danmaku.outlineStyle'] == 'none') {
        settings['danmaku.outlineStyle'] = 'uniform';
      }
    }
    if (key == 'danmaku.outlineStyle') {
      if (value == 'none') settings['danmaku.outlineWidth'] = 0.0;
      else if (settings['danmaku.outlineWidth'] == 0) {
        settings['danmaku.outlineWidth'] = 2.0;
      }
    }
    if (key == 'danmaku.fontFilePath' && value == '') {
      settings['danmaku.fontFamily'] = '';
    }
    final rebuildNeeded = {'danmaku.blockWords', 'danmaku.blockTop',
      'danmaku.blockBottom', 'danmaku.blockScroll', 'danmaku.merge',
      'danmaku.randomColor', 'danmaku.manualOffset'}.contains(key);
    if (rebuildNeeded) unawaited(rebuild());
    final sink = _native;
    if (sink != null) await sink.configureDanmaku(Map.of(settings));
    if (key == 'danmaku.manualOffset') {
      await SettingsAccess.recordRuntime(key, null, value);
      return;
    }
    await _persist(key);
    if (key.startsWith('danmaku.outline')) {
      await _persist(key == 'danmaku.outlineWidth'
          ? 'danmaku.outlineStyle' : 'danmaku.outlineWidth');
    }
    if (key == 'danmaku.fontFilePath' && value == '') {
      await _persist('danmaku.fontFamily');
    }
  }

  Future<void> _persist(String key) async {
    final storage = NextDanmakuSettings.keys[key];
    if (storage == null) return;
    var value = settings[key];
    if (key == 'danmaku.blockWords') value = jsonEncode(value);
    if (key == 'danmaku.outlineStyle') {
      value = ['none', 'stroke', 'uniform'].indexOf(value as String);
    }
    if (key == 'danmaku.shadowStyle') {
      value = ['none', 'soft', 'medium', 'strong'].indexOf(value as String);
    }
    final prefs = await SharedPreferences.getInstance();
    await SettingsAccess.persist(storage, () => switch (value) {
      bool v => prefs.setBool(storage, v),
      int v => prefs.setInt(storage, v),
      double v => prefs.setDouble(storage, v),
      String v => prefs.setString(storage, v),
      _ => Future.value(false),
    });
  }

  JsonMap facts() => {'listVersion': version, 'count': timeline.entries.length,
    'total': timeline.total, 'backgroundBuildUs': timeline.buildUs,
    'invalidRules': timeline.invalidRules, 'error': error,
    'native': native, 'visible': visible,
    'opacity': settings['danmaku.opacity'], 'offsetSeconds': offset};

  @override
  void dispose() {
    _closed = true;
    _native = null;
    _worker.close();
    super.dispose();
  }
}
