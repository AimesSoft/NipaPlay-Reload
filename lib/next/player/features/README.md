# Next 播放功能

本目录只操作 Next 会话、共享设置/记录和系统窗口端口，不调用 Classic 播放器或 `VideoPlayerState`。

- `capture.dart`：截图读取正在显示的 Flutter 场景；原生 surface 读取驱动截图后叠加当前透明叠层。编码、缩放、裁剪在 isolate；GIF 使用独立 Erika 解码器。截图不切原生轨道。输出用独占创建防止覆盖已有文件。
- `timeline_preview.dart`：按需解码，一个执行中请求、一个最新等待请求、一张缓存图片；切会话和关闭时释放独立解码器。不申请播放租约。
- `navigation.dart`：容器章节、双向逐帧。优先驱动原生逐帧，否则按报告的帧率精确 seek，并在结果中说明方法。
- `windows.dart`：同引擎分离窗口和画中画，系统调用可注入；串行处理进出，恢复原置顶状态。测试不操作真实桌面窗口。
- `external_handoff.dart`：用参数列表直接启动所选程序，保留路径、类型、起点与 UA；只记录交接事实，进度和暂停未知，不把收据当成可控制的内部会话。
- `remote_control.dart`：远控协议读取 Next 快照，并调用 Next 的暂停、seek、章节等端口；设置通过原设置来源记录，外部播放器不提供虚假的控制。
- `settings_adapter.dart`：F 线设置直接写共享偏好，保留整数枚举等原存储格式；Next 开启时不触发 Classic 的 setter/预览解码器。
- `local_operations.dart` / `operation_specs.dart`：Next 自己的本地操作，动作 ID、effect 和输入输出 schema 通过对照测试保持一致。
- `debug_features.dart`：只在 Debug 且 LabProfile 下注册的实机预览/远控/目录验证入口；不添加 Agent 动作。

## 并行线接合

K 线的驱动实现可选接口 `KernelFrameFeatures`，在原有栅栏队列中实现 `stepFrame` / `snapshotPicture`；截图数据为 RGBA。容器章节写入 `MediaFacts.chapters`，单位毫秒，按容器顺序。F 已给 MDK 接上。没有原生逐帧接口的变帧率媒体，按帧率 seek 不保证一帧，不能将其报告成原生逐帧。

D/P2 将自己的可视叠层交给 `NextVideoStage.overlays`；每层用 `PlaybackCaptureLayer(capture: playback.capture, danmaku: true/false, child: ...)` 包装。主窗和分离窗必须使用同一套叠层构造。原生播放器内部叠层是否包含在截图中，由该驱动的 snapshot 决定，不能据此伪报包含。`danmakuIncluded` 只表示包含显示层，不证明当前时刻有可见文字。

S 线的重试应保留原 `MediaRequest` 的来源上下文并重新解析；目前重试搬运位置、暂停、音量、增强和倍速，通过 `NextPlayerHost.open(initialLevels: ...)` 创建新实例。

F 线没有改写 P2/D/S 的轨道、字幕、弹幕、跳过片段或剧集实现。全 `playback.*` 的真实通过验收，需要主控合并相应模块后运行 `scripts/next/player_core_f_lab.zsh`。目录授权原生选择器只由人操作；脚本对它执行输入校验，不发送会影响用户桌面的系统键盘事件。
