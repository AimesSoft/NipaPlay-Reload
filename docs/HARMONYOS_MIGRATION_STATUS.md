# NipaPlay HarmonyOS 迁移状态

更新日期：2026-07-31

当前基线使用 Flutter `3.35.8-ohos-1.0.1`、HarmonyOS SDK API 24，
应用 `compatibleSdkVersion` 为 18。工程可以完成 Release HAP 的编译、签名、
安装和启动。配置 DevEco Studio 自动签名后，产物位于：

```text
build/ohos/hap/entry-default-signed.hap
```

签名配置由 DevEco Studio 写入本机工程，证书和密钥路径与开发机绑定，不应作为
可复用的仓库凭据提交。

### 本地签名配置

仓库中的 `ohos/build-profile.json5` 只保留可复用的产品、SDK、构建模式和模块
配置，不包含 `signingConfigs`。从开源仓库拉取代码后，每位开发者都需要在
DevEco Studio 中登录自己的华为开发者账号，并为自己的设备配置自动签名；也可
使用自己申请的证书、Profile 和 P12 手动签名。

签名材料不能在开发者之间共用：Profile 与应用、开发者账号和调试设备绑定，
P12 还包含私钥。不要提交以下内容：

- DevEco Studio 写入 `ohos/build-profile.json5` 的 `signingConfigs`；
- `keyPassword`、`storePassword` 等密码字段；
- 指向个人目录或 `.ohos/config` 的绝对路径；
- `.p12`、`.p7b`、`.cer`、`.csr` 等本地签名材料。

DevEco Studio 完成自动签名后，可能会在工作区内修改
`ohos/build-profile.json5`。这些修改只供本机使用，提交代码前应恢复该文件，
并运行兼容性测试：

```bash
git restore ohos/build-profile.json5
fvm flutter test test/mainline_flutter_compatibility_test.dart
```

CI 或正式发布应从私有 Secret 临时注入签名材料，不应把凭据固化到公开分支。

## HarmonyOS 依赖启用与恢复

HarmonyOS 插件 fork 和本地适配库集中在 `pubspec_overrides.ohos.yaml`，不会
长期写入根 `pubspec.yaml` 的共享依赖配置。使用 OpenHarmony Flutter SDK 前，
需要先生成本机专用的 `pubspec_overrides.yaml`。

切换脚本只负责启用或移除依赖覆盖文件，不会自动执行 `pub get`。

### 启用 HarmonyOS 依赖

先设置本机 OpenHarmony Flutter SDK 路径。以下命令适用于 bash 和 zsh：

```bash
export NIPAPLAY_OHOS_FLUTTER=/path/to/flutter-ohos/bin/flutter
export NIPAPLAY_OHOS_DART=/path/to/flutter-ohos/bin/dart

"$NIPAPLAY_OHOS_FLUTTER" --version
"$NIPAPLAY_OHOS_DART" run tool/configure_flutter_dependencies.dart ohos
"$NIPAPLAY_OHOS_FLUTTER" pub get
```

启用成功后，根目录会生成被 Git 忽略的 `pubspec_overrides.yaml`。它应与
`pubspec_overrides.ohos.yaml` 内容一致，其中包含 HarmonyOS 插件 fork、本地
FVP 0.37.3 适配版以及 Flutter 3.35 可用的 `desktop_multi_window` 占位实现。

### 构建和调试 HAP

构建 Release HAP：

```bash
RUSTUP_TOOLCHAIN=1.93.0 \
  "$NIPAPLAY_OHOS_FLUTTER" build hap --release --no-pub
```

签名产物位于：

```text
build/ohos/hap/entry-default-signed.hap
```

需要真机调试时：

```bash
"$NIPAPLAY_OHOS_FLUTTER" devices
"$NIPAPLAY_OHOS_FLUTTER" run -d <device-id> --debug
```

### GitHub Actions 构建

`.github/workflows/build-ohos.yml` 提供手动触发和 `workflow_call` 两种入口。
工作流在 GitHub 托管的 Ubuntu runner 上完成以下步骤：

1. 准备固定版本的 HarmonyOS Command Line Tools 和 OpenHarmony Flutter；
2. 启用 `pubspec_overrides.ohos.yaml`；
3. 使用 Rust 1.93.0 构建 OHOS arm64 原生库；
4. 链接 MDK 官方提供的 OHOS 预编译 SDK；
5. 使用 `flutter build hap --no-codesign` 生成 unsigned HAP；
6. 可选地从 GitHub Actions Secrets 读取签名材料，生成并校验 signed HAP；
7. 上传 HAP 和对应的 `SHA256SUMS-*`。

#### 运行环境和安全边界

GitHub 托管 runner 默认不包含 HarmonyOS Command Line Tools、Hvigor 和 ohpm。
因此工作流使用公开的
[`harmony-next-pipeline-docker`](https://github.com/sanchuanhehe/harmony-next-pipeline-docker)
镜像，并固定到完整 SHA-256 digest，避免上游修改同名 tag 后无提示地改变构建
环境。OpenHarmony Flutter 同样固定到已经过真机验证的 commit，而不是跟随浮动
分支。

这个容器用于提供构建工具，不包含 NipaPlay 的签名凭据。工作流的权限限制为
只读仓库内容，签名文件只在 runner 临时目录中从 Secrets 解码，签名完成后立即
删除。容器内 HarmonyOS CLI 6.1.1 的 `hap-sign-tool.jar` 不支持交互式
`pwdInputMode` 参数，因此工作流使用其支持的 `keyPwd` 和 `keystorePwd` 非交互
参数。密码来自 GitHub Actions Secrets，日志会自动脱敏，并且签名任务只允许在
明确提供 Secrets 的受信任工作流中运行。

`workflow_dispatch` 只在该工作流已经存在于仓库默认分支时显示。合并后可进入
**Actions > Build HarmonyOS > Run workflow** 手动运行，也可以由其他工作流通过
`workflow_call` 复用。该工作流不会在外部 Pull Request 上自动使用签名 Secrets：
GitHub 不会向 fork PR 提供仓库 Secrets，也不应把签名凭据暴露给不受信任的 PR
代码。

#### 配置签名

在仓库的 **Settings > Secrets and variables > Actions** 中配置以下 Secrets：

| Secret | 内容 |
| --- | --- |
| `OHOS_SIGNING_CERT_BASE64` | Base64 编码的应用签名 `.cer` |
| `OHOS_SIGNING_PROFILE_BASE64` | Base64 编码的调试或发布 `.p7b` |
| `OHOS_SIGNING_KEYSTORE_BASE64` | Base64 编码的 `.p12` |
| `OHOS_SIGNING_KEY_ALIAS` | P12 中的密钥别名 |
| `OHOS_SIGNING_KEYSTORE_PASSWORD` | P12 密码 |
| `OHOS_SIGNING_KEY_PASSWORD` | 密钥密码 |

可使用以下命令生成单行 Base64 内容：

```bash
base64 < application.cer | tr -d '\n'
base64 < profile.p7b | tr -d '\n'
base64 < application.p12 | tr -d '\n'
```

进入仓库的 **Actions > Build HarmonyOS > Run workflow**，保持
`sign_hap=true` 即可构建签名包。可侧载产物位于：

```text
release-HarmonyOS-signed/
└── NipaPlay-<version>-HarmonyOS-arm64-signed.hap
```

工作流每次都会保留 unsigned 构建结果，签名开启时会再额外上传 signed 结果：

| Artifact | 用途 | 能否直接侧载 |
| --- | --- | --- |
| `release-HarmonyOS-signed` | 真机安装和测试 | 可以，但 Profile 必须包含目标设备 |
| `release-HarmonyOS-unsigned` | 检查 CI 是否可以完成编译 | 不可以 |

调试 Profile 必须包含目标设备 UDID，并且证书、Profile、P12 和密钥别名必须
属于同一套签名。否则即使 CI 签名成功，设备也会拒绝安装。使用不同证书签名的
同包名应用不能直接覆盖安装，需要先卸载旧版本。

若未配置签名 Secrets，可以将 `sign_hap` 设为 `false`，工作流会上传
`release-HarmonyOS-unsigned`。Unsigned HAP 仅用于验证构建，不能直接侧载到
正式 HarmonyOS 设备。

工作流不会把解码器 SDK 从源码重新编译：MDK 使用官方 OHOS 预编译库，Erika
则按其开源构建流程编译 OHOS arm64 运行库。

#### 当前验证结果

已经完成以下本地与 GitHub Actions 验证：

- 使用固定的 OpenHarmony Flutter commit 完成 OHOS arm64 Release unsigned
  HAP 构建；
- 使用 HarmonyOS `hap-sign-tool.jar` 完成签名和 `verify-app` 校验；
- 将生成的 signed HAP 侧载到 HarmonyOS 6.1 真机并成功启动应用；
- 在 fork 的 GitHub Actions 中使用六项签名 Secrets 完成完整 Release 构建、
  签名、校验，并成功上传 signed 和 unsigned 两种 HAP artifact；
- `actionlint`、YAML 解析及主线 Flutter 兼容性测试通过。

主仓库合并工作流后仍需配置相同的六项 Secrets；证书和 Profile 决定 signed HAP
可用于真机侧载、AGC 邀请测试还是正式发布，工作流本身不会改变 Profile 的授权
范围。

### 提交前恢复默认依赖

完成 HarmonyOS 开发或构建后，使用仓库 `.fvmrc` 指定的标准 Flutter 恢复默认
依赖，并重新生成 `pubspec.lock`：

```bash
fvm install
fvm use --force
dart run tool/configure_flutter_dependencies.dart mainline
fvm flutter --version
fvm flutter pub get
test ! -e pubspec_overrides.yaml
git status --short
```

检查要求：

- `pubspec_overrides.yaml` 不存在；该文件只用于本机切换，且已加入 `.gitignore`。
- `pubspec.lock` 由标准 Flutter 3.44.6 生成，不包含
  `pubspec_overrides.ohos.yaml` 对共享依赖的覆盖解析结果。
- 不提交由 HAP 构建临时改写的插件注册文件或 Hvigor 绝对路径。
- 根 `.metadata` 保持标准 stable Flutter 元数据；现有 `ohos/` 工程不依赖其中的
  HarmonyOS 迁移记录参与构建。

### 常见问题

- 标准 Flutter 无法识别 `flutter build hap` 属于正常现象；HAP 必须使用
  OpenHarmony Flutter SDK。
- 启用或恢复依赖后若未重新执行 `pub get`，`.dart_tool/package_config.json`
  仍可能指向旧依赖，导致看似无关的导入或编译错误。
- 完成 HAP 构建后，提交前应恢复默认依赖和 `pubspec.lock`。

## 已接入的 HarmonyOS 能力

| 能力 | 库或模块 | 当前处理 |
| --- | --- | --- |
| 播放器 | `fvp` | 使用 0.37.3 本地 fork，并兼容 API 18 的 `resourceManager` |
| 播放器 | `erika_flutter` | 使用官方 `AimesSoft/Erika` v0.1.4；Erika Rust 内核使用 OHNativeWindow/wgpu、AVCodec 和 OHAudio |
| 本地设置 | `shared_preferences` | 使用 OpenHarmony 实现 |
| 应用目录 | `path_provider` | 使用 OpenHarmony 实现 |
| SQLite | `sqflite` | 使用 OpenHarmony 实现 |
| 权限 | `permission_handler_ohos` | 本地接入并注册 |
| 文件选择 | `file_selector` | 使用仓库内 OpenHarmony fork；文件选择可用，并修复取消选择后 Future 不返回的问题 |
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

### 文件选择能力边界

- 鸿蒙手机上的单文件和多文件选择可用；用户取消选择时返回空结果，
  不再让 Flutter Future 一直等待。
- 当前 `file_selector_ohos` 没有实现 `getDirectoryPath`。API 23 SDK 的
  `DocumentSelectMode.FOLDER` 仅声明支持 2-in-1 设备，当前手机不具备
  `SystemCapability.FileManagement.UserFileService.FolderSelection`。
- 因此手机端不能把“选择任意文件夹并长期递归访问”作为稳定能力。
  依赖目录的功能应优先采用多文件导入、应用固定目录或远程媒体库。

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
| 文件关联 / 系统“打开方式” | HarmonyOS 原生入口尚未实现 |
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
