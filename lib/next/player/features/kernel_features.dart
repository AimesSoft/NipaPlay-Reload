import 'dart:typed_data';

import '../kernel/driver.dart';

/// Optional native frame primitives. Implementations use the same fenced
/// command queue as transport commands; no native handle reaches the UI.
abstract interface class KernelFrameFeatures
    implements KernelFrameStep, KernelPictureSnapshot {}

/// A kernel that steps one frame itself. One that does not is not asked: the
/// navigation seeks by the frame interval the media reports and says so.
abstract interface class KernelFrameStep {
  Future<SeekOutcome> stepFrame(int delta);
}

/// A kernel that gives back the picture it has drawn, with what it draws
/// itself (its subtitles) in it.
abstract interface class KernelPictureSnapshot {
  Future<KernelPicture> snapshotPicture();
}

final class KernelPicture {
  const KernelPicture(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;
}

final class ChapterFacts {
  const ChapterFacts(this.title, this.startMs, {this.endMs});
  final String title;
  final int startMs;
  final int? endMs;

  Map<String, Object?> toJson() => {
        'title': title,
        'startMs': startMs,
        if (endMs != null) 'endMs': endMs,
      };
}
