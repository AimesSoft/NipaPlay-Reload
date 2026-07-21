import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/external_player_window_service.dart';

void main() {
  group('external player window bounds', () {
    test('uses half the current screen width and preserves aspect ratio', () {
      final result = ExternalPlayerWindowService.calculateHalfWidthBounds(
        currentBounds: const Rect.fromLTWH(200, 120, 1200, 800),
        workArea: const Rect.fromLTWH(0, 24, 1920, 1056),
      );

      expect(result, const Rect.fromLTWH(0, 232, 960, 640));
    });

    test('respects the application minimum size on a small screen', () {
      final result = ExternalPlayerWindowService.calculateHalfWidthBounds(
        currentBounds: const Rect.fromLTWH(0, 0, 800, 800),
        workArea: const Rect.fromLTWH(0, 0, 1000, 700),
      );

      expect(result.width, 600);
      expect(result.height, 600);
      expect(result.left, 0);
      expect(result.top, 50);
    });
  });
}
