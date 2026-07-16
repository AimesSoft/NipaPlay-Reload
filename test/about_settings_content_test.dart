import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sponsor acknowledgements render without badge containers', () {
    final source = File(
      'lib/settings/pages/about_settings_content.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf('Widget _buildAcknowledgementItem(');
    final methodEnd = source.indexOf(
      '\n  Future<void> _loadVersion()',
      methodStart,
    );

    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));

    final method = source.substring(methodStart, methodEnd);
    expect(method, contains('return Row('));
    expect(method, isNot(contains('Container(')));
    expect(method, isNot(contains('BoxDecoration(')));
    expect(method, isNot(contains('BorderRadius.')));
  });

  test('update action changes color and scales only while hovered', () {
    final source = File(
      'lib/settings/pages/about_settings_content.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf('Widget _buildCanvasUpdateAction(');
    final methodEnd = source.indexOf(
      '\n  Widget _buildCanvasRichText(',
      methodStart,
    );

    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));

    final method = source.substring(methodStart, methodEnd);
    expect(method, contains('Color.lerp('));
    expect(method, contains('secondaryColor,'));
    expect(method, contains('accentColor,'));
    expect(method, contains('AnimatedScale('));
    expect(method, contains('scale: isHovered ? 1.08 : 1'));
    expect(method, contains('TweenAnimationBuilder<double>('));
    expect(
      method.indexOf('Padding('),
      lessThan(method.indexOf('AnimatedScale(')),
    );
  });
}
