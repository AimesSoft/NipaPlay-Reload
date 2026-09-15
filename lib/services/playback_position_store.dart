import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _positionsKey = 'video_positions';

// This callback must stay top-level: never capture a player, plugin or channel
// in a closure sent to the worker isolate.
String _updatePositions((String, String, int) request) {
  final (existing, path, position) = request;
  final positions = Map<String, dynamic>.from(json.decode(existing));
  positions[path] = position;
  return json.encode(positions);
}

Future<String> _readPositions() async =>
    (await SharedPreferences.getInstance()).getString(_positionsKey) ?? '{}';

Future<void> _writePositions(String value) async {
  if (!await (await SharedPreferences.getInstance())
      .setString(_positionsKey, value)) {
    throw StateError('Failed to persist playback position');
  }
}

/// Serializes the entire read/modify/write operation, not only the disk write.
/// A pause, seek backwards, or switch to another file cannot be overwritten by
/// an older background encoding job. The shared JSON format is unchanged.
class PlaybackPositionStore {
  PlaybackPositionStore({
    Future<String> Function()? read,
    Future<void> Function(String)? write,
  })  : _read = read ?? _readPositions,
        _write = write ?? _writePositions;

  static final instance = PlaybackPositionStore();
  final Future<String> Function() _read;
  final Future<void> Function(String) _write;
  Future<void> _pending = Future<void>.value();

  Future<void> save(String path, int position, {VoidCallback? onPrepared}) {
    final operation = _pending.then((_) async {
      final existing = await _read();
      final encoded = await compute(
          _updatePositions, (existing, path, position),
          debugLabel: 'nipaplay.playback_position.encode');
      onPrepared?.call();
      await _write(encoded);
    });
    // Report failures to the caller but keep later saves and shutdown draining
    // usable after a transient disk/encoding failure.
    _pending =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  Future<void> flush() async {
    // Include saves enqueued while an earlier write was in flight.
    var pending = _pending;
    do {
      pending = _pending;
      await pending;
    } while (!identical(pending, _pending));
  }
}
