import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/video_player_state.dart';

void main() {
  group('preferredPlaybackErrorDetail', () {
    test('prefers a non-empty adapter-specific error', () {
      expect(
        preferredPlaybackErrorDetail(
          specificError: 'unsupported AV3A audio stream',
          mediaLoadError: 'generic media error',
          fallback: Exception('fallback'),
        ),
        'unsupported AV3A audio stream',
      );
    });

    test('ignores empty adapter errors', () {
      expect(
        preferredPlaybackErrorDetail(
          specificError: '  ',
          mediaLoadError: '',
          fallback: Exception('decoder unavailable'),
        ),
        'Exception: decoder unavailable',
      );
    });
  });
}
