import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/mesh/library_codec.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

UiEpisode _episode(int number,
        {double? progress, DateTime? at, bool playable = true}) =>
    UiEpisode(
        episodeId: 'e$number',
        workId: 'w',
        number: number,
        progress: progress,
        lastPlayedAt: at,
        playable: playable);

/// #1127: the play button of a work opened episode 158, left half-watched
/// long ago, after episode 165 had just been left.
void main() {
  final earlier = DateTime.utc(2026, 10, 1), later = DateTime.utc(2026, 11, 19);
  List<UiEpisode> series(Map<int, UiEpisode> played) => [
        for (var n = 150; n <= 170; n++) played[n] ?? _episode(n),
      ];

  test('the episode just left, not an older one in progress', () {
    final episodes = series({
      158: _episode(158, progress: 0.4, at: earlier),
      165: _episode(165, progress: 0.3, at: later),
    });
    expect(nextEpisode(episodes)?.number, 165);
  });

  test('after an episode finished last, the next unfinished one after it', () {
    final episodes = series({
      158: _episode(158, progress: 0.4, at: earlier),
      165: _episode(165, progress: 1, at: later),
      166: _episode(166, progress: 1, at: earlier),
    });
    expect(nextEpisode(episodes)?.number, 167);
  });

  test('the episode just left, if it cannot play now, gives way', () {
    final episodes = series({
      158: _episode(158, progress: 0.4, at: earlier),
      165: _episode(165, progress: 0.3, at: later, playable: false),
    });
    expect(nextEpisode(episodes)?.number, 158);
  });

  test('never played: the first episode', () {
    expect(nextEpisode(series({}))?.number, 150);
  });

  test('progress without a time keeps the first in progress', () {
    final episodes = series({
      152: _episode(152, progress: 0.5),
      160: _episode(160, progress: 0.2),
    });
    expect(nextEpisode(episodes)?.number, 152);
  });

  test('all watched: none', () {
    expect(
        nextEpisode([
          _episode(1, progress: 1, at: earlier),
          _episode(2, progress: 1, at: later),
        ]),
        isNull);
  });
}
