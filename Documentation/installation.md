# 安装

选择你的平台并按照步骤完成安装。

## Windows

- 前往 [GitHub Release 页面](https://github.com/Shinokawa/NipaPlay-Reload/releases) 下载安装包（或压缩包）；执行安装或解压后运行。
- 首次启动被 Defender 拦截时，点击"更多信息→仍要运行"。

## macOS

- 推荐 Homebrew：

    ```bash
    brew tap Shinokawa/nipaplay-reload
    brew install --cask nipaplay-reload
    ```

    安装完成后，查看 [更新与发布通道](release-channels.md) 了解如何使用 Homebrew 轻松更新 NipaPlay（无需再次处理系统安全提示）。

- 或从 [Release 页面](https://github.com/Shinokawa/NipaPlay-Reload/releases) 下载 dmg，将应用拖至"应用程序"。

## Linux

- Arch Linux（x86_64）：

    ```bash
    paru -S nipaplay-reload-bin
    # 或
    yay -S nipaplay-reload-bin
    ```

- 其他发行版：从 [Release 页面](https://github.com/Shinokawa/NipaPlay-Reload/releases) 下载对应构建包并按常规方式安装/运行。

## Android

- 从 [Release 页面](https://github.com/Shinokawa/NipaPlay-Reload/releases) 下载匹配架构的 APK（常见 arm64），启用"未知来源"后安装。

## iOS

iOS 用户可以选择以下几种安装方式：

### 方式一：TestFlight 公开测试版（推荐）

1. 在 iOS 设备上打开 App Store，搜索并下载 TestFlight 应用
2. 点击以下链接加入测试：[NipaPlay TestFlight 公开测试](https://testflight.apple.com/join/4JMh3t44)
3. 在 TestFlight 中点击"接受"，然后点击"安装"
4. 等待应用下载完成即可使用

**优势**：
- 无需复杂配置，一键安装
- 自动更新通知
- TestFlight 测试版本有效期为 90 天
- 官方测试渠道，安全可靠

### 方式二：Xcode 自签名（技术用户）

如果您有 macOS 设备并熟悉 Xcode 开发：

1. **准备环境**：
   - 一台 macOS 设备
   - Xcode（从 App Store 免费下载）
   - iOS 设备和数据线

2. **获取源码**：
   - 从 [Release 页面](https://github.com/Shinokawa/NipaPlay-Reload/releases) 下载源码包

3. **配置和构建**：
   - 解压源码并用 Xcode 打开 `ios/Runner.xcworkspace`
   - 配置 Bundle Identifier 和开发者签名
   - 连接设备并构建安装

### 方式三：侧载工具安装（不推荐）

**注意**：侧载方式需要定期重新签名，维护成本较高，建议优先使用 TestFlight。

**使用爱思助手**：

1. 在电脑上下载并安装 [爱思助手](https://www.i4.cn/)
2. 从 [Release 页面](https://github.com/Shinokawa/NipaPlay-Reload/releases) 下载 `.ipa` 文件
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
