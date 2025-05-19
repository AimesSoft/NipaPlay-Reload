import 'dart:typed_data';

class PlayerFrame {
  final int width;
  final int height;
  final Uint8List bytes;

  PlayerFrame({
    required this.width,
    required this.height,
    required this.bytes,
  });
}

class PlayerVideoCodecParams {
  final int width;
  final int height;
  final String? name;

  PlayerVideoCodecParams({required this.width, required this.height, this.name});
}

class PlayerVideoStreamInfo {
  final PlayerVideoCodecParams codec;
  final String? codecName;

  PlayerVideoStreamInfo({required this.codec, this.codecName});
}

class PlayerSubtitleStreamInfo {
  final String? title;
  final String? language;
  final Map<String, String> metadata;
  final String rawRepresentation; // For mdk.Track.toString() compatibility

  PlayerSubtitleStreamInfo({
    this.title,
    this.language,
    this.metadata = const {},
    required this.rawRepresentation,
  });

  @override
  String toString() => rawRepresentation;
}

class PlayerAudioCodecParams {
  final String? name;
  final int? bitRate;
  final int? channels;
  final int? sampleRate;
  // Add other relevant audio codec parameters if needed

  PlayerAudioCodecParams({
    this.name,
    this.bitRate,
    this.channels,
    this.sampleRate,
  });
}

class PlayerAudioStreamInfo {
  final PlayerAudioCodecParams codec;
  final String? title;
  final String? language;
  final Map<String, String> metadata;
  final String rawRepresentation; // For mdk.Track.toString() compatibility if needed for audio too

  PlayerAudioStreamInfo({
    required this.codec,
    this.title,
    this.language,
    this.metadata = const {},
    required this.rawRepresentation,
  });

  @override
  String toString() => rawRepresentation; // Or a more structured string
}

class PlayerMediaInfo {
  final int duration; // in milliseconds
  final List<PlayerVideoStreamInfo>? video;
  final List<PlayerAudioStreamInfo>? audio;
  final List<PlayerSubtitleStreamInfo>? subtitle;

  PlayerMediaInfo({
    required this.duration,
    this.video,
    this.audio,
    this.subtitle,
  });
} 