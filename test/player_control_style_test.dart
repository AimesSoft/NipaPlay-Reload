import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/control_shadow.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shadow_action_button.dart';

void main() {
  test('top action buttons match the 28px back icon', () {
    final button = ShadowActionButton(
      tooltip: 'test',
      icon: Icons.share,
      onPressed: () {},
    );

    expect(button.iconSize, 28);
    expect(button.padding, const EdgeInsets.all(8));
  });

  test('player icon shadows stay centered on the glyph', () {
    const shadow = ControlIconShadow(child: SizedBox.shrink());

    expect(shadow.shadows, isNotEmpty);
    expect(
      shadow.shadows.every((item) => item.offset == Offset.zero),
      isTrue,
    );
  });

  test('portrait controls rebuild unscaled and danmaku keeps phone size', () {
    final player = File('lib/pages/play_video_page.dart').readAsStringSync();

    expect(
      player,
      contains('key: ValueKey<bool>(portraitUiScale < 0.999)'),
    );
    expect(
      player,
      contains('isCompactPortrait ? 1.0 : portraitUiScale'),
    );
    expect(
      RegExp(r'scale: topControlsScale').allMatches(player).length,
      2,
    );
    expect(player, contains('const Positioned.fill('));
    expect(player, contains('child: VideoPlayerWidget()'));
    expect(
      player,
      isNot(contains('VideoPlayerWidget(danmakuScale: portraitUiScale)')),
    );
  });
}
