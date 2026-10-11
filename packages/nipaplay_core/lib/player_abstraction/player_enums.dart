enum PlayerPlaybackState {
  stopped,
  paused,
  playing,
}

enum PlayerMediaType {
  unknown,
  video,
  audio,
  subtitle,
}

// PlayerSeekFlag removed as its usage with MDK is unclear and VideoPlayerState uses defaults. 