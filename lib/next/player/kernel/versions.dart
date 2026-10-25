import 'package:flutter/foundation.dart';

/// What this build links of the two kernels that cannot say their own
/// version: Erika's hosted plugin and matching liberika release tag, and
/// video_player with the platform backend that plays. The package versions
/// are locked in `pubspec.lock`; a test holds them to it.
const erikaFlutterVersion = '0.3.0';
const liberikaRef = 'v0.3.0';
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
