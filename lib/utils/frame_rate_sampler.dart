/// Measures rendered-frame cadence using engine timestamps, independently of
/// how FrameTiming reports are batched or delayed on their way to Dart.
class FrameRateSampler {
  int? _windowStartUs;
  int? _previousUs;
  int _intervals = 0;

  double fps = 0;

  void addTimestamp(int timestampUs) {
    final previousUs = _previousUs;
    if (previousUs == null) {
      _windowStartUs = timestampUs;
      _previousUs = timestampUs;
      return;
    }
    // Duplicate/out-of-order reports cannot create extra frame intervals.
    if (timestampUs <= previousUs) return;

    _previousUs = timestampUs;
    _intervals++;
    final spanUs = timestampUs - _windowStartUs!;
    if (spanUs >= 1000000) {
      fps = _intervals * 1000000 / spanUs;
      _windowStartUs = timestampUs;
      _intervals = 0;
    }
  }

  void reset() {
    _windowStartUs = null;
    _previousUs = null;
    _intervals = 0;
    fps = 0;
  }
}
