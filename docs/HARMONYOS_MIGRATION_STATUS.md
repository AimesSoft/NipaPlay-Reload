# NipaPlay HarmonyOS 迁移状态

更新日期：2026-07-30

当前基线使用 Flutter `3.35.8-ohos-1.0.1`、HarmonyOS SDK API 24，
应用 `compatibleSdkVersion` 为 18。工程可以完成 Release HAP 的编译、签名、
安装和启动。配置 DevEco Studio 自动签名后，产物位于：

```text
build/ohos/hap/entry-default-signed.hap
```

签名配置由 DevEco Studio 写入本机工程，证书和密钥路径与开发机绑定，不应作为
可复用的仓库凭据提交。

## 主线与 HarmonyOS 依赖模式

仓库默认使用标准 Flutter 的跨平台依赖图。HarmonyOS 插件 fork 不再放在根
`pubspec.yaml` 的全局 override 中，避免 Android、iOS、桌面和 Web 构建被迫
解析鸿蒙版本。

两种模式使用不同的 Flutter SDK：主线版本以根目录 `.fvmrc` 为准，HarmonyOS
版本使用 OpenHarmony Flutter SDK。不要用鸿蒙 SDK 替代主线 SDK 跑桌面或移动端
发布构建。

使用 OpenHarmony Flutter SDK 前先启用鸿蒙依赖：

```bash
dart run tool/configure_flutter_dependencies.dart ohos
flutter pub get
flutter build hap --debug
```

切回标准 Flutter 进行主线开发或验证：

```bash
dart run tool/configure_flutter_dependencies.dart mainline
flutter pub get
flutter analyze lib test
```

脚本生成的 `pubspec_overrides.yaml` 不纳入版本控制；提交前应保留标准 Flutter
生成的 `pubspec.lock`。根 `.metadata` 也保持主线 stable Flutter 元数据，现有
`ohos/` 工程不依赖其中的迁移记录参与构建。

## 已接入的 HarmonyOS 能力

| 能力 | 库或模块 | 当前处理 |
| --- | --- | --- |
| 播放器 | `fvp` | 使用 0.37.3 本地 fork，并兼容 API 18 的 `resourceManager` |
| 播放器 | `erika_flutter` | 锁定远程集成提交；Erika Rust 内核使用 OHNativeWindow/wgpu、AVCodec 和 OHAudio |
| 本地设置 | `shared_preferences` | 使用 OpenHarmony 实现 |
| 应用目录 | `path_provider` | 使用 OpenHarmony 实现 |
| SQLite | `sqflite` | 使用 OpenHarmony 实现 |
| 权限 | `permission_handler_ohos` | 本地接入并注册 |
| 文件选择 | `file_selector` | 使用 OpenHarmony 实现，替代应用内 `file_picker` 调用 |
| 图片选择 | `image_picker` | 使用 OpenHarmony 实现 |
| 打开 URL | `url_launcher` | 使用 OpenHarmony 实现 |
| 应用信息 | `package_info_plus` | 使用 OpenHarmony 实现 |
| 二维码扫码 | `mobile_scanner` | 使用 OpenHarmony 实现并声明相机权限 |
| 屏幕亮度 | `screen_brightness_ohos` | 已注册 |
| 防休眠 | `wakelock_plus_ohos` | 本地 fork 修正 Pigeon 1.3 协议标签并通过真机启停验证 |
| 系统音量 | `volume_controller` | 本地 fork 新增 ArkTS 实现，并兼容鸿蒙返回整数音量 |
| C++ 核心 | `nipaplay_native` | 使用 OHOS NDK 编译为 arm64 动态库并打入 HAP |
| JS 插件运行时 | QuickJS C bridge | HarmonyOS 绕过 `flutter_js`，使用仓库内 FFI bridge |
| 旧字幕编码 | `charset`、`enough_convert`、`cp949_codec` | 纯 Dart 替代 `charset_converter` |
| Rust 核心 | `rust_lib_nipaplay` | Rust 1.93 的 OHOS arm64 target，经 CMake/Hvigor 自动构建并打入 HAP |

播放器在 HarmonyOS 上可选择 FVP/MDK 或 Erika。`media_kit` 仍不进入 HarmonyOS
运行路径；Erika 由本地 OHOS 插件接入，不依赖 libmpv。

## HAP 内的项目原生库

| 文件 | 作用 | Debug HAP 中状态 |
| --- | --- | --- |
| `libnipaplay_native.so` | C++ 字幕、相似度和弹幕计算 | arm64，已剥离 |
| `libquickjs_c_bridge_plugin.so` | JS 插件执行和 `sendMessage` bridge | arm64，已剥离 |
| `librust_lib_nipaplay.so` | FRB、Torrent、扫描、媒体分析等 | arm64，已剥离 |
| `liberika_flutter.so` | Erika Flutter OHOS 插件与 OHNativeWindow bridge | arm64，已打包 |
| `liberika_capi.so` | Erika 播放、FFmpeg、wgpu 和 OHAudio 引擎 | arm64，已打包 |

Rust 构建要求：

```bash
rustup toolchain install 1.93.0-aarch64-apple-darwin --profile minimal
rustup target add aarch64-unknown-linux-ohos --toolchain 1.93.0-aarch64-apple-darwin
```

在非 macOS 构建机上，把第一条命令的 host 后缀换成对应平台。CMake 会固定
`RUSTUP_TOOLCHAIN=1.93.0`，并使用 DevEco Studio OHOS NDK 的
`aarch64-unknown-linux-ohos-clang` 链接。

## 仍需迁移或真机验证

### P1：需要 HarmonyOS 设备验证

| 能力 | 当前状态 |
| --- | --- |
| FVP/MDK 播放 | 播放器创建和 FFmpeg 解码器初始化通过；仍需验证本地文件、网络流、横竖屏和硬解 |
| Erika 播放 | Presenter、零拷贝 Surface、AVCodec/FFmpeg 解码和 OHAudio 真机 smoke 通过；仍需覆盖更多视频格式、横竖屏和长时间播放 |
| Rust FRB | 真机初始化、媒体文件名函数和 Torrent 会话通过；仍需验证文件扫描、实际种子下载和媒体探测 |
| QuickJS | 真机动态库加载、JavaScript 执行和 `sendMessage` 回调通过 |
| 文件/图片选择、扫码、权限 | 权限状态查询通过；仍需验证系统选择器、相机 UI 和授权回调 |
| SQLite、设置、应用目录 | 真机建表读写、设置持久化和文件读写通过 |
| 亮度、音量、防休眠 | 真机读取亮度/音量及防休眠启停通过 |

### P2：已有降级，不阻塞基础播放

| 库或模块 | 当前降级 |
| --- | --- |
| `battery_plus` | 暂不读取电量，播放器状态栏仍显示时间 |
| `nipaplay_smb2` | 原生 SMB2 加速不可用，继续使用纯 Dart `smb_connect` |
| `SystemShareService` | 暂不显示系统分享入口 |
| 文件关联 / 系统“打开方式” | 目前只有 Android、桌面端原生实现 |
| Next2/DFM+ 原生纹理渲染 | Rust 布局库已存在，但还缺 HarmonyOS TextureRegistry/Surface bridge，UI 继续隐藏这两个内核 |

### 可选播放器能力

`media_kit`、`media_kit_video` 及 libmpv 尚未迁移；当前多内核选择为 FVP 和
Erika。Erika 已接入 HarmonyOS AVCodec 硬解与 Surface 零拷贝渲染，并保留
FFmpeg 软件解码回退。

## 不需要迁移

以下能力仅用于桌面端，HarmonyOS 分支已隔离：

- `window_manager`、`screen_retriever`、`tray_manager`；
- `hotkey_manager`、`desktop_drop`、`dart_ipc`；
- `desktop_multi_window`。

`dynamic_color` 使用可选 MethodChannel；HarmonyOS 没有原生结果时会自动使用
应用主题色，无需单独迁移。

## 验证状态

- `flutter pub get`：通过；
- 旧编码字幕单测：6 项通过；
- QuickJS bridge 宿主机 FFI 单测：2 项通过；
- `cargo check --target aarch64-unknown-linux-ohos --lib`：通过；
- `cargo build --target aarch64-unknown-linux-ohos --lib`：通过；
- 标准 Flutter 3.44.6 `flutter build apk --release`：通过，三种 ABI 均包含
  Erika、FVP/MDK 和 NipaPlay Rust 原生库；
- 标准 Flutter 3.44.6 `flutter build ios --release --no-codesign`：通过，
  arm64 `Runner.app` 最低系统版本为 iOS 13；
- OpenHarmony Flutter 3.35.8 `flutter build hap --release`：签名 HAP 编译、
  组包和 SHA-256 摘要验证通过；
- 真机环境：arm64、OpenHarmony `6.1.0.115`、API 23；
- 签名 HAP：安装、正式入口启动及前台驻留通过；
- Erika 纯音频真机 smoke：OHNativeWindow Surface 绑定成功；OHAudio 推入 47 个 PCM
  块并由回调消费 192000 帧，`audioFailures=0`；
- Erika H.264/AAC 联合真机 smoke：渲染 291 个视频帧、推入 263 个音频块、
  OHAudio 回调消费 248562 帧，`renderFailures=0`、`audioFailures=0`；
- Erika HTTP 数据源的 HEAD 探测与 Range 请求使用独立连接池，已通过
  HTTP/1.0 短连接服务器回归，避免首个 GET 报 `Peer disconnected`；
- `tool/ohos_native_smoke.dart`：C++、QuickJS、Rust FRB、Torrent 会话、应用目录、
  SharedPreferences、SQLite、包信息、权限状态、亮度、音量和防休眠全部通过；
- Torrent 在 HarmonyOS 上关闭 rqbit 的全局 DHT 持久化，并将会话数据放入
  应用可写目录，避免访问 `/storage/Users/currentUser/.cache` 被系统拒绝；
- Cupertino Torrent 页面销毁时的锁树通知异常已修复，并增加生命周期回归测试；
- 真机日志仍有 Flutter OHOS 引擎的 Vulkan `SetPresentInfo` 和图片方向读取警告，
  当前未引发崩溃或阻塞渲染。

可重复运行真机 smoke：

```bash
flutter run -d <device-id> --debug -t tool/ohos_native_smoke.dart

# Erika 音视频链路（URI 应指向含音视频轨的媒体）
flutter run -d <device-id> --debug -t tool/ohos_erika_smoke.dart \
  --dart-define=ERIKA_SMOKE_URI=<media-uri>
```
