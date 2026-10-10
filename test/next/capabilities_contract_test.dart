import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/history_capability.dart';
import 'package:nipaplay/next/capabilities/library_capability.dart';
import 'package:nipaplay/next/capabilities/navigation_capability.dart';

import 'test_support.dart';

void main() {
  test('all nine actions produce real outputs matching their contracts',
      () async {
    final playback = PlaybackFixture();
    final pages = <String>[];
    final harness = Harness([
      LibraryCapability(
          history: () => playback.rows, seriesDetail: (_) => seriesDetail()),
      HistoryCapability(
          continueWatching: () => playback.rows,
          seriesDetail: (_) => seriesDetail()),
      playback.capability,
      NavigationCapability(changePage: pages.add),
    ]);
    final calls = <String, JsonMap>{
      'media.library.search': {},
      'media.library.series': {'animeId': 10},
      'history.continue_watching': {},
      'playback.open': {'path': '/media/episode.mkv'},
      'playback.state': {},
      'playback.set_paused': {'paused': true},
      'playback.seek': {'positionMs': 250},
      'playback.switch_episode': {'direction': 'next'},
      'ui.navigate': {'page': 'media_library'},
    };
    expect(harness.catalog.map((spec) => spec.id).toSet(), calls.keys.toSet());
    for (final call in calls.entries) {
      await invokeCompleted(harness, call.key, call.value);
    }
    expect(pages, ['media_library']);
    expect(playback.started.length, 1);
    expect(playback.player.episodeId, 101);
    final readIds = {
      'media.library.search',
      'media.library.series',
      'history.continue_watching',
      'playback.state',
    };
    for (final spec in harness.catalog) {
      expect(
          spec.effect, readIds.contains(spec.id) ? Effect.read : Effect.write);
    }
  });
}
