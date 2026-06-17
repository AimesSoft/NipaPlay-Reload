# 12. 悬赏板块 🎯

欢迎来到 NipaPlay-Reload 悬赏板块！这里汇集的是**当前仍然开放、仍然值得投入的技术挑战**。如果你有相关技术背景或者感兴趣，非常欢迎你挑战这些问题。解决这些问题将会极大地提升用户体验。

## 如何参与

- 选择一个你感兴趣且有能力解决的问题
- 在对应的 Issue 中留言表示你想要尝试解决
- 提交 Pull Request 时请在描述中引用相关的悬赏问题
- 成功解决问题的贡献者将在项目中获得特别致谢

## 当前核心方向：Erika 自研内核

**[Erika](https://github.com/AimesSoft/Erika)** 是 NipaPlay 的自研播放内核，Rust 实现，目标是从解码到渲染完全自主可控。虽然目前还不完整，但已经在 macOS/iOS 上跑通了硬件解码、Metal 渲染、HDR/EDR、AI 超分、弹幕等完整链路。

**我们需要大家团结一致，把 Erika 做到全平台可用。** 这是当前最有价值的贡献方向——不管你擅长 Rust、Metal/wgpu、音视频还是跨平台构建，Erika 都有你能发力的地方。具体参见下方问题列表。

## 最近已经完成的里程碑

先说明一下，下面这些方向已经不再属于当前悬赏重点：

*   **弹幕系统基础能力已经比较完善**: 基础使用、渲染和整体体验已经不是主要堵点。
*   **MDK 硬件解码支持问题已基本解决**: 不再作为当前开放悬赏。
*   **Windows 完整版 LibMPV 支持已落地**: 官方构建已经集成完整版能力，不再作为当前开放悬赏。
*   **macOS HDR 支持已落地**: Erika 内核已实现 Apple EDR 原生 HDR/PQ (BT.2020) 输出与 tone mapping；macOS 平台的 media-kit 也已支持 HDR。不再作为 macOS 平台的开放悬赏。

因此，下面的列表只保留仍然值得投入的新挑战。

## 问题列表

### 🔥 高优先级问题

#### 1. Erika 内核完善与跨平台推进 ![难度: 极高](https://img.shields.io/badge/难度-极高-darkred)

**问题描述**: [Erika](https://github.com/AimesSoft/Erika) 是 NipaPlay 的自研播放内核（Rust），目前已在 macOS/iOS 上实现硬件解码 (VideoToolbox)、零拷贝 Metal 渲染、HDR/EDR、AI 超分 (ArtCNN)、弹幕 GPU 渲染等能力。但离全平台可用还有距离，以下是最需要帮助的方向：

*   **wgpu 渲染后端**：让 Erika 的渲染管线跑在 Windows/Linux/Android 上（基础架构已就绪，需要补全平台适配）
*   **跨平台硬件解码**：接入 DXVA2/D3D11VA (Windows)、VAAPI/VDPAU (Linux)、MediaCodec (Android)
*   **跨平台音频输出**：接入 WASAPI (Windows)、PulseAudio/PipeWire (Linux)、AAudio/OpenSL ES (Android)
*   **Flutter 插件跨平台扩展**：目前 Flutter 插件仅支持 macOS + iOS，需要扩展到其他平台
*   **C ABI 与宿主集成**：完善 C ABI 导出，确保各平台 FFI 调用稳定

**技术领域**: Rust、wgpu/Metal、音视频解码、跨平台构建、Flutter 原生插件
**相关仓库**: [AimesSoft/Erika](https://github.com/AimesSoft/Erika)
**期望结果**: Erika 能在 Windows/Linux/Android 上运行基本的解码-渲染-音频链路
**备注**: 这是当前项目最核心的长期方向。即使只完成其中一个平台的一个模块，也是极有价值的贡献。

---

#### 2. HDR / 杜比视界跨平台推进 ![难度: 高](https://img.shields.io/badge/难度-高-red)

**问题描述**: macOS 上的 HDR 已经通过 Erika 内核（Apple EDR 原生 PQ/BT.2020 tone mapping）和 media-kit 两条路径落地。但 Windows/Linux/Android 上的 HDR 仍是开放问题，涉及不同平台的色彩管理、显示链路和渲染路径差异。

**技术领域**: 视频解码、色彩科学、HDR 元数据、平台渲染管线
**相关文件**: Erika 仓库的渲染模块、`lib/player_abstraction/`、各平台目录
**期望结果**: 在 Windows/Linux 上实现 HDR10 的检测、透传或可接受的 tone mapping 策略
**备注**: 研究型议题，先提交调研报告或实验性 PR 也非常有价值

---

#### 3. Erika macOS/iOS 稳定性与 Bug 修复 ![难度: 高](https://img.shields.io/badge/难度-高-red)

**问题描述**: Erika 内核已经接入 NipaPlay 并可在 macOS/iOS 上使用，但作为尚在快速迭代的自研内核，仍存在各类稳定性问题和边界情况 Bug。需要社区帮助发现、复现和修复这些问题。

**技术领域**: Rust、Metal、VideoToolbox、CoreAudio/AudioQueue、Flutter 原生插件
**相关仓库**: [AimesSoft/Erika](https://github.com/AimesSoft/Erika)
**期望结果**: 在 macOS/iOS 上达到日常可用的稳定性
**备注**: 测试 + 提 Issue 也是极有价值的贡献。如果能附上复现步骤和日志，对修复速度帮助很大。

---

#### 4. Steam Deck GPU 弹幕性能优化 ![难度: 高](https://img.shields.io/badge/难度-高-red)

**问题描述**: 在 Steam Deck 上使用 GPU 弹幕渲染时，视频帧数仍可能明显下降，说明渲染与播放链路之间还有优化空间。

**技术领域**: GPU 渲染优化、性能调优、掌机适配
**相关文件**: `lib/danmaku_gpu/`, `lib/danmaku_next/`, 播放器与覆盖层相关逻辑
**期望结果**: 在 Steam Deck 上更稳定地维持可接受帧率和交互体验


### 💻 桌面端优化

#### 5. Linux AppImage 体积优化 ![难度: 中](https://img.shields.io/badge/难度-中-orange)

**问题描述**: 目前 Linux 的 AppImage 格式文件体积过大，需要优化打包策略。

**技术领域**: 构建系统、包管理、Linux 平台
**相关文件**: 构建脚本、`linux/` 目录
**期望结果**: 显著减小 AppImage 文件大小

---

#### 6. Flathub 上架支持 ![难度: 中](https://img.shields.io/badge/难度-中-orange)

**问题描述**: 希望将应用上架到 Flathub，需要创建相应的 Flatpak 配置。

**技术领域**: Flatpak、Linux 包管理、CI/CD
**相关文件**: 需要新建 Flatpak 相关配置文件
**期望结果**: 成功上架 Flathub，用户可以通过 `flatpak install` 安装

---

### 🎨 用户体验优化

#### 7. Windows 安装程序美化 ![难度: 低](https://img.shields.io/badge/难度-低-green)

**问题描述**:

- 安装程序图标显示为默认图标而非 NipaPlay 图标
- 安装界面可以进一步美化

**技术领域**: NSIS、Windows 安装程序
**相关文件**: `windows/nipaplay_installer.nsi`
**期望结果**: 使用正确的应用图标和更美观的安装界面

---

#### 8. macOS DMG 布局美化 ![难度: 低](https://img.shields.io/badge/难度-低-green)

**问题描述**: macOS 的 DMG 文件打开后的布局需要美化。

**技术领域**: macOS 打包、DMG 设计
**相关文件**: `dmg.sh`
**期望结果**: 更美观的 DMG 安装界面

---

### 🎬 平台与内核拓展

#### 9. 新平台移植 ![难度: 极高](https://img.shields.io/badge/难度-极高-darkred)

**问题描述**: 希望将应用移植到更多平台：

- Apple TV
- 鸿蒙OS (HarmonyOS)
- Vision Pro

**技术领域**: 跨平台开发、平台特定API
**相关文件**: 需要新建平台特定目录
**期望结果**: 在新平台上运行的完整应用

---

### 🎮 交互体验

#### 10. 手柄支持 ![难度: 中](https://img.shields.io/badge/难度-中-orange)

**问题描述**: 添加游戏手柄支持，特别是为 Steam Deck 等设备优化交互体验。

**技术领域**: 输入设备、游戏手柄API
**相关文件**: `lib/utils/`, 控制器相关组件
**期望结果**: 支持主流游戏手柄的导航和播放控制

---

### 🔧 底层优化

#### 11. LibMPV 参数扩展 ![难度: 中](https://img.shields.io/badge/难度-中-orange)

**问题描述**: 需要让 libmpv 内核支持更多传入参数，提供更多的播放选项。

**技术领域**: 播放器集成、参数传递
**相关文件**: `lib/player_abstraction/`
**期望结果**: 用户可以配置更多 libmpv 参数

---

## 如何开始

1. **选择问题**: 根据你的技术背景选择一个合适难度的问题
2. **研究现状**: 仔细阅读相关代码，理解当前的实现
3. **制定方案**: 在开始编码前，先在 Issue 中分享你的解决思路
4. **实现和测试**: 使用 AI 工具辅助开发，确保充分测试
5. **提交 PR**: 按照标准流程提交你的解决方案

## 获得帮助

- 如果你对某个问题感兴趣但不知道如何开始，可以在对应的 Issue 中提问
- 可以在项目的 Discord/QQ 群中寻求技术指导
- 使用 AI 编程助手（如 **VS Code + Codex**、Claude、GitHub Copilot）来辅助开发

---

**💡 提示**: 即使你无法一次性解决整个问题，调研报告、原型验证、局部优化和失败经验也都是有价值的贡献。

**⬅️ 上一篇: [11. 非代码贡献：同样重要！](11-Non-Coding-Contributions.md)**
