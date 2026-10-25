import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/player/kernel/versions.dart';

/// The versions a kernel cannot report itself are the ones the build locks:
/// bump a dependency and this says to bump them in versions.dart too.
void main() {
  final lock = File('pubspec.lock').readAsStringSync();

  String? field(String package, String key) {
    final block =
        RegExp('\n  $package:\n((?:    .*\n|\n)*)').firstMatch(lock)?.group(1);
    return block == null
        ? null
        : RegExp('$key: "?([^"\n]+)"?').firstMatch(block)?.group(1);
  }

  test('the Erika and video_player versions are the locked ones', () {
    expect(field('erika_flutter', 'version'), erikaFlutterVersion);
    expect(field('erika_flutter', 'source'), 'hosted');
    expect(liberikaRef, 'v$erikaFlutterVersion');
    expect(field('video_player', 'version'), videoPlayerVersion);
    expect(field('video_player_avfoundation', 'version'),
        videoPlayerAvfoundationVersion);
  });
}
