import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';

void main() {
  test('the subtitle settings reach Erika as one style', () {
    final style = erikaSubtitleStyleFromMpv({
      'sub-color': '#FFEE00',
      'sub-border-color': '#000000',
      'sub-opacity': '128',
      'sub-border-size': '2.5',
      'sub-shadow-offset': '1.0',
      'sub-bold': 'yes',
      'sub-italic': 'no',
      'sub-align-x': 'left',
      'sub-align-y': 'top',
      'sub-margin-x': '40',
      'sub-margin-y': '24',
      'sub-font': 'PingFang SC',
      'sub-ass-override': 'no',
    });
    expect(style['primaryColorRgba'], 0xFFEE0080);
    expect(style['outlineColorRgba'], 0x00000080);
    expect(style['outlineWidth'], 2.5);
    expect(style['shadowDepth'], 1.0);
    expect(style['bold'], isTrue);
    expect(style['italic'], isFalse);
    expect(style['alignment'], 7);
    expect([style['marginLeft'], style['marginRight'], style['marginVertical']],
        [40, 40, 24]);
    // The font is the custom style's, as on the other kernels.
    expect(style['fontFamily'], '');
    expect(style['overrideMask'], 0);
  });

  test('alignment follows the ASS numpad', () {
    int at(String x, String y) => erikaSubtitleStyleFromMpv(
        {'sub-align-x': x, 'sub-align-y': y})['alignment'] as int;
    expect(at('center', 'bottom'), 2);
    expect(at('right', 'center'), 6);
    expect(at('left', 'bottom'), 1);
  });

  test('the custom style sets the font and pushes the style onto ASS', () {
    final named = erikaSubtitleStyleFromMpv(
        {'sub-font': 'Source Han Sans', 'sub-ass-override': 'force'});
    expect(named['fontFamily'], 'Source Han Sans');
    expect(named['fontFilePath'], '');
    expect(named['overrideMask'], kErikaSubtitleOverrideAll);
    final file = erikaSubtitleStyleFromMpv(
        {'sub-font': 'Source Han Sans', 'sub-ass-override': 'force'},
        fontFile: '/fonts/Source Han Sans.otf');
    expect(file['fontFamily'], '');
    expect(file['fontFilePath'], '/fonts/Source Han Sans.otf');
  });

  test('what was never set is left as Erika has it', () {
    final style = erikaSubtitleStyleFromMpv({});
    expect(style['primaryColorRgba'], isNull);
    expect(style['outlineWidth'], isNull);
    expect(style['bold'], isNull);
    expect(style['marginVertical'], isNull);
  });
}
