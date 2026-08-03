import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/build_target_label_common.dart';

void main() {
  test('formats the Apple TV build target with its operating system', () {
    expect(
      buildTargetLabelFromParts(
        architecture: 'iosArm64',
        platform: 'tvos',
      ),
      'Arm64 AppleTV OS',
    );
  });
}
