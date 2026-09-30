import 'package:flutter/widgets.dart';
import 'package:nipaplay/models/episode_file_candidate.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/episode_file_selection_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/media_identity_resolver.dart';
import 'package:provider/provider.dart';

typedef EpisodeFileChooser = Future<EpisodeFileCandidate?> Function(
  List<EpisodeFileCandidate> candidates,
  Future<bool> Function(EpisodeFileCandidate) unmatch,
);

/// Shared by card playback, external players and direct player initialization.
class EpisodeFileSelectionService {
  EpisodeFileSelectionService({
    Future<List<WatchHistoryItem>> Function(int, int)? loadMatches,
    Future<WatchHistoryItem?> Function(String)? loadHistory,
    Future<bool> Function(WatchHistoryItem)? clearMatch,
  })  : _loadMatches =
            loadMatches ?? WatchHistoryManager.getMatchedItemsForEpisode,
        _loadHistory = loadHistory ?? WatchHistoryManager.getHistoryItem,
        _clearMatch = clearMatch ?? WatchHistoryManager.clearMatchInfoForFile;

  final Future<List<WatchHistoryItem>> Function(int, int) _loadMatches;
  final Future<WatchHistoryItem?> Function(String) _loadHistory;
  final Future<bool> Function(WatchHistoryItem) _clearMatch;

  static Future<PlayableItem?> select(
    BuildContext context,
    PlayableItem requested, {
    bool Function()? isCancelled,
  }) async {
    try {
      return await EpisodeFileSelectionService().resolve(
        requested,
        isCancelled: () => !context.mounted || (isCancelled?.call() ?? false),
        choose: (candidates, unmatch) => EpisodeFileSelectionDialog.show(
          context: context,
          candidates: candidates,
          onUnmatch: (candidate) async {
            final changed = await unmatch(candidate);
            if (changed && context.mounted) {
              WatchHistoryProvider? provider;
              try {
                provider = context.read<WatchHistoryProvider>();
              } on ProviderNotFoundException {
                // The resolver also works outside the media library subtree.
              }
              try {
                await provider?.refresh();
              } catch (error) {
                // Persistence already succeeded; a refresh must not undo the UI.
                debugPrint('解除匹配后刷新媒体库失败: $error');
              }
            }
            return changed;
          },
        ),
      );
    } catch (error) {
      debugPrint('读取剧集匹配文件失败: $error');
      if (context.mounted && !(isCancelled?.call() ?? false)) {
        BlurSnackBar.show(context, '读取剧集匹配文件失败，请重试');
      }
      return null;
    }
  }

  Future<PlayableItem?> resolve(
    PlayableItem requested, {
    required EpisodeFileChooser choose,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    if (cancelled()) return null;
    final stored = await _loadHistory(requested.videoPath);
    final history = requested.historyItem ?? stored;
    if (cancelled()) return null;
    final animeId = requested.animeId ?? history?.animeId;
    final episodeId = requested.episodeId ?? history?.episodeId;
    if (animeId == null || episodeId == null) return requested;
    if (requested.animeId == null &&
        (history == null || history.animeName.trim().isEmpty)) {
      return requested;
    }

    final matches = await _loadMatches(animeId, episodeId);
    if (cancelled()) return null;
    final byIdentity = <String, EpisodeFileCandidate>{};
    for (final match in matches) {
      if (match.animeId != animeId ||
          match.episodeId != episodeId ||
          match.animeName.trim().isEmpty ||
          match.filePath.trim().isEmpty) {
        continue;
      }
      final candidate = EpisodeFileCandidate(match);
      byIdentity.putIfAbsent(candidate.identity, () => candidate);
    }
    if (byIdentity.isEmpty) {
      return stored != null && stored.animeName.trim().isEmpty
          ? null
          : requested;
    }
    if (byIdentity.length == 1) {
      final only = byIdentity.values.single;
      return MediaIdentityResolver.samePath(
              only.history.filePath, requested.videoPath)
          ? requested
          : only.toPlayable(requested);
    }

    final selected =
        await choose(byIdentity.values.toList(), (candidate) async {
      // A stable URI and an old proxy URL can refer to the same video file.
      final aliases = matches.where((match) =>
          EpisodeFileCandidate(match).identity == candidate.identity);
      for (final alias in aliases) {
        if (!await _clearMatch(alias)) return false;
      }
      return true;
    });
    if (cancelled() || selected == null) return null;
    // Re-read after an asynchronous dialog so a stale/unlinked file cannot play.
    final remaining = await _loadMatches(animeId, episodeId);
    if (cancelled()) return null;
    for (final match in remaining) {
      if (match.animeId == animeId &&
          match.episodeId == episodeId &&
          match.animeName.trim().isNotEmpty &&
          EpisodeFileCandidate(match).identity == selected.identity) {
        return EpisodeFileCandidate(match).toPlayable(requested);
      }
    }
    return null;
  }
}
