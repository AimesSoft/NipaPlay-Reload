// 硬解模式（照搬 PiliPlus hwdec_type.dart 的 mpv --hwdec 全枚举）
// value = mpv hwdec 属性值；mdk 内核按模式映射 decoder 列表。

enum HwDecType {
  no('no', '软解'),
  auto('auto', '自动（任意可用解码器）'),
  autoSafe('auto-safe', '自动（最佳解码器）'),
  autoCopy('auto-copy', '自动（带拷贝）'),
  d3d12va('d3d12va', 'DirectX 12 (Windows 10+)'),
  d3d12vaCopy('d3d12va-copy', 'DirectX 12 (Windows 10+) (非直通)'),
  d3d11va('d3d11va', 'DirectX 11 (Windows 8+)'),
  d3d11vaCopy('d3d11va-copy', 'DirectX 11 (Windows 8+) (非直通)'),
  dxva2('dxva2', 'DXVA2 (Windows 7+)'),
  dxva2Copy('dxva2-copy', 'DXVA2 (Windows 7+) (非直通)'),
  videotoolbox('videotoolbox', 'VideoToolbox (macOS / iOS)'),
  videotoolboxCopy(
      'videotoolbox-copy', 'VideoToolbox (macOS / iOS) (非直通)'),
  vaapi('vaapi', 'VAAPI (Linux)'),
  vaapiCopy('vaapi-copy', 'VAAPI (Linux) (非直通)'),
  nvdec('nvdec', 'NVDEC (NVIDIA 独占)'),
  nvdecCopy('nvdec-copy', 'NVDEC (NVIDIA 独占) (非直通)'),
  drm('drm', 'DRM (Linux)'),
  drmCopy('drm-copy', 'DRM (Linux) (非直通)'),
  vulkan('vulkan', 'Vulkan (全平台) (实验性)'),
  vulkanCopy('vulkan-copy', 'Vulkan (全平台) (实验性) (非直通)'),
  vdpau('vdpau', 'VDPAU (Linux)'),
  vdpauCopy('vdpau-copy', 'VDPAU (Linux) (非直通)'),
  mediacodec('mediacodec', 'MediaCodec (Android)'),
  mediacodecCopy('mediacodec-copy', 'MediaCodec (Android) (非直通)'),
  cuda('cuda', 'CUDA (NVIDIA 独占) (过时)'),
  cudaCopy('cuda-copy', 'CUDA (NVIDIA 独占) (过时) (非直通)'),
  crystalhd('crystalhd', 'CrystalHD (全平台) (过时)'),
  rkmpp('rkmpp', 'Rockchip MPP (部分 Rockchip 芯片)'),
  amf('amf', 'AMF (AMD 独占)'),
  amfCopy('amf-copy', 'AMF (AMD 独占) (非直通)'),
  qsv('qsv', 'Quick Sync Video (Intel 独占)'),
  qsvCopy('qsv-copy', 'Quick Sync Video (Intel 独占) (非直通)'),
  ;

  final String hwdec;
  final String desc;
  const HwDecType(this.hwdec, this.desc);
}