# 更新与发布通道

NipaPlay 提供多种获取更新的方式，选择最适合你平台的方法来保持应用为最新版本。

## GitHub Releases（所有平台）

**发布地址**：[GitHub Release 页面](https://github.com/Shinokawa/NipaPlay-Reload/releases)

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

## Arch Linux - AUR

**包名**：`nipaplay-reload-bin`

**更新方式**：

使用 `paru`：

```bash
# 检查可更新的 AUR 包
paru -Sua

# 更新 NipaPlay
paru -S nipaplay-reload-bin
```

使用 `yay`：

```bash
# 检查可更新的 AUR 包  
yay -Sua

# 更新 NipaPlay
yay -S nipaplay-reload-bin
```

## Windows

**更新方式**：

- 手动检查：访问 [GitHub Releases](https://github.com/Shinokawa/NipaPlay-Reload/releases)
- 下载最新的安装包或压缩包
- 运行安装程序（会自动覆盖旧版本）

## Android

**更新方式**：

- 手动检查新版本并下载对应架构的 APK
- 安装时系统会提示"更新应用"
- 无需卸载旧版本

## iOS

**更新方式**：

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
