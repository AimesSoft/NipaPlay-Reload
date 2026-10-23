import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:nipaplay/src/rust/api/dfm_plus.dart' as dfm;
import 'package:nipaplay/src/rust/api/next2.dart' as next2;
import 'package:nipaplay/src/rust/rust_init.dart';

import '../../danmaku/source.dart';
import '../perf/budget.dart';
import 'timeline_build.dart';

/// Keeps source lists and pagination off the UI isolate. Transfers into the
/// worker are bounded to 64 comments per event-loop turn; replies are copied
/// by the sending (background) isolate. The UI only assigns a snapshot.
final class DanmakuWorker {
  DanmakuWorker();
  final _replies = ReceivePort();
  final _ready = Completer<SendPort>();
  final _pending = <int, Completer<Object?>>{};
  Isolate? _isolate;
  int _seq = 0;
  bool _closed = false;
  Future<void>? _starting;

  Future<void> _start() => _starting ??= _spawn();
  Future<void> _spawn() async {
    _replies.listen((dynamic message) {
      if (message is SendPort) {
        _ready.complete(message);
        return;
      }
      final data = message as List;
      final done = _pending.remove(data[0]);
      if (data.length == 3) {
        done?.completeError(StateError(data[2] as String));
      } else {
        done?.complete(data[1]);
      }
    });
    final isolate = await Isolate.spawn(_run, _replies.sendPort,
        debugName: 'next-danmaku-timeline');
    if (_closed) {
      isolate.kill(priority: Isolate.immediate);
    } else {
      _isolate = isolate;
    }
  }

  Future<T> request<T>(String op, Map<String, dynamic> input) async {
    if (_closed) throw StateError('Danmaku worker closed');
    await _start();
    final port = await _ready.future;
    if (_closed) throw StateError('Danmaku worker closed');
    final id = ++_seq;
    final done = Completer<Object?>();
    _pending[id] = done;
    PlayerPerf.span('danmaku.dispatch.$op', () => port.send([id, op, input]));
    final result = (await done.future) as T;
    if (op.startsWith('layout.')) PlayerPerf.mark('danmaku.reply.$op');
    return result;
  }

  Future<void> install(String id, Map<String, dynamic> binding,
      List<DanmakuEntry> entries, int startMs, int? endMs) async {
    await request<Object?>('track', {'id': id, 'binding': binding,
      'startMs': startMs, 'endMs': endMs});
    for (var from = 0; from < entries.length; from += 64) {
      if (_closed) return;
      final to = (from + 64).clamp(0, entries.length);
      await request<Object?>('append', {'id': id,
        'entries': entries.sublist(from, to)});
      // Let input, rendering and other capabilities run between transfers.
      await Future<void>.delayed(Duration.zero);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _replies.close();
    for (final done in _pending.values) {
      done.completeError(StateError('Danmaku worker closed'));
    }
    _pending.clear();
  }
}

void _run(SendPort replies) {
  final input = ReceivePort();
  replies.send(input.sendPort);
  final tracks = <String, Map<String, dynamic>>{};
  var snapshot = DanmakuTimeline.empty;
  var version = 0;
  input.asyncMap((dynamic message) async {
    final request = message as List;
    final id = request[0] as int;
    final op = request[1] as String;
    final data = request[2] as Map<String, dynamic>;
    try {
      Object? result;
      switch (op) {
        case 'track':
          tracks[data['id'] as String] = {...data,
            'enabled': (data['binding'] as Map)['enabled'] == 1,
            'entries': <Map<String, dynamic>>[]};
        case 'append':
          final entries = tracks[data['id']]!['entries'] as List;
          for (final entry in data['entries'] as List<DanmakuEntry>) {
            entries.add(entry.toPlayer());
          }
        case 'echo':
          // Classic's local track for what the user sent (`local_我的弹幕`).
          final track = tracks.putIfAbsent('local_我的弹幕', () => {
            'id': 'local_我的弹幕', 'startMs': 0, 'endMs': null, 'enabled': true,
            'binding': {'enabled': 1, 'deduplicate': 0, 'offset_ms': 0,
              'video': {'sourceId': 'local'}},
            'entries': <Map<String, dynamic>>[]});
          final comment = Map<String, dynamic>.from(data['comment'] as Map);
          final type = comment['type'];
          comment['type'] = type is num
              ? (type == 5 ? 'top' : type == 4 ? 'bottom' : 'scroll')
              : type?.toString() ?? 'scroll';
          (track['entries'] as List).add({...comment, 'isMe': true,
            'content': comment['content'].toString(),
            'sourceTimeMs': ((comment['time'] as num) * 1000).round()});
        case 'remove':
          tracks.remove(data['id']);
        case 'update':
          final track = tracks[data['id']];
          if (track != null) {
            track['binding'] = data['binding'];
            track['enabled'] = (data['binding'] as Map)['enabled'] == 1;
          }
        case 'clear':
          tracks.clear();
          snapshot = DanmakuTimeline.empty;
          version = 0;
        case 'build':
          snapshot = buildTimeline(tracks,
              data['settings'] as Map<String, Object?>,
              data['durationMs'] as int,
              data['chapters'] as List<Map<String, dynamic>>,
              spoilerTexts: Set<String>.of(data['spoilerTexts'] as List<String>),
              externalSegments: (data['externalSegments'] as List).cast<Map<String, dynamic>>());
          version = data['version'] as int;
          result = snapshot;
        case 'page':
          if (data['version'] != version) {
            result = <String, dynamic>{'conflict': true};
          } else {
            result = pageTimeline(snapshot,
                data['input'] as Map<String, dynamic>, version,
                data['sessionId'] as String?, data['offset'] as double);
          }
        case 'layout.dfm':
          await ensureRustInitialized();
          result = await _prepareDfm(snapshot, data);
        case 'layout.next2':
          await ensureRustInitialized();
          result = await _prepareNext2(snapshot, data);
        default:
          throw StateError('Unknown danmaku worker operation: $op');
      }
      replies.send([id, result]);
    } catch (error, stack) {
      replies.send([id, null, '$error\n$stack']);
    }
  }).listen((_) {});
}

int _color(Object? raw) {
  if (raw is int) return (0xFF000000 | (raw & 0xFFFFFF)).toSigned(32);
  final text = raw.toString();
  if (text.startsWith('rgb(')) {
    final parts = text.substring(4, text.length - 1).split(',');
    if (parts.length >= 3) return (0xFF000000 |
      (int.parse(parts[0].trim()) << 16) | (int.parse(parts[1].trim()) << 8) |
      int.parse(parts[2].trim())).toSigned(32);
  }
  return (int.tryParse(text.replaceFirst('#', ''), radix: 16) ?? 0xFFFFFFFF).toSigned(32);
}

Future<dfm.DfmPlusPreparedLayout> _prepareDfm(DanmakuTimeline snapshot,
    Map<String, dynamic> c) async {
  final path = c['customFontFilePath'] as String? ?? '';
  final font = path.isEmpty ? null : await File(path).readAsBytes();
  return dfm.dfmPlusPrepareLayoutFull(
    rawItems: [for (final e in snapshot.entries) dfm.DfmPlusRawDanmakuItem(
      timeSeconds: (e['time'] as num).toDouble(), text: e['content'] as String,
      typeCode: e['type'] == 'top' ? 1 : e['type'] == 'bottom' ? 2 : 0,
      colorArgb: _color(e['color']), isMe: e['isMe'] == true)],
    width: c['width'] as double, height: c['height'] as double,
    fontSize: c['fontSize'] as double, displayArea: c['displayArea'] as double,
    scrollDurationSeconds: c['scrollDurationSeconds'] as double,
    allowStacking: c['allowStacking'] as bool,
    // Rules and block words were applied by the timeline builder; the merge
    // of same comments is the renderer's, as in Classic.
    mergeDanmaku: c['mergeDanmaku'] as bool, maxQuantity: c['maxQuantity'] as int?,
    maxLinesPerType: c['maxLinesPerType'] as int?,
    trackGapRatio: c['trackGapRatio'] as double,
    outlineWidth: c['outlineWidth'] as double, customFontBytes: font,
    blockWords: const []);
}

Future<next2.RustNext2PreparedLayout> _prepareNext2(DanmakuTimeline snapshot,
    Map<String, dynamic> c) => next2.next2PrepareLayout(
      request: next2.RustNext2PrepareRequest(
        items: [for (final e in snapshot.entries) next2.RustNext2DanmakuItem(
          timeSeconds: (e['time'] as num).toDouble(), text: e['content'] as String,
          typeCode: e['type'] == 'top' ? 1 : e['type'] == 'bottom' ? 2 : 0,
          colorArgb: _color(e['color']), isMe: e['isMe'] == true)],
        width: c['width'] as double, height: c['height'] as double,
        fontSize: c['fontSize'] as double, displayArea: c['displayArea'] as double,
        scrollDurationSeconds: c['scrollDurationSeconds'] as double,
        allowStacking: c['allowStacking'] as bool,
        mergeDanmaku: c['mergeDanmaku'] as bool,
        customFontFamily: c['customFontFamily'] as String? ?? '',
        customFontFilePath: c['customFontFilePath'] as String? ?? '',
      ));
