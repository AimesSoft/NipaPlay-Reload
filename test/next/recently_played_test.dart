import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui_data/recently_played.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

void main() {
  test(
      'recent playback uses latest episode per work, including completed works',
      () {
    const a = UiWork(workId: 'a', title: 'A');
    const b = UiWork(workId: 'b', title: 'B');
    const old = UiEpisode(episodeId: 'a1', workId: 'a', number: 1);
    const latest =
        UiEpisode(episodeId: 'a2', workId: 'a', number: 2, progress: 1);
    const other = UiEpisode(episodeId: 'b1', workId: 'b', number: 1);
    final shelf = recentlyPlayedShelf([
      (a, old, DateTime.parse('2026-10-26T20:00:00+08:00')),
      (b, other, DateTime.parse('2026-10-26T13:00:00Z')),
      (a, latest, DateTime.parse('2026-10-26T22:00:00+08:00')),
    ])!;
    expect(shelf.title, '最近播放');
    expect(shelf.items.map((i) => i.work.workId), ['a', 'b']);
    expect(shelf.items.first.episode, same(latest));
    expect(shelf.items.first.caption, '第 2 集');
    expect(latest.resumePosition, Duration.zero);
    expect(recentlyPlayedShelf([]), isNull);
  });
}
