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
  // Add other mappings if mdk.PlaybackState has more members that are relevant
  // and PlayerPlaybackState enum is expanded.
  // Default for unhandled MDK states:
  // debugPrint('Warning: Unknown MDK PlaybackState '$state' encountered. Defaulting to stopped.');
  return PlayerPlaybackState.stopped; 
}

mdk.PlaybackState _fromPlayerPlaybackState(PlayerPlaybackState state) {
  switch (state) {
    case PlayerPlaybackState.stopped: return mdk.PlaybackState.stopped;
    case PlayerPlaybackState.paused: return mdk.PlaybackState.paused;
    case PlayerPlaybackState.playing: return mdk.PlaybackState.playing;
    // PlayerPlaybackState is now restricted, so no default needed if all cases covered.
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
    video: mdkInfo.video?.map((v) { // v is mdk.VideoStreamInfo
      String? codecNameValue;
      try {
        // This is the most likely property if it exists directly on VideoCodecParameters
        // Based on typical MDK patterns, there might be a direct name string or a more complex object.
        // If VideoCodecParameters has a specific field like `codec_id_string` or `name`, that would be ideal.
        // The linter previously indicated 'name' is not on VideoCodecParameters.
        // Let's assume VideoStreamInfo (v) itself might have a codec name string, or fallback to codec.toString()
        if (v.codec != null) { // Ensure codec object exists
            try {
                // Check if VideoStreamInfo itself has a 'codec' string property (different from v.codec object)
                // This is a guess based on some player APIs.
                dynamic trackCodecName = (v as dynamic).codecName; 
                if (trackCodecName is String && trackCodecName.isNotEmpty) {
                    codecNameValue = trackCodecName;
                }
            } catch (_) {}

            if (codecNameValue == null) {
                 // Final fallback: use toString() of the VideoCodecParameters object
                codecNameValue = v.codec.toString();
                if (codecNameValue.startsWith('Instance of')) { // A poor toString() impl.
                    codecNameValue = 'Unknown Codec'; // Or try to parse if it contains useful info
                }
            }
        } else {
            codecNameValue = 'Unknown Codec';
        }
      } catch (e) {
        codecNameValue = 'Error Retrieving Codec';
      }
      return PlayerVideoStreamInfo(
        codec: PlayerVideoCodecParams(
            width: v.codec?.width ?? 0, // Add null checks for safety 
            height: v.codec?.height ?? 0, 
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
    audio: mdkInfo.audio?.map<PlayerAudioStreamInfo>((aMdk) { // Explicit type for map
      String? codecNameValue;
      int? bitRate;
      int? channels;
      int? sampleRate;
      String? title;
      String? language;
      Map<String, String> metadata = {};
      String rawRepresentation = 'Unknown Audio Track';

      try {
        rawRepresentation = aMdk.toString(); // Get raw representation first
        dynamic mdkAudioCodec = (aMdk as dynamic)?.codec;

        if (mdkAudioCodec != null) {
          try {
            dynamic codecNameProp = (mdkAudioCodec as dynamic)?.name;
            if (codecNameProp is String && codecNameProp.isNotEmpty) {
              codecNameValue = codecNameProp;
            } else {
              codecNameValue = mdkAudioCodec.toString();
              if (codecNameValue != null && codecNameValue.startsWith('Instance of')) {
                codecNameValue = 'Unknown Codec'; // Simplified fallback
              }
            }
          } catch (e) {
            //debugPrint("Error accessing audio codec name: $e");
            codecNameValue = mdkAudioCodec.toString();
            if (codecNameValue != null && codecNameValue.startsWith('Instance of')) {
                codecNameValue = 'Unknown Codec';
            }
          }

          try {
            bitRate = (mdkAudioCodec as dynamic)?.bit_rate as int?;
          } catch (e) { /* //debugPrint("Error accessing bit_rate: $e"); */ }
          try {
            channels = (mdkAudioCodec as dynamic)?.channels as int?;
          } catch (e) { /* //debugPrint("Error accessing channels: $e"); */ }
          try {
            sampleRate = (mdkAudioCodec as dynamic)?.sample_rate as int?;
          } catch (e) { /* //debugPrint("Error accessing sample_rate: $e"); */ }
        }

        try {
            dynamic mdkMetadata = (aMdk as dynamic)?.metadata;
            if (mdkMetadata is Map) {
                 metadata = mdkMetadata.map((key, value) => MapEntry(key.toString(), value.toString()));
                 title = metadata['title'];
                 language = metadata['language'];
            }
        } catch (e) { /* //debugPrint("Error accessing audio metadata: $e"); */ }

      } catch (e) {
        //debugPrint("Error processing MDK audio track: $e");
        // Defaults are already set
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
  mdk.Player _mdkPlayer;
  double _playbackRate = 1.0; // 添加播放速度状态变量

  MdkPlayerAdapter(mdk.Player initialPlayer) : _mdkPlayer = initialPlayer {
    _applyInitialSettings();
  }

  void _applyInitialSettings() {
    try {
      _mdkPlayer.setProperty('auto_load', '0');
      print('[MdkPlayerAdapter] Applied initial settings. auto_load to false.');
      // Apply any other fixed initial settings here if necessary
    } catch (e) {
      print('[MdkPlayerAdapter] Warning: Could not set MDK auto_load or other properties: $e');
    }
  }

  @override
  double get volume => _mdkPlayer.volume;
  @override
  set volume(double value) => _mdkPlayer.volume = value;
  
  // 添加播放速度属性实现
  @override
  double get playbackRate => _playbackRate;
  @override
  set playbackRate(double value) {
    _playbackRate = value;
    try {
      _mdkPlayer.setProperty('speed', value.toString());
      debugPrint('[MdkPlayerAdapter] 设置播放速度: ${value}x');
    } catch (e) {
      debugPrint('[MdkPlayerAdapter] 设置播放速度失败: $e');
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
      print('[MdkPlayerAdapter] New media detected. Current: "${_mdkPlayer.media}", New: "$value". Disposing and recreating MDK player instance.');
      
      List<String> videoDecoders = [];
      List<String> audioDecoders = [];
      try {
        // Assuming getDecoders works as intended on the AbstractPlayer interface
        videoDecoders = getDecoders(PlayerMediaType.video);
        audioDecoders = getDecoders(PlayerMediaType.audio);
        if (videoDecoders.isNotEmpty || audioDecoders.isNotEmpty) {
            print('[MdkPlayerAdapter] Saved decoders before dispose: Video=${videoDecoders.join(",")}, Audio=${audioDecoders.join(",")}');
        }
      } catch (e) {
        print('[MdkPlayerAdapter] Could not get existing decoders before dispose: $e');
      }
      
      try {
        _mdkPlayer.dispose();
        print('[MdkPlayerAdapter] Old MDK Player instance disposed.');
      } catch (e) {
        print('[MdkPlayerAdapter] Error disposing old MDK Player instance: $e. Proceeding with new instance.');
      }
      
      _mdkPlayer = mdk.Player(); 
      print('[MdkPlayerAdapter] New MDK Player instance created.');
      _applyInitialSettings(); 

      try {
        if (videoDecoders.isNotEmpty) {
          setDecoders(PlayerMediaType.video, videoDecoders); // Use the adapter's setDecoders
          print('[MdkPlayerAdapter] Restored video decoders: ${videoDecoders.join(",")}');
        }
        if (audioDecoders.isNotEmpty) {
          setDecoders(PlayerMediaType.audio, audioDecoders); // Use the adapter's setDecoders
          print('[MdkPlayerAdapter] Restored audio decoders: ${audioDecoders.join(",")}');
        }
      } catch (e) {
         print('[MdkPlayerAdapter] Failed to restore decoders: $e');
      }

    } else if (value.isEmpty && _mdkPlayer.media.isNotEmpty) {
      print('[MdkPlayerAdapter] Clearing media. Current: "${_mdkPlayer.media}". Stopping and setting media to empty.');
      _mdkPlayer.state = mdk.PlaybackState.stopped;
      _mdkPlayer.setMedia("", mdk.MediaType.video);
    }

    _mdkPlayer.media = value;
    if (value.isNotEmpty) {
       print('[MdkPlayerAdapter] Media set to: $value');
    } else {
       print('[MdkPlayerAdapter] Media cleared.');
    }
  }

  @override
  PlayerMediaInfo get mediaInfo => _toPlayerMediaInfo(_mdkPlayer.mediaInfo);

  @override
  List<int> get activeSubtitleTracks => _mdkPlayer.activeSubtitleTracks;
  @override
  set activeSubtitleTracks(List<int> value) => _mdkPlayer.activeSubtitleTracks = value;

  @override
  List<int> get activeAudioTracks => _mdkPlayer.activeAudioTracks; // Assuming mdk.Player has this
  @override
  set activeAudioTracks(List<int> value) => _mdkPlayer.activeAudioTracks = value; // Assuming mdk.Player has this

  @override
  int get position => _mdkPlayer.position;

  @override
  bool get supportsExternalSubtitles => true; // MDK supports this

  @override
  Future<int?> updateTexture() {
    print('[MdkPlayerAdapter] updateTexture() called for media: ${_mdkPlayer.media}');
    try {
      final originalFuture = _mdkPlayer.updateTexture();

      // 添加超时处理，例如10秒
      return originalFuture.timeout(const Duration(seconds: 10), onTimeout: () {
        print('[MdkPlayerAdapter] updateTexture() TIMED OUT for media: ${_mdkPlayer.media}');
        // 超时后，是返回null还是抛出异常取决于你希望如何处理。
        // 返回null可能让VideoPlayerState尝试继续，但可能后续会因textureId为null而失败。
        // 抛出异常会更明确地指示错误。
        throw TimeoutException('Texture update timed out for ${_mdkPlayer.media}');
        // return null; 
      }).then((textureId) {
        print('[MdkPlayerAdapter] updateTexture() completed for media: ${_mdkPlayer.media} with textureId: $textureId');
        return textureId;
      }).catchError((e, s) {
        // TimeoutException 也会被这里捕获
        if (e is TimeoutException) {
          print('[MdkPlayerAdapter] updateTexture() FAILED DUE TO TIMEOUT for media: ${_mdkPlayer.media}. Error: $e');
        } else {
          print('[MdkPlayerAdapter] updateTexture() FAILED for media: ${_mdkPlayer.media}. Error: $e');
        }
        print('[MdkPlayerAdapter] Stacktrace: $s');
        throw e;
      });
    } catch (e, s) {
      print('[MdkPlayerAdapter] updateTexture() threw synchronous FAILED for media: ${_mdkPlayer.media}. Error: $e');
      print('[MdkPlayerAdapter] Stacktrace: $s');
      throw e;
    }
  }

  @override
  void setMedia(String path, PlayerMediaType type) => _mdkPlayer.setMedia(path, _fromPlayerMediaType(type));

  @override
  Future<void> prepare() async {
    print('[MdkPlayerAdapter] prepare() called for media: ${_mdkPlayer.media}'); // 添加当前媒体路径
    try {
      // MDK的prepare方法本身不是async的，但这里我们遵循接口定义为async
      // 如果_mdkPlayer.prepare()是同步的，它会在这个await之前完成或抛出异常
      _mdkPlayer.prepare(); 
      print('[MdkPlayerAdapter] prepare() completed for media: ${_mdkPlayer.media}');
    } catch (e, s) { // 添加堆栈跟踪
      print('[MdkPlayerAdapter] prepare() FAILED for media: ${_mdkPlayer.media}. Error: $e');
      print('[MdkPlayerAdapter] Stacktrace: $s');
      rethrow;
    }
  }

  @override
  void seek({required int position}) {
    // Assuming MDK Player.seek takes a named position argument, based on VideoPlayerState's usage pattern.
    _mdkPlayer.seek(position: position); 
  }

  @override
  void dispose() => _mdkPlayer.dispose();

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    final Uint8List? frameBytes = await _mdkPlayer.snapshot(width: width, height: height);
    if (frameBytes == null) {
      // MDK snapshot failed, return a black frame as per user request
      if (width <= 0) width = 128; // Default black frame width
      if (height <= 0) height = 72; // Default black frame height
      final int numBytes = width * height * 4; // RGBA
      final Uint8List blackBytes = Uint8List(numBytes);
      // For opaque black, set alpha (Uint8List is zero-initialized, so R,G,B are already 0)
      for (int i = 3; i < numBytes; i += 4) {
        blackBytes[i] = 255; // Alpha channel to full opacity
      }
      print("MDKPlayerAdapter: Snapshot failed, returning black frame ${width}x${height}");
      return PlayerFrame(width: width, height: height, bytes: blackBytes);
    }

    // Original logic for successful snapshot
    if (width == 0 || height == 0) {
        // If original call was with 0,0, we don't know MDK's default output size for the frameBytes.
        // Using the video's actual dimensions would be best if frameBytes corresponds to that.
        // However, PlayerFrame requires width & height. For now, this path might be problematic
        // if MDK returns data but width/height were 0. VideoPlayerState seems to always provide w/h.
        print("Warning: Snapshot called with effective width/height 0. Frame dimensions might be incorrect if MDK doesn't default to video size.");
        // To prevent PlayerFrame construction error, ensure width/height are non-zero if frameBytes exist.
        // This is a tricky case: if MDK defaults to video size, we don't have that info here easily.
        // For now, let's assume if width/height are 0 and frameBytes is not null, it's an issue or
        // VideoPlayerState should always provide them.
        // A better solution might be to get actual video dimensions from mediaInfo if available.
    }

    return PlayerFrame(
      width: width, // Should ideally be the actual output width of frameBytes
      height: height, // Should ideally be the actual output height of frameBytes
      bytes: frameBytes,
    );
  }

  // NEWLY IMPLEMENTED METHODS
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
      print('[MDKPlayerAdapter] 直接调用播放方法');
      if (_mdkPlayer != null) {
        _mdkPlayer.state = mdk.PlaybackState.playing;
      }
    } catch (e) {
      print('[MDKPlayerAdapter] 直接播放出错: $e');
    }
  }
  
  @override
  Future<void> pauseDirectly() async {
    try {
      print('[MDKPlayerAdapter] 直接调用暂停方法');
      if (_mdkPlayer != null) {
        _mdkPlayer.state = mdk.PlaybackState.paused;
      }
    } catch (e) {
      print('[MDKPlayerAdapter] 直接暂停出错: $e');
    }
  }

  // 添加setPlaybackRate方法实现
  @override
  void setPlaybackRate(double rate) {
    playbackRate = rate; // 这将调用setter
  }
} 