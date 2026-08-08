# 更新与发布通道

NipaPlay 提供多种获取更新的方式，选择最适合你平台的方法来保持应用为最新版本。

## GitHub Releases（所有平台）

**发布地址**：[GitHub Release 页面](https://github.com/AimesSoft/NipaPlay-Reload/releases)

**更新方式**：

1. 定期访问 Release 页面查看新版本
2. 下载对应平台的安装包
3. 按常规方式安装（会覆盖旧版本）

## macOS - Homebrew（推荐）

**更新步骤**：

```bash
# 1. 更新 Homebrew 软件源
brew update

# 2. 升级 NipaPlay 到最新版本
brew upgrade nipaplay-reload
```

**优势说明**：

- 通过 Homebrew 更新时，系统不会再次要求在"隐私与安全性"中手动允许应用
- 自动处理依赖关系和清理旧版本

## Windows

**更新方式**：

- 手动检查：访问 [GitHub Releases](https://github.com/AimesSoft/NipaPlay-Reload/releases)
- 下载最新的安装包或压缩包
- 运行安装程序（会自动覆盖旧版本）

## Android

**更新方式**：

- 手动检查新版本并下载对应架构的 APK
- 安装时系统会提示"更新应用"
- 无需卸载旧版本

## HarmonyOS

- 当前以源码构建 HAP 为主，没有与 Android APK 等价的稳定公开更新通道。
- 更新需要重新构建、签名并安装 HAP；请保留旧版本数据目录后再执行升级。
- DevEco/SDK 或设备兼容性变化可能导致构建结果不同，升级前建议记录 SDK、签名和 Erika 版本。

## tvOS

- tvOS 当前是开发者预览和侧载路径，不提供常规 GitHub 自动更新。
- 更新需要重新构建并使用有效的 tvOS 开发者签名安装；模拟器构建不等同于真机发布包。
- 版本回退前请确认应用数据模型兼容，必要时先导出设置和观看记录。

## iOS

**更新方式**：

### App Store 版本
- **自动更新**：在 App Store 设置中开启自动更新
- **手动更新**：打开 App Store → 点击头像 → 查看待更新应用

### TestFlight 版本
- **自动通知**：TestFlight 会在有新版本时发送推送通知
- **手动检查**：打开 TestFlight 应用查看更新

### 侧载版本
- 重新下载最新的 `.ipa` 文件
- 使用相同的侧载工具重新安装
- AltStore 用户可以在应用内直接更新

**签名注意**：

- 免费 Apple ID 签名有效期为 7 天，需定期刷新
- 建议在签名过期前主动更新


## 更新通知

NipaPlay在设置-关于会提示更新，发现有红色new标识标识已有新版本

您也可以关注官方发布渠道

- **GitHub**：Watch 本仓库以接收 Release 通知
- **QQ群**：加入官方QQ群 961207150 获取更新提醒

---

**⬅️ 上一篇: [隐私与数据](privacy.md)** | **🏠 返回首页: [欢迎来到 NipaPlay 文档](index.md)**
