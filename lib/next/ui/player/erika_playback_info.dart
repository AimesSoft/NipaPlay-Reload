import 'package:nipaplay/player_abstraction/player_data_models.dart';

/// Native status, not the saved preference: a selected model may be inactive.
List<(String, String)> erikaPlaybackInfoRows(Map<String, Object?> status) {
  final diagnostics = status['diagnostics'];
  final detail = diagnostics is Map ? diagnostics['upscaler'] : null;
  final upscaler = status['upscalerStatus'];
  if (upscaler is! Map) {
    final errors = status['errors'];
    final error = errors is Map ? errors['upscalerStatus'] : null;
    return [('超分状态', error == null ? '内核未报告' : '读取失败：$error')];
  }
  final mode = upscaler['requestedMode'];
  final backend = upscaler['activeBackend'];
  final modeLabel = PlayerUpscalerMode.values
          .where((m) => m.nativeName == mode || m.name == mode)
          .firstOrNull
          ?.label ??
      '$mode';
  final backendLabel = PlayerUpscalerBackendStatus.values
          .where((b) => b.name == backend)
          .firstOrNull
          ?.label ??
      '$backend';
  final frames = upscaler['upscaledFrames'];
  final gpu = upscaler['lastGpuMicros'];
  final encode = upscaler['lastEncodeMicros'];
  final fallbacks = upscaler['fallbackCount'];
  return [
    ('超分模式', modeLabel),
    ('超分后端', backendLabel),
    if (mode != 'off') ...[
      if (frames is num) ('超分帧数', '${frames.toInt()}'),
      if (encode is num && encode > 0)
        ('超分提交', '${(encode / 1000).toStringAsFixed(2)} ms'),
      if (gpu is num && gpu > 0)
        ('超分 GPU', '${(gpu / 1000).toStringAsFixed(2)} ms'),
      if (fallbacks is num && fallbacks > 0) ('超分回退', '${fallbacks.toInt()} 次'),
      if (detail is Map) ...[
        if (detail['engine'] case final String engine when engine.isNotEmpty)
          ('超分实现', engine),
        if (detail['reason'] case final String reason when reason.isNotEmpty)
          ('超分说明', reason),
      ],
    ],
  ];
}

String? erikaDecoderLabel(Map<String, Object?> status) {
  final diagnostics = status['diagnostics'];
  // Windows 0.3.5 omits the decoder payload from Flutter events. The native
  // diagnostics snapshot retains it, including runtime decoder fallback.
  final decoder = diagnostics is Map && diagnostics['decoder'] is Map
      ? diagnostics['decoder']
      : status['decoder'];
  if (decoder is! Map) return null;
  return switch (decoder['activeBackend']) {
    'cuda' => 'CUDA / NVDEC',
    'vaapi' => 'VA-API',
    'videotoolbox' => 'VideoToolbox',
    'd3d11va' => 'D3D11VA',
    'mediacodec' => 'MediaCodec',
    'software' => 'FFmpeg (software)',
    final String backend when backend.isNotEmpty => backend,
    _ => null,
  };
}
