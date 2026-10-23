import 'package:nipa_harness/nipa_harness.dart';

import '../core/session.dart';
import '../kernel/driver.dart';
import 'kernel_features.dart';

final class PlaybackNavigation {
  const PlaybackNavigation();

  JsonMap chapters(PlaybackSession session) {
    final chapters = session.media.value?.chapters ?? const <ChapterFacts>[];
    final at = session.position.inMilliseconds;
    // Binary search; capabilities and UI never scan a growing chapter list.
    var lo = 0, hi = chapters.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (chapters[mid].startMs <= at) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return {
      'sessionId': session.id,
      'items': [for (final c in chapters) c.toJson()],
      'index': lo - 1,
      'source': 'kernel',
      'skipSegments': const [],
      'activeSkipKind': null
    };
  }

  Future<JsonMap> navigate(
      PlaybackSession s, JsonMap input, String origin) async {
    if (!s.phase.value.open) {
      throw const Failure(FailureCode.unavailable, 'No open video session.');
    }
    if (input['chapterIndex'] case final int index) {
      final chapters = s.media.value?.chapters ?? const <ChapterFacts>[];
      if (index < 0 || index >= chapters.length) {
        throw const Failure(
            FailureCode.invalidInput, 'Chapter index out of range.');
      }
      final receipt = await s.seek(
          Duration(milliseconds: chapters[index].startMs),
          origin: origin);
      return {
        'commandStatus': receipt.applied ? 'accepted' : receipt.outcome,
        'method': 'chapter',
        'receipt': receipt.toJson()
      };
    }
    if (input['frameDelta'] case final int delta) {
      if (delta != -1 && delta != 1) {
        throw const Failure(
            FailureCode.invalidInput, 'frameDelta must be -1 or +1.');
      }
      await s.setPaused(true, origin: origin);
      if (s.phase.value.done) throw const KernelFenced();
      final driver = s.driver;
      if (driver is KernelFrameFeatures) {
        final outcome = await (driver as KernelFrameFeatures).stepFrame(delta);
        if (s.phase.value.done) throw const KernelFenced();
        if (outcome.landed case final landed?) {
          s.clock.anchor(landed, advancing: false, source: 'native_frame_step');
        }
        return {
          'commandStatus':
              outcome.result == SeekResult.done ? 'accepted' : 'rejected',
          'method': 'native_frame_step',
          'landedMs': outcome.landed?.inMilliseconds
        };
      }
      // Drivers without a frame primitive use the reported frame interval,
      // with exact seeking. The result names the method rather than claiming
      // a native frame step (especially for variable-frame-rate media).
      final fps = s.media.value?.frameRate;
      if (fps == null || !fps.isFinite || fps <= 0) {
        throw const Failure(
            FailureCode.unavailable, 'The media reports no frame rate.');
      }
      final receipt = await s.seek(
          s.position + Duration(microseconds: (delta * 1e6 / fps).round()),
          origin: origin);
      return {
        'commandStatus': receipt.applied ? 'accepted' : receipt.outcome,
        'method': 'reported_frame_interval_seek',
        'fps': fps,
        'receipt': receipt.toJson()
      };
    }
    throw const Failure(FailureCode.unavailable,
        'Requested skip segment is not active at this position.');
  }
}
