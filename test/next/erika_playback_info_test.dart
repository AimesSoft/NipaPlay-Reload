import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/player/erika_playback_info.dart';

void main() {
  test('selected model shows its actual inactive backend and reason', () {
    final rows = erikaPlaybackInfoRows({
      'upscalerStatus': {
        'requestedMode': 'artCnnC4F16',
        'activeBackend': 'inactive',
        'upscaledFrames': 0,
        'lastGpuMicros': 0,
        'fallbackCount': 0,
      },
      'diagnostics': {
        'upscaler': {'reason': 'Output size does not require upscaling'},
      },
    });
    expect(rows, contains(('超分模式', 'ArtCNN C4F16')));
    expect(rows, contains(('超分后端', '未激活')));
    expect(rows, contains(('超分帧数', '0')));
    expect(rows, contains(('超分说明', 'Output size does not require upscaling')));
    expect(rows.any((r) => r.$1 == '超分 GPU'), isFalse);
  });

  test('running upscaler exposes native counters and timing', () {
    final rows = erikaPlaybackInfoRows({
      'upscalerStatus': {
        'requestedMode': 'artCnnC4F32',
        'activeBackend': 'cooperativeMatrix',
        'upscaledFrames': 720,
        'lastEncodeMicros': 120,
        'lastGpuMicros': 2500,
        'fallbackCount': 1,
      },
    });
    expect(rows, contains(('超分后端', 'Cooperative Matrix')));
    expect(rows, contains(('超分帧数', '720')));
    expect(rows, contains(('超分 GPU', '2.50 ms')));
    expect(rows, contains(('超分回退', '1 次')));
  });

  test('Windows decoder comes from native diagnostics without event payload',
      () {
    expect(
        erikaDecoderLabel({
          'decoder': null,
          'diagnostics': {
            'decoder': {'activeBackend': 'd3d11va'}
          },
        }),
        'D3D11VA');
    expect(
        erikaDecoderLabel({
          'decoder': {'activeBackend': 'd3d11va'},
          'diagnostics': {
            'decoder': {'activeBackend': 'software'}
          },
        }),
        'FFmpeg (software)');
  });
}
