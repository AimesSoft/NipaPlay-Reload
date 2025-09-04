# 12. 悬赏板块 🎯

欢迎来到 NipaPlay-Reload 悬赏板块！这里汇集了一些我们目前无法解决的棘手技术问题。如果你有相关技术背景或者感兴趣，非常欢迎你挑战这些问题。解决这些问题将会极大地提升用户体验！

## 如何参与

- 选择一个你感兴趣且有能力解决的问题
- 在对应的 Issue 中留言表示你想要尝试解决
- 提交 Pull Request 时请在描述中引用相关的悬赏问题
- 成功解决问题的贡献者将在项目中获得特别致谢

## 问题列表

### 🔥 高优先级问题

#### 1. 弹幕算法优化 ![难度: 高](https://img.shields.io/badge/难度-高-red)
**问题描述**: 目前的弹幕算法存在碰撞检测和轨道分配缺陷，弹幕重叠严重，影响观看体验。

**技术领域**: 算法优化、图形渲染、性能优化  
**相关文件**: `lib/danmaku_gpu/`, `lib/danmaku_abstraction/`  
**期望结果**: 更智能的弹幕碰撞检测和轨道分配算法

---

#### 2. MDK硬件解码支持 ![难度: 高](https://img.shields.io/badge/难度-高-red)
**问题描述**: 目前使用的 mdk 内核（pub.dev 上的 fvp 包）无法开启硬件解码，但官方文档声称支持。

**技术领域**: 原生平台集成、视频解码、FFmpeg  
**相关文件**: `lib/player_abstraction/mdk_player_adapter*.dart`  
**期望结果**: 正确启用硬件解码，提升播放性能和降低CPU占用

---

#### 3. 移动端字体渲染问题 ![难度: 高](https://img.shields.io/badge/难度-高-red)
**问题描述**: 
- Android: 加载非内置字体的 ASS/SRT 字幕导致应用卡顿，中文显示为空格
- iOS: 同样的问题，但中文显示为豆腐块

**技术领域**: 字体渲染、移动端优化、字幕解析  
**相关文件**: `lib/utils/subtitle_*.dart`, `lib/services/subtitle_service.dart`  
**期望结果**: 流畅的字体加载和正确的中文字符显示

---

### 💻 桌面端优化


#### 4. Linux AppImage 体积优化 ![难度: 中](https://img.shields.io/badge/难度-中-orange)
**问题描述**: 目前 Linux 的 AppImage 格式文件体积过大，需要优化打包策略。

**技术领域**: 构建系统、包管理、Linux 平台  
**相关文件**: 构建脚本、`linux/` 目录  
**期望结果**: 显著减小 AppImage 文件大小

---

#### 5. Flathub 上架支持 ![难度: 中](https://img.shields.io/badge/难度-中-orange)
**问题描述**: 希望将应用上架到 Flathub，需要创建相应的 Flatpak 配置。

**技术领域**: Flatpak、Linux 包管理、CI/CD  
**相关文件**: 需要新建 Flatpak 相关配置文件  
**期望结果**: 成功上架 Flathub，用户可以通过 `flatpak install` 安装

---

### 🎨 用户体验优化

#### 6. Windows 安装程序美化 ![难度: 低](https://img.shields.io/badge/难度-低-green)
**问题描述**: 
- 安装程序图标显示为默认图标而非 NipaPlay 图标
- 安装界面可以进一步美化

**技术领域**: NSIS、Windows 安装程序  
**相关文件**: `windows/nipaplay_installer.nsi`  
**期望结果**: 使用正确的应用图标和更美观的安装界面

---

#### 7. macOS DMG 布局美化 ![难度: 低](https://img.shields.io/badge/难度-低-green)
**问题描述**: macOS 的 DMG 文件打开后的布局需要美化。

**技术领域**: macOS 打包、DMG 设计  
**相关文件**: `dmg.sh`  
**期望结果**: 更美观的 DMG 安装界面

---

#### 8. 更多主题支持 ![难度: 中](https://img.shields.io/badge/难度-中-orange)
**问题描述**: 目前主题数量有限，希望有更多风格的主题选择。

**技术领域**: UI/UX 设计、Flutter 主题系统  
**相关文件**: `lib/theme_abstraction/`, `lib/widgets/nipaplay_theme/`  
**期望结果**: 新增多种风格的主题（如：极简、游戏风、复古等）

---

### 🎬 播放器内核扩展

#### 9. HDR 支持 ![难度: 高](https://img.shields.io/badge/难度-高-red)
**问题描述**: 播放器需要支持 HDR 视频播放和色彩管理。

**技术领域**: 视频解码、色彩科学、图形渲染  
**相关文件**: `lib/player_abstraction/`  
**期望结果**: 支持 HDR10、HDR10+、Dolby Vision 等格式

---

#### 10. 新播放器内核集成 ![难度: 高](https://img.shields.io/badge/难度-高-red)
**问题描述**: 希望添加更多播放器内核选择：
- VLC 内核
- GPU-Next 内核

**技术领域**: 播放器集成、原生平台开发  
**相关文件**: `lib/player_abstraction/`  
**期望结果**: 用户可以在设置中选择不同的播放器内核

---

#### 11. 新平台移植 ![难度: 极高](https://img.shields.io/badge/难度-极高-darkred)
**问题描述**: 希望将应用移植到更多平台：
- Apple TV
- 鸿蒙OS (HarmonyOS)
- Vision Pro

**技术领域**: 跨平台开发、平台特定API  
**相关文件**: 需要新建平台特定目录  
**期望结果**: 在新平台上运行的完整应用

---

### 🎮 交互体验

#### 12. 手柄支持 ![难度: 中](https://img.shields.io/badge/难度-中-orange)
**问题描述**: 添加游戏手柄支持，特别是为 Steam Deck 等设备优化交互体验。

**技术领域**: 输入设备、游戏手柄API  
**相关文件**: `lib/utils/`, 控制器相关组件  
**期望结果**: 支持主流游戏手柄的导航和播放控制

---

#### 13. Steam Deck GPU 弹幕性能优化 ![难度: 高](https://img.shields.io/badge/难度-高-red)
**问题描述**: 在 Steam Deck 上使用 GPU 弹幕渲染时，视频帧数急剧下降。

**技术领域**: GPU 渲染优化、性能调优  
**相关文件**: `lib/danmaku_gpu/`  
**期望结果**: 在 Steam Deck 上流畅运行 GPU 弹幕

---

### 🔧 底层优化

#### 14. LibMPV 完整版支持 ![难度: 中](https://img.shields.io/badge/难度-中-orange)
**问题描述**: Windows 版本的 libmpv 不是完整版，需要默认支持完整版以获得更好的编解码器支持。

**技术领域**: 构建系统、Windows 平台  
**相关文件**: Windows 构建相关文件  
**期望结果**: Windows 版本默认使用完整版 libmpv

---

#### 15. LibMPV 参数扩展 ![难度: 中](https://img.shields.io/badge/难度-中-orange)
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
- 使用 AI 编程助手（如 Claude、Cursor、GitHub Copilot）来辅助开发

---

**💡 提示**: 即使你无法完全解决某个问题，部分进展也是有价值的！不要害怕尝试。

**⬅️ 上一篇: [11. 非代码贡献：同样重要！](11-Non-Coding-Contributions.md)**