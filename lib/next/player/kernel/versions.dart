import 'package:flutter/foundation.dart';

/// What this build links of the two kernels that cannot say their own
/// version: Erika's plugin and the liberika commit its git dependency is
/// locked to, and video_player with the platform backend that plays. They
/// are the locked versions in `pubspec.lock`; a test holds them to it.
const erikaFlutterVersion = '0.2.1';
const liberikaRef = '230666bc58981847af611a3addf3d372904151c0';
const videoPlayerVersion = '2.9.5';
const videoPlayerAvfoundationVersion = '2.8.9';

Map<String, String> erikaVersion() =>
    {'erika_flutter': erikaFlutterVersion, 'liberika': liberikaRef};

Map<String, String> videoPlayerVersions() => {
      'video_player': videoPlayerVersion,
      if (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS)
        'video_player_avfoundation': videoPlayerAvfoundationVersion,
    };
