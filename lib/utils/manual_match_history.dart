import 'package:nipaplay/models/watch_history_model.dart';
import 'package:path/path.dart' as p;

/// 手动匹配弹幕（单个或批量）后写回的观看记录。
///
/// [source] 是该文件现有的记录；批量匹配时也可能是已解除匹配的旧路径记录。
/// 进度、缩略图、哈希都沿用 [source]。
///
/// 没有任何记录说明文件从未播放过：扫描时没匹配上的文件不会建记录。
/// 这种新记录必须标成扫描项，否则未播放的条目会被当成播放产生的记录，
/// 媒体库详情页显示成“共享媒体”而不是“未播放”（#1047）。
WatchHistoryItem buildManualMatchHistoryItem({
  required String filePath,
  required String fileName,
  required int? animeId,
  required int? episodeId,
  required String animeTitle,
  required String episodeTitle,
  WatchHistoryItem? source,
  DateTime? now,
}) {
  return WatchHistoryItem(
    filePath: filePath,
    animeName: animeTitle.isNotEmpty
        ? animeTitle
        : (source?.animeName ?? p.basenameWithoutExtension(fileName)),
    episodeTitle: episodeTitle.isNotEmpty ? episodeTitle : source?.episodeTitle,
    episodeId: episodeId,
    animeId: animeId,
    watchProgress: source?.watchProgress ?? 0.0,
    lastPosition: source?.lastPosition ?? 0,
    duration: source?.duration ?? 0,
    lastWatchTime: now ?? DateTime.now(),
    thumbnailPath: source?.thumbnailPath,
    isFromScan: source?.isFromScan ?? true,
    videoHash: source?.videoHash,
  );
}
