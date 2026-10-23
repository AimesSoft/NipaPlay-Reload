import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/player/classic/local_playback_operations.dart';
import 'package:nipaplay/next/player/features/operation_specs.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('Next local feature action IDs and schemas equal the original catalogue',
      () {
    final old = LocalPlaybackOperations(
        _Player(),
        SettingsRegistry(_Database(), []),
        () => throw StateError('Schema inspection must not read the UI'));
    final specs = {
      for (final action in old.actions) action.spec.id: action.spec
    };
    expect(featureOperationSpecs.keys.toSet(), specs.keys.toSet());
    for (final entry in featureOperationSpecs.entries) {
      final previous = specs[entry.key]!;
      expect(entry.value.input.toJsonSchema(), previous.input.toJsonSchema(),
          reason: entry.key);
      expect(entry.value.output.toJsonSchema(), previous.output.toJsonSchema(),
          reason: entry.key);
      expect(entry.value.effect, previous.effect, reason: entry.key);
    }
  });
}

class _Player implements VideoPlayerState {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Database implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
