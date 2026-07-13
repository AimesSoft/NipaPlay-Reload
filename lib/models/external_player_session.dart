/// Information about the external player session shown in the console.
class ExternalPlayerSession {
  const ExternalPlayerSession({
    required this.playerPath,
    required this.mediaPath,
    required this.processId,
    this.animeTitle,
    this.episodeTitle,
    this.episodeId,
    this.ipcPath,
  });

  final String playerPath;
  final String mediaPath;
  final int processId;
  final String? animeTitle;
  final String? episodeTitle;
  final int? episodeId;
  final String? ipcPath;
}

/// Playback state read from an external player's control channel.
class ExternalPlayerPlaybackProgress {
  const ExternalPlayerPlaybackProgress({
    required this.position,
    required this.duration,
    this.isPaused = false,
  });

  final Duration position;
  final Duration duration;
  final bool isPaused;

  double? get fraction {
    if (duration <= Duration.zero) return null;
    return (position.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}
