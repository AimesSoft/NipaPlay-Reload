import 'ui_data.dart';

/// The last episode played in each work, including completed episodes.
UiShelf? recentlyPlayedShelf(
    Iterable<(UiWork, UiEpisode, DateTime)> observations) {
  final ordered = observations.toList()..sort((a, b) => b.$3.compareTo(a.$3));
  final seen = <String>{};
  final items = <UiShelfItem>[];
  for (final (work, episode, _) in ordered) {
    if (!seen.add(work.workId)) continue;
    items.add(UiShelfItem(work,
        episode: episode,
        caption: work.film || episode.number == null
            ? null
            : '第 ${episode.number} 集'));
    if (items.length == 20) break;
  }
  return items.isEmpty
      ? null
      : UiShelf(
          id: 'recently-played',
          title: '最近播放',
          kind: UiShelfKind.recentlyPlayed,
          items: items);
}
