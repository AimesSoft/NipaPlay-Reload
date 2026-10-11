// 统一播放器接口 — NipaPlay 四内核 (libmpv/media_kit, MDK/fvp, Erika, VideoPlayer) 的公共契约。
//
// 对用户模板的两处已声明调整 (见 docs/refactor/core-inventory.md §1.2):
// 1. 模板中的 `Widget buildVideoSurface()` 与 core 禁 UI 红线冲突:
//    这里改为 `NipaPlayerSurface createSurfaceHandle()` 返回不透明表面描述符,
//    由 UI 层 (app / 未来 ui_common) 把描述符包装成平台视图 Widget。
// 2. `TargetPlatform` 以 core 自有枚举 `NipaTargetPlatform` 表达, app 侧做映射。
// 其余方法签名与模板一致。四个内核适配器实现本接口的迁移工作见库存文档 Batch 2 一节。
import 'dart:async';

/// core 自有平台枚举 (不依赖 flutterfoundation 之外的 Flutter 类型)。
enum NipaTargetPlatform { android, ios, windows, macos, linux, web, ohos, tvos }

/// 视频表面类型。
enum NipaSurfaceKind { none, texture, platformView }

/// 视频表面描述符: core 层对"画面渲染目标"的最小不透明描述。
/// UI 层按 kind 消费:
/// - [NipaSurfaceKind.texture]     → 包裹 Texture(textureId) 或各内核纹理视图;
/// - [NipaSurfaceKind.platformView] → 包裹内核自管的平台视图 (如 Erika 窗口覆盖层);
/// - [NipaSurfaceKind.none]        → 内核无独立表面 (音频/不支持)。
class NipaPlayerSurface {
  const NipaPlayerSurface.texture(int this.textureId)
      : kind = NipaSurfaceKind.texture,
        viewId = null;

  const NipaPlayerSurface.platformView(int this.viewId)
      : kind = NipaSurfaceKind.platformView,
        textureId = null;

  const NipaPlayerSurface.none()
      : kind = NipaSurfaceKind.none,
        textureId = null,
        viewId = null;

  final NipaSurfaceKind kind;
  final int? textureId;
  final int? viewId;
}

/// 统一播放状态 (映射自各内核的 PlaybackState)。
enum PlayerState { idle, buffering, playing, paused, completed, error }

/// 播放器初始化配置。
class PlayerConfig {
  const PlayerConfig({
    this.enableHardwareDecode = true,
    this.userAgent,
    this.httpProxy,
    this.properties = const {},
  });

  final bool enableHardwareDecode;
  final String? userAgent;
  final String? httpProxy;
  final Map<String, String> properties;
}

/// 媒体源描述。
class MediaSource {
  const MediaSource({
    required this.uri,
    this.httpHeaders = const {},
    this.isLive = false,
    this.mimeType,
  });

  final String uri;
  final Map<String, String> httpHeaders;
  final bool isLive;
  final String? mimeType;
}

/// 内核能力声明, 供 UI/服务层按能力降级。
class PlayerCapabilities {
  const PlayerCapabilities({
    this.supportsSnapshot = false,
    this.supportsGifExport = false,
    this.supportsExternalSubtitles = false,
    this.supportsBufferRange = false,
    this.supportsDecoderSelection = false,
    this.supportsPropertyQuery = false,
  });

  final bool supportsSnapshot;
  final bool supportsGifExport;
  final bool supportsExternalSubtitles;
  final bool supportsBufferRange;
  final bool supportsDecoderSelection;
  final bool supportsPropertyQuery;
}

/// 统一播放器接口 — 四内核都实现它。
abstract class NipaPlayer {
  Future<void> initialize(PlayerConfig config);

  Future<void> load(MediaSource source);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Stream<PlayerState> get stateStream;

  Stream<Duration> get positionStream;

  /// 返回渲染表面描述符; UI 层负责将其包装为平台 Widget (core 不持 Widget)。
  NipaPlayerSurface createSurfaceHandle();

  Future<void> dispose();

  PlayerCapabilities get capabilities;
}

/// 内核工厂: 支持平台判定 + 优先级 (数值大者优先)。
abstract class PlayerFactory {
  NipaPlayer create();

  bool supportsPlatform(NipaTargetPlatform platform);

  int get priority;
}
