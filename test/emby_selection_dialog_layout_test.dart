import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/emby_media_selection_dialog.dart';

void main() {
  test('caps a large desktop dialog', () {
    final metrics = calculateEmbySelectionDialogMetrics(const Size(1920, 1080));

    expect(metrics.maxWidth, 860);
    expect(metrics.maxHeightFactor, closeTo(760 / 1080, 0.0001));
  });

  test('scales continuously for a normal window', () {
    final metrics = calculateEmbySelectionDialogMetrics(const Size(1024, 768));

    expect(metrics.maxWidth, closeTo(1024 * 0.72, 0.0001));
    expect(metrics.maxHeightFactor, closeTo(0.78, 0.0001));
  });

  test('leaves small-window safety margins to the window scaffold', () {
    final metrics = calculateEmbySelectionDialogMetrics(const Size(600, 480));

    expect(metrics.maxWidth, 680);
    expect(metrics.maxHeightFactor, 1);
  });

  test('handles an unavailable window size without invalid values', () {
    final metrics = calculateEmbySelectionDialogMetrics(Size.zero);

    expect(metrics.maxWidth, 0);
    expect(metrics.maxHeightFactor, 0);
  });
}
