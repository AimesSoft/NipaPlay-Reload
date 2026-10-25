# NipaPlay Windows 安装程序 (Inno Setup 版本)

目前 GitHub Actions 使用 Inno Setup 6 来生成 Windows 安装程序，并启用 `WizardStyle=modern` 的现代向导界面（整体观感会比 NSIS 经典向导更现代）。

## 功能特性

### 安装程序功能
- **现代化界面**: Inno Setup 6 `WizardStyle=modern`
- **完整中文支持**: 通过 Inno Setup 语言包支持简体中文界面
- **自动文件关联**: 支持常见视频格式（.mp4, .mkv, .avi, .mov, .wmv, .flv, .webm等）
- **权限与安装目录**: 按管理员安装到 `Program Files\NipaPlay`（安装时提升一次，之后运行应用不需要提升：可变数据都在用户的 Documents\nipaplay 和 AppData 里）。以前按“只为我安装”装在 `%LOCALAPPDATA%\Programs\NipaPlay` 的，新安装器会先静默卸载旧的程序文件（不动用户数据），避免装出两份
- **可选任务**: 用户可选择创建桌面快捷方式、启用文件关联等
- **卸载功能**: Inno Setup 自带完整卸载与清理
- **多语言**: 支持中文和英文界面切换

### 视觉效果
- **安装器图标**: 使用 `windows/runner/resources/app_icon.ico`
- **现代向导风格**: 采用 Inno Setup modern wizard 样式

## 文件说明

### nipaplay_installer.nsi（历史遗留）
旧的 NSIS 脚本已不再被 GitHub Actions 使用（保留仅供参考）。它同样会在安装时添加防火墙放行规则、卸载时删除；编译时 `nipaplay_firewall.ps1` 要和 `.nsi` 放在同一个目录。

### 安装程序生成的文件
构建过程中会生成：
- `NipaPlay_{version}_Windows_x64.zip`（绿色版）
- `NipaPlay_{version}_Windows_x64_Setup.exe`（安装版，Inno Setup）

## 构建流程

安装程序的构建过程集成在 GitHub Actions 中，核心逻辑在：
- `.github/actions/build-windows/action.yml`：安装 Inno Setup、生成 `.iss` 脚本并调用 `ISCC.exe` 编译

## 输出文件

每次构建会生成两种Windows分发包：
- **压缩包**: `NipaPlay_{version}_Windows_{arch}.zip` - 绿色版，直接解压运行
- **安装程序**: `NipaPlay_{version}_Windows_{arch}_Setup.exe` - 完整安装包（Inno Setup），可选文件关联

## 注意事项

- **中文界面**: 若 runner 的 Inno Setup 缺少 `ChineseSimplified.isl`，工作流会尝试自动下载补齐
- **文件关联**: 仅在用户勾选对应任务时写入 HKCU 的文件关联注册表项
- **防火墙**: 任务 `firewall`（默认勾选）为安装的 `NipaPlay.exe` 添加名为 `NipaPlay` 的入站放行规则（TCP 和 UDP，只放行域和专用网络，不含公用网络），并删除指向同一个 exe 的入站 Block 规则（Windows 在首次弹窗被取消后自动建的）。逻辑在 `windows/nipaplay_firewall.ps1`，安装器把它带进临时目录用 netsh 执行；失败不影响安装，只写进 `/LOG` 日志。卸载时删除指向这个 exe 的同名规则。压缩包（便携版）和 MSIX 不带这条规则
- **MSIX**: 使用的 `msix` 包（3.16.13）生成的清单里没有 `windows.firewallRules` 扩展，没法声明防火墙规则，MSIX 版首次监听端口时仍由 Windows 弹防火墙窗
