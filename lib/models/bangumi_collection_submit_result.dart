class BangumiCollectionSubmitResult {
  final int rating;
  final int collectionType;
  final String comment;
  final int episodeStatus;

  /// The short-comment editor explicitly requests a watched-state update.
  final bool markAsWatched;

  const BangumiCollectionSubmitResult({
    required this.rating,
    required this.collectionType,
    required this.comment,
    required this.episodeStatus,
    this.markAsWatched = false,
  });
}
