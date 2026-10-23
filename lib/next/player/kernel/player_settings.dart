import 'package:nipaplay/player_abstraction/hwdec_type.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/arbiter.dart';
import 'driver.dart';
import 'erika_driver.dart';
import 'mdk_driver.dart';
import 'media_kit_driver.dart';
import 'video_player_driver.dart';

/// The settings a kernel instance is made from (D3: the same preference
/// keys Classic reads), read once when the instance is created and kept as
/// the instance's configuration: another value is another instance (I6).
///
/// Classic's player state is never read; the shared keys are the seam.
final class PlayerSettings {
  PlayerSettings(this.prefs);
  final SharedPreferences prefs;

  /// The registry keys these settings answer for.
  static const keys = {
    'player.kernel',
    'player.useHardwareDecoder',
    'player.hwdecMode',
    'player.softDecodePixelFormat',
    'player.precacheBufferSizeMb',
    'player.precacheBufferDurationSeconds',
    'player.macosNativeVideoEnabled',
    'player.erikaAndroidOutputMode',
    'player.erikaUpscalerMode',
    'player.customUserAgent',
    'network.httpProxy',
  };

  bool get hardware => prefs.getBool('use_hardware_decoder') ?? true;
  HwDecType get hwdecMode => HwDecType.values.firstWhere(
      (m) => m.name == prefs.getString('hwdec_mode'),
      orElse: () => HwDecType.auto);
  String get pixelFormat => prefs.getString('soft_decode_pixel_format') ?? '';
  int get precacheMb =>
      (prefs.getInt('player_precache_buffer_size_mb') ??
              PlayerFactory.defaultPrecacheBufferSizeMb)
          .clamp(PlayerFactory.minPrecacheBufferSizeMb,
              PlayerFactory.maxPrecacheBufferSizeMb);
  int get precacheSeconds =>
      (prefs.getInt('player_precache_buffer_duration_seconds') ?? 4)
          .clamp(1, 120);
  PlayerUpscalerMode get upscaler {
    final index = prefs.getInt('erika_upscaler_mode');
    return index != null &&
            index >= 0 &&
            index < PlayerUpscalerMode.values.length
        ? PlayerUpscalerMode.values[index]
        : PlayerUpscalerMode.off;
  }

  /// What the instance reports as its settings, by registry key, in the
  /// form `settings.get` stores them.
  Map<String, Object?> snapshot(KernelId kernel) => {
        'player.kernel': switch (kernel) {
          KernelId.mdk => 'mdk',
          KernelId.mediaKit => 'mediaKit',
          KernelId.erika => 'erika',
          KernelId.videoPlayer => 'videoPlayer',
        },
        'player.useHardwareDecoder': hardware,
        'player.hwdecMode': hwdecMode.name,
        'player.softDecodePixelFormat': pixelFormat,
        'player.precacheBufferSizeMb': precacheMb,
        'player.precacheBufferDurationSeconds': precacheSeconds,
        'player.macosNativeVideoEnabled':
            PlayerFactory.getMacOSNativeVideoEnabled(),
        'player.erikaAndroidOutputMode':
            PlayerFactory.getErikaAndroidOutputMode().name,
        'player.erikaUpscalerMode': upscaler.name,
        'player.customUserAgent': PlayerFactory.getCustomPlayerUA(),
        'network.httpProxy': PlayerFactory.getHttpProxy(),
      };

  KernelConfig config(KernelId kernel) {
    final proxy = PlayerFactory.getHttpProxy();
    final agent = PlayerFactory.getCustomPlayerUA();
    final settings = Map<String, Object?>.unmodifiable(snapshot(kernel));
    switch (kernel) {
      case KernelId.mdk:
        final mdk = mdkConfigFrom(prefs);
        return KernelConfig(
          kernel: kernel,
          videoDecoders: mdk.videoDecoders,
          hardwareDecoding: mdk.hardwareDecoding,
          bufferMaxMs: mdk.bufferMaxMs,
          settings: settings,
          properties: {
            ...mdk.properties,
            if (proxy.isNotEmpty) ...{
              'avformat.http_proxy': proxy,
              'avio.http_proxy': proxy,
            },
            if (agent.isNotEmpty) ...{
              'avformat.user_agent': agent,
              'avio.user_agent': agent,
            },
          },
        );
      case KernelId.mediaKit:
        return KernelConfig(
          kernel: kernel,
          hardwareDecoding: hardware,
          settings: settings,
          properties: {
            // libmpv's decoder is its hwdec property; software when off.
            'hwdec': hardware ? hwdecMode.hwdec : 'no',
            if (agent.isNotEmpty) 'user-agent': agent,
          },
        );
      case KernelId.erika:
        return KernelConfig(kernel: kernel, settings: settings);
      case KernelId.videoPlayer:
        return KernelConfig(kernel: kernel, settings: settings);
    }
  }

  /// A new instance of [kernel] under [lease], made from the settings now.
  KernelDriver create(KernelId kernel, KernelLease lease) {
    final config = this.config(kernel);
    return switch (kernel) {
      KernelId.mdk => MdkDriver(lease, config),
      KernelId.mediaKit => MediaKitDriver(lease, config),
      KernelId.erika => ErikaDriver(lease, config),
      KernelId.videoPlayer => VideoPlayerDriver(lease, config),
    };
  }
}
