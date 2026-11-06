# NipaPlay tvOS development

NipaPlay's Apple TV target uses the community
[`fluttertv/flutter-tvos`](https://github.com/fluttertv/flutter-tvos) fork. It
is intentionally versioned independently from the mainline, Linux, and
HarmonyOS Flutter toolchains.

## Pinned toolchain

- flutter-tvos: `v3.44.8-tvos.1.4.3`
- bundled Flutter: `3.44.8`
- deployment target: tvOS 13.0
- application identifier: `com.aimessoft.nipaplay.tvos`

The exact fork tag is stored in `.flutter-version-tvos`. Do not replace the
mainline `.fvmrc` with this version. HarmonyOS keeps its Flutter 3.35-compatible
package interfaces in `pubspec_overrides.ohos.yaml`; adding tvOS does not move
that platform onto the tvOS or mainline toolchain.

## Local setup

Xcode and CocoaPods are required. From the NipaPlay repository root, run:

```bash
./tool/setup_tvos.sh
```

The setup script installs the pinned fork next to the repository by default:

```text
FlutterProject/
  flutter-tvos/
  nipaplay/
```

Set `FLUTTER_TVOS_ROOT` before running the script to use another location.
Use the repository wrapper for subsequent commands so the normal Flutter SDK
is never changed. The wrapper automatically enables
`pubspec_overrides.tvos.yaml`, just as Linux and HarmonyOS select their own
dependency profiles:

```bash
./tool/flutter_tvos.sh doctor -v
./tool/flutter_tvos.sh pub get
./tool/flutter_tvos.sh build tvos --simulator --debug
```

To run the app, install a tvOS Simulator runtime in **Xcode > Settings >
Components**, create an Apple TV simulator, and then use:

```bash
./tool/flutter_tvos.sh devices
./tool/flutter_tvos.sh run -d <apple-tv-device-id>
```

tvOS uses indirect focus navigation rather than touch-style pointer input.
In Simulator, use the arrow keys to move focus, Return to activate, and Escape
to go back; a trackpad or mouse wheel can also move focus. At the root screen,
the Siri Remote MENU button and Simulator Escape key toggle NipaPlay's left
menu instead of leaving the application. In a nested route they retain their
normal back-navigation behavior. NipaPlay always enables its large-screen,
focusable layout on Apple TV.

For a physical Apple TV, select a Development Team for the Runner target in
`tvos/Runner.xcworkspace`, then build or run against the paired device. The
team is deliberately not committed because signing identities are
developer-specific.

## Platform behavior

tvOS is part of the same repository and application source as every other
platform. Shared display-surface and large-screen widgets live under `lib/` and
can also be enabled by desktop, tablet, and television surfaces. Only the
`tvos/` native runner, `.flutter-version-tvos`, the dependency override profile,
and the SDK wrapper are platform-specific. A second Git worktree is optional
for parallel builds; it is not a separate source repository.

The fork reports both `Platform.isIOS == true` and
`Platform.operatingSystem == 'tvos'`. NipaPlay uses the latter to keep Apple TV
out of phone-only code paths and to select the television display surface.

Only Flutter plugins with an explicit `tvos:` implementation are registered.
The target pins the official fluttertv implementations for SharedPreferences,
path provider, package info, SQLite, wakelock, and video playback. Playback is
fixed to the Erika kernel through the tvOS dependency profile; Media Kit, MDK,
file pickers, URL launcher, and camera-based features remain hidden where they
do not have usable tvOS implementations.

Pull-request CI builds an unsigned simulator app. Manual and reusable release
runs build an unsigned arm64 device IPA for sideloading tools to re-sign with
the user's Apple developer identity. This keeps personal teams and provisioning
profiles out of the project while still producing a physical Apple TV package.
App Store or directly installable device-specific artifacts continue to require
Apple signing credentials and a matching tvOS provisioning profile.

## Next 身体模式

实验室的 Next 开关现在也适用于 tvOS。打开后复用 iPad 的身体模式：
电视运行界面、播放器和 Mesh，通过同账号设备上的梨花提供对话服务。
没有设备运行梨花时，来源和播放继续独立工作；关闭开关回到 Classic。
本线没有增加电视专用主题、字号或版式。

### 原生依赖与构建

除上面的 Flutter SDK、Xcode、CocoaPods 外，Next 的 Mesh 静态库需要
带 `rust-src` 的 nightly Rust。tvOS 的 Rust target 使用 `build-std`：

```bash
rustup toolchain install nightly --component rust-src
FLUTTER_TVOS_ROOT=$HOME/development/flutter-tvos ./tool/flutter_tvos.sh pub get
FLUTTER_TVOS_ROOT=$HOME/development/flutter-tvos ./tool/flutter_tvos.sh build tvos --simulator --debug --no-pub
```

在共享验收机器上，以上依赖安装和构建必须写入脚本并用
`~/.nipa-next/bin/heavy-run` 执行。2026-11-07 的实际构建使用
Rust `1.101.0-nightly (249c1e4e3 2026-11-05)`，默认限制为两个 Cargo worker。
`rust_builder/tvos/build_mesh.sh` 从 CocoaPods 调用；`rust/tvos/` 只链接
共享 Mesh，Dart 在后台 isolate 通过 JSON C ABI 调用，不引入桌面渲染器或下载器。
其他平台继续使用原 FRB 路径。

tvOS profile 固定 Erika Flutter 0.3.4。`tvos/erika_surface_patch.rb` 在
Pod 安装时验证上游 Swift 源的 SHA-256，并生成 tvOS 专用副本：把 renderer
控制的 Metal layer 从 UIView backing layer 改为独立 sublayer，解决
tvOS 26 的后台线程 UIKit 断言。不改 Pub cache 和其他平台的插件源。
升级 Erika 时必须复核该补丁；上游修复后应移除它。

### 存储与恢复

tvOS 的可写文件根为 `Library/Caches/NipaPlay`，Next 位于其 `next/` 下。
数据库、目录投影和图片均可清理；身份私钥、证书和小型安装记录保存到
系统 Keychain，启动时恢复缓存副本。账号和来源秘密也经现有凭据迁移逻辑
进入 Keychain，偏好只保留引用。数据库消失后，通过现有任务引擎同步已配置
来源，远端目录由 MeshLibrary 恢复；不把整个数据库放进 UserDefaults 或 Keychain。

焦点输入在 `lib/next/ui/widgets/television_focus.dart`；按钮、卡片复用原 hover
状态。`next_shell.dart` 负责跨页面焦点域和 Menu/Esc 返回，文字输入复用
Classic 的 `TvOSRemoteTextInputControl`。后续视觉工作可从这些位置接手。
第一轮的完整证据、限制与交付状态见 `next/TVOS_REPORT.md`。
