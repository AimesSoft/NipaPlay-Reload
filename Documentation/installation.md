# 安装

选择你的平台并按照步骤完成安装。

## Windows

- 前往 [GitHub Release 页面](https://github.com/AimesSoft/NipaPlay-Reload/releases) 下载安装包（或压缩包）；执行安装或解压后运行。
- 首次启动被 Defender 拦截时，点击"更多信息→仍要运行"。

## macOS

- 推荐 Homebrew：
  
  ```bash
  brew tap AimesSoft/nipaplay-reload
  brew install --cask nipaplay-reload
  ```
  
  安装完成后，查看 [更新与发布通道](release-channels.md) 了解如何使用 Homebrew 轻松更新 NipaPlay（无需再次处理系统安全提示）。
- 或从 [Release 页面](https://github.com/AimesSoft/NipaPlay-Reload/releases) 下载 dmg，将应用拖至"应用程序"。

## Linux

- Arch Linux (AUR)：从 AUR 下载 二进制包 [`nipaplay-reload-bin`](https://aur.archlinux.org/packages/nipaplay-reload-bin) 或源码包 [`nipaplay-reload`](https://aur.archlinux.org/packages/nipaplay-reload)：
  ```bash
  yay -S nipaplay-reload-bin
  ```
  或
  ```bash
  yay -S nipaplay-reload
  ```

- Gentoo Linux (x86_64)：
  ```bash
  # 将版本号替换为当前最新版本
  ebuild gentoo/media-video/nipaplay-bin/nipaplay-bin-<版本号>.ebuild merge
  ```

- 其他发行版：从 [Release 页面](https://github.com/AimesSoft/NipaPlay-Reload/releases) 下载对应构建包（AppImage / deb 等）并按常规方式安装/运行。

## Android

- 从 [Release 页面](https://github.com/AimesSoft/NipaPlay-Reload/releases) 下载匹配架构的 APK（常见 arm64），启用"未知来源"后安装。

## HarmonyOS

HarmonyOS 当前主要面向开发者和测试用户，需要从源码构建 HAP，并使用 DevEco Studio 配置开发者签名；这不是 GitHub Release 中的通用安装包。开发者请参考
[HarmonyOS 依赖与构建说明](../docs/HARMONYOS_MIGRATION_STATUS.md#harmonyos-依赖启用与恢复)。

安装前请确认：

- 已安装与仓库说明匹配的 OpenHarmony Native SDK 和 DevEco Studio。
- 设备允许开发者模式和调试签名，且应用包的签名证书与设备匹配。
- 当前构建可能缺少商店分发、自动更新和全部硬件能力；遇到播放问题请先切换内核并保留日志。

## tvOS

tvOS 当前是开发者预览路径，不提供面向普通用户的 App Store 安装包。需要 macOS、Xcode、tvOS 设备或模拟器以及项目指定的 tvOS Flutter fork。

构建和签名说明见 [Apple TV 开发指南](../docs/TVOS_DEVELOPMENT.md)。真机安装需要 Apple Developer 签名；模拟器只能验证 UI 和部分播放流程，不能代表所有硬解、HDR 或遥控器行为。

## iOS

iOS 用户可以选择以下几种安装方式：

### 方式一：App Store

- 点击以下链接从App Store安装：[Nipaplay](https://apps.apple.com/cn/app/nipaplay/id6751284970)

### 方式二：TestFlight 公开测试版

1. 在 iOS 设备上打开 App Store，搜索并下载 TestFlight 应用
2. 点击以下链接加入测试：[NipaPlay TestFlight 公开测试](https://testflight.apple.com/join/4JMh3t44)
3. 在 TestFlight 中点击"接受"，然后点击"安装"
4. 等待应用下载完成即可使用

**优势**：

- 无需复杂配置，一键安装
- 自动更新通知
- TestFlight 测试版本有效期为 90 天
- 官方测试渠道，安全可靠

### 方式三：Xcode 自签名（技术用户）

如果您有 macOS 设备并熟悉 Xcode 开发：

1. **准备环境**：
   
   - 一台 macOS 设备
   - Xcode（从 App Store 免费下载）
   - iOS 设备和数据线
2. **获取源码**：
   
   - 从 [Release 页面](https://github.com/AimesSoft/NipaPlay-Reload/releases) 下载源码包
3. **配置和构建**：
   
   - 解压源码并用 Xcode 打开 `ios/Runner.xcworkspace`
   - 配置 Bundle Identifier 和开发者签名
   - 连接设备并构建安装

### 方式四：侧载工具安装（不推荐）

**注意**：侧载方式需要定期重新签名，维护成本较高，建议优先使用 TestFlight。

**使用爱思助手**：

1. 在电脑上下载并安装 [爱思助手](https://www.i4.cn/)
2. 从 [Release 页面](https://github.com/AimesSoft/NipaPlay-Reload/releases) 下载 `.ipa` 文件
3. 连接 iOS 设备到电脑
4. 打开爱思助手「工具箱」→ 选择「IPA签名」→ 导入IPA文件
5. 点击「使用Apple ID签名」→ 登录Apple ID → 勾选设备标识
6. 在设备上：设置 → 通用 → VPN与设备管理 → 信任企业级应用

**使用 AltStore**：

1. 在电脑上安装 [AltStore](https://altstore.io/) 和 iTunes/Apple Music
2. 通过 AltStore 在设备上安装 AltStore 应用
3. 使用 AltStore 侧载 `.ipa` 文件
4. 定期刷新签名（免费账号 7 天刷新一次）

### 签名说明

- **免费 Apple ID**：签名有效期 7 天，需定期刷新

---

**⬅️ 上一篇: [快速开始](quick-start.md)** | **➡️ 下一篇: [安装后设置](post-install.md)**
