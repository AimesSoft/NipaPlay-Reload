import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/danmaku/style.dart';

void main() {
  test('uses the expected default danmaku style', () {
    final style = DanmakuStyle();

    expect(style.opacity, 1.0);
    expect(style.outlineWidth, 1.0);
    expect(style.outlineEnabled, isTrue);
  });

  test('copyWith only replaces the selected danmaku style fields', () {
    final style = DanmakuStyle(
      opacity: 0.8,
      outlineWidth: 2.5,
      outlineEnabled: true,
    );

    final updated = style.copyWith(
      opacity: 0.5,
      outlineEnabled: false,
    );

    expect(updated.opacity, 0.5);
    expect(updated.outlineWidth, 2.5);
    expect(updated.outlineEnabled, isFalse);
    expect(updated, DanmakuStyle(
      opacity: 0.5,
      outlineWidth: 2.5,
      outlineEnabled: false,
    ));
  });

  test('normalizes danmaku style values', () {
    final style = DanmakuStyle(
      opacity: -0.5,
      outlineWidth: 8.0,
    );

    expect(style.opacity, DanmakuStyle.minOpacity);
    expect(style.outlineWidth, DanmakuStyle.maxOutlineWidth);

    final normalized = style.copyWith(
      opacity: double.nan,
      outlineWidth: double.infinity,
    );

    expect(normalized.opacity, DanmakuStyle.maxOpacity);
    expect(normalized.outlineWidth, 1.0);
  });

  test('setters normalize and update danmaku style values', () {
    final style = DanmakuStyle();

    style.opacity = 1.5;
    style.outlineWidth = 0.1;
    style.outlineEnabled = false;

    expect(style.opacity, DanmakuStyle.maxOpacity);
    expect(style.outlineWidth, DanmakuStyle.minOutlineWidth);
    expect(style.outlineEnabled, isFalse);
  });
}
