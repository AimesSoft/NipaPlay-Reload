import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/decoder_manager.dart';

void main() {
  group('platform decoder defaults', () {
    test('HarmonyOS prefers the native OH decoder', () {
      expect(
        platformDefaultDecodersForOperatingSystem('ohos'),
        ['OH', 'FFmpeg', 'dav1d'],
      );
    });

    test('mainline platform defaults remain unchanged', () {
      expect(
        platformDefaultDecodersForOperatingSystem('android'),
        ['AMediaCodec', 'MediaCodec', 'dav1d', 'FFmpeg'],
      );
      expect(
        platformDefaultDecodersForOperatingSystem('ios'),
        ['VT', 'hap', 'dav1d', 'FFmpeg'],
      );
      expect(
        platformDefaultDecodersForOperatingSystem('macos'),
        ['VT', 'hap', 'dav1d', 'FFmpeg'],
      );
      expect(
        platformDefaultDecodersForOperatingSystem('unsupported'),
        ['FFmpeg'],
      );
    });
  });

  group('HarmonyOS saved decoder migration', () {
    test('restores OH before a legacy FFmpeg-only preference', () {
      expect(
        applyDecoderPreferenceForOperatingSystem(
          operatingSystem: 'ohos',
          decoders: ['FFmpeg'],
          preferHardware: true,
        ),
        ['OH', 'FFmpeg'],
      );
    });

    test('keeps software first when hardware decoding is disabled', () {
      expect(
        applyDecoderPreferenceForOperatingSystem(
          operatingSystem: 'ohos',
          decoders: ['FFmpeg', 'dav1d'],
          preferHardware: false,
        ),
        ['FFmpeg', 'dav1d', 'OH'],
      );
    });

    test('does not duplicate an existing OH candidate', () {
      expect(
        applyDecoderPreferenceForOperatingSystem(
          operatingSystem: 'ohos',
          decoders: ['OH', 'FFmpeg', 'dav1d'],
          preferHardware: true,
        ),
        ['OH', 'FFmpeg', 'dav1d'],
      );
    });

    test('does not add OH on mainline platforms', () {
      for (final operatingSystem in [
        'android',
        'ios',
        'macos',
        'windows',
        'linux',
      ]) {
        expect(
          applyDecoderPreferenceForOperatingSystem(
            operatingSystem: operatingSystem,
            decoders: ['FFmpeg'],
            preferHardware: true,
          ),
          ['FFmpeg'],
          reason: operatingSystem,
        );
      }
    });
  });
}
