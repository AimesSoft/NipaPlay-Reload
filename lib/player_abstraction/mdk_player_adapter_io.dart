import 'package:fvp/mdk.dart' as mdk;
import 'package:flutter/foundation.dart';
import 'dart:typed_data'; // Required for Uint8List
import './abstract_player.dart';
import './player_enums.dart';
import './player_data_models.dart';
import 'dart:async';

// Enum Converters
PlayerPlaybackState _toPlayerPlaybackState(mdk.PlaybackState state) {
  if (state == mdk.PlaybackState.stopped) return PlayerPlaybackState.stopped;
  if (state == mdk.PlaybackState.paused) return PlayerPlaybackState.paused;
  if (state == mdk.PlaybackState.playing) return PlayerPlaybackState.playing;
  return PlayerPlaybackState.stopped; 
}

mdk.PlaybackState _fromPlayerPlaybackState(PlayerPlaybackState state) {
  switch (state) {
    case PlayerPlaybackState.stopped: return mdk.PlaybackState.stopped;
    case PlayerPlaybackState.paused: return mdk.PlaybackState.paused;
    case PlayerPlaybackState.playing: return mdk.PlaybackState.playing;
  }
}

PlayerMediaType _toPlayerMediaType(mdk.MediaType type) {
  switch (type) {
    case mdk.MediaType.unknown: return PlayerMediaType.unknown;
    case mdk.MediaType.video: return PlayerMediaType.video;
    case mdk.MediaType.audio: return PlayerMediaType.audio;
    case mdk.MediaType.subtitle: return PlayerMediaType.subtitle;
    default: throw ArgumentError('Unknown MDK MediaType: $type');
  }
}

mdk.MediaType _fromPlayerMediaType(PlayerMediaType type) {
  switch (type) {
    case PlayerMediaType.unknown: return mdk.MediaType.unknown;
    case PlayerMediaType.video: return mdk.MediaType.video;
    case PlayerMediaType.audio: return mdk.MediaType.audio;
    case PlayerMediaType.subtitle: return mdk.MediaType.subtitle;
    default: throw ArgumentError('Unknown PlayerMediaType: $type');
  }
}

PlayerMediaInfo _toPlayerMediaInfo(mdk.MediaInfo mdkInfo) {
  return PlayerMediaInfo(
    duration: mdkInfo.duration,
    video: mdkInfo.video?.map((v) {
      String? codecNameValue;
      try {
          try {
              dynamic trackCodecName = (v as dynamic).codecName; 
              if (trackCodecName is String && trackCodecName.isNotEmpty) {
                  codecNameValue = trackCodecName;
              }
          } catch (_) {}

          if (codecNameValue == null) {
              codecNameValue = v.codec.toString();
              if (codecNameValue.startsWith('Instance of')) {
                  codecNameValue = 'Unknown Codec';
              }
          }
            } catch (e) {
        codecNameValue = 'Error Retrieving Codec';
      }
      return PlayerVideoStreamInfo(
        codec: PlayerVideoCodecParams(
            width: v.codec.width ?? 0,
            height: v.codec.height ?? 0, 
            name: codecNameValue
        ),
        codecName: codecNameValue, 
      );
    }).toList(),
    subtitle: mdkInfo.subtitle?.map((sMdk) {
      return PlayerSubtitleStreamInfo(
        title: sMdk.metadata['title'] ?? 'Subtitle track ${mdkInfo.subtitle!.indexOf(sMdk)}',
        language: sMdk.metadata['language'] ?? 'unknown',
        metadata: sMdk.metadata,
        rawRepresentation: sMdk.toString(),
      );
    }).toList(),
    audio: mdkInfo.audio?.map<PlayerAudioStreamInfo>((aMdk) {
      String? codecNameValue;
      int? bitRate;
      int? channels;
      int? sampleRate;
      String? title;
      String? language;
      Map<String, String> metadata = {};
      String rawRepresentation = 'Unknown Audio Track';

      try {
        rawRepresentation = aMdk.toString();
        dynamic mdkAudioCodec = (aMdk as dynamic)?.codec;

        if (mdkAudioCodec != null) {
          try {
            dynamic codecNameProp = (mdkAudioCodec as dynamic)?.name;
            if (codecNameProp is String && codecNameProp.isNotEmpty) {
              codecNameValue = codecNameProp;
            } else {
              codecNameValue = mdkAudioCodec.toString();
              if (codecNameValue.startsWith('Instance of')) {
                codecNameValue = 'Unknown Codec';
              }
            }
          } catch (e) {
            codecNameValue = mdkAudioCodec.toString();
            if (codecNameValue.startsWith('Instance of')) {
                codecNameValue = 'Unknown Codec';
            }
          }

          try {
            bitRate = (mdkAudioCodec as dynamic)?.bit_rate as int?;
          } catch (e) { }
          try {
            channels = (mdkAudioCodec as dynamic)?.channels as int?;
          } catch (e) { }
          try {
            sampleRate = (mdkAudioCodec as dynamic)?.sample_rate as int?;
          } catch (e) { }
        }

        try {
            dynamic mdkMetadata = (aMdk as dynamic)?.metadata;
            if (mdkMetadata is Map) {
                 metadata = mdkMetadata.map((key, value) => MapEntry(key.toString(), value.toString()));
                 title = metadata['title'];
                 language = metadata['language'];
            }
        } catch (e) { }

      } catch (e) {
      }
      
      return PlayerAudioStreamInfo(
        codec: PlayerAudioCodecParams(
          name: codecNameValue,
          bitRate: bitRate,
          channels: channels,
          sampleRate: sampleRate,
        ),
        title: title ?? 'Audio track ${mdkInfo.audio!.indexOf(aMdk)}',
        language: language ?? 'unknown',
        metadata: metadata,
        rawRepresentation: rawRepresentation,
      );
    }).toList(),
  );
}

class MdkPlayerAdapter implements AbstractPlayer {
  late mdk.Player _mdkPlayer;
  double _playbackRate = 1.0;

  MdkPlayerAdapter() {
    _mdkPlayer = mdk.Player();
    _applyInitialSettings();
  }

  void _applyInitialSettings() {
    try {
      _mdkPlayer.setProperty('auto_load', '0');
    } catch (e) {
    }
  }

  @override
  double get volume => _mdkPlayer.volume;
  @override
  set volume(double value) => _mdkPlayer.volume = value;
  
  @override
  double get playbackRate => _playbackRate;
  @override
  set playbackRate(double value) {
    _playbackRate = value;
    try {
      _mdkPlayer.setProperty('speed', value.toString());
    } catch (e) {
    }
  }

  @override
  PlayerPlaybackState get state => _toPlayerPlaybackState(_mdkPlayer.state);
  @override
  set state(PlayerPlaybackState value) => _mdkPlayer.state = _fromPlayerPlaybackState(value);

  @override
  ValueListenable<int?> get textureId => _mdkPlayer.textureId;

  @override
  String get media => _mdkPlayer.media;
  @override
  set media(String value) {
    if (value.isNotEmpty && _mdkPlayer.media != value) {
      List<String> videoDecoders = [];
      List<String> audioDecoders = [];
      try {
        videoDecoders = getDecoders(PlayerMediaType.video);
        audioDecoders = getDecoders(PlayerMediaType.audio);
      } catch (e) {
      }
      
      try {
        _mdkPlayer.dispose();
      } catch (e) {
      }
      
      _mdkPlayer = mdk.Player(); 
      _applyInitialSettings(); 

      try {
        if (videoDecoders.isNotEmpty) {
          setDecoders(PlayerMediaType.video, videoDecoders);
        }
        if (audioDecoders.isNotEmpty) {
          setDecoders(PlayerMediaType.audio, audioDecoders);
        }
      } catch (e) {
      }

    } else if (value.isEmpty && _mdkPlayer.media.isNotEmpty) {
      _mdkPlayer.state = mdk.PlaybackState.stopped;
      _mdkPlayer.setMedia("", mdk.MediaType.video);
    }

    _mdkPlayer.media = value;
  }

  @override
  PlayerMediaInfo get mediaInfo => _toPlayerMediaInfo(_mdkPlayer.mediaInfo);

  @override
  List<int> get activeSubtitleTracks => _mdkPlayer.activeSubtitleTracks;
  @override
  set activeSubtitleTracks(List<int> value) => _mdkPlayer.activeSubtitleTracks = value;

  @override
  List<int> get activeAudioTracks => _mdkPlayer.activeAudioTracks;
  @override
  set activeAudioTracks(List<int> value) => _mdkPlayer.activeAudioTracks = value;

  @override
  int get position => _mdkPlayer.position;

  @override
  bool get supportsExternalSubtitles => true;

  @override
  Future<int?> updateTexture() {
    try {
      final originalFuture = _mdkPlayer.updateTexture();
      return originalFuture.timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('Texture update timed out for ${_mdkPlayer.media}');
      });
    } catch (e) {
      rethrow;
    }
  }

  @override
  void setMedia(String path, PlayerMediaType type) => _mdkPlayer.setMedia(path, _fromPlayerMediaType(type));

  @override
  Future<void> prepare() async {
    try {
      _mdkPlayer.prepare(); 
    } catch (e) {
      rethrow;
    }
  }

  @override
  void seek({required int position}) {
    _mdkPlayer.seek(position: position); 
  }

  @override
  void dispose() => _mdkPlayer.dispose();

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    final Uint8List? frameBytes = await _mdkPlayer.snapshot(width: width, height: height);
    if (frameBytes == null) {
      if (width <= 0) width = 128;
      if (height <= 0) height = 72;
      final int numBytes = width * height * 4;
      final Uint8List blackBytes = Uint8List(numBytes);
      for (int i = 3; i < numBytes; i += 4) {
        blackBytes[i] = 255;
      }
      return PlayerFrame(width: width, height: height, bytes: blackBytes);
    }
    return PlayerFrame(
      width: width,
      height: height,
      bytes: frameBytes,
    );
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    _mdkPlayer.setDecoders(_fromPlayerMediaType(type), decoders);
  }

  @override
  List<String> getDecoders(PlayerMediaType type) {
    String decodersString = "";
    if (type == PlayerMediaType.video) {
      decodersString = _mdkPlayer.getProperty("video.decoders") ?? "";
    } else if (type == PlayerMediaType.audio) {
      decodersString = _mdkPlayer.getProperty("audio.decoders") ?? "";
    }
    if (decodersString.isEmpty) return [];
    return decodersString.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  @override
  String? getProperty(String key) {
    return _mdkPlayer.getProperty(key);
  }

  @override
  void setProperty(String key, String value) {
    _mdkPlayer.setProperty(key, value);
  }

  @override
  Future<void> playDirectly() async {
    try {
      _mdkPlayer.state = mdk.PlaybackState.playing;
        } catch (e) {
    }
  }
  
  @override
  Future<void> pauseDirectly() async {
    try {
      _mdkPlayer.state = mdk.PlaybackState.paused;
        } catch (e) {
    }
  }

  @override
  void setPlaybackRate(double rate) {
    playbackRate = rate;
  }
} 