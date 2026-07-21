import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/video_player_state.dart';

void main() {
  test('timeline preview is isolated to the MDK playback kernel', () {
    expect(
      supportsTimelinePreviewForKernel(PlayerKernelType.mdk),
      isTrue,
    );
    expect(
      supportsTimelinePreviewForKernel(PlayerKernelType.mediaKit),
      isFalse,
      reason: 'The MDK preference must not create a libmpv preview player.',
    );
    expect(
      supportsTimelinePreviewForKernel(PlayerKernelType.videoPlayer),
      isFalse,
    );
    expect(
      supportsTimelinePreviewForKernel(PlayerKernelType.erika),
      isFalse,
    );
  });
}
