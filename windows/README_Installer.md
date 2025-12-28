# NipaPlay Windows 安装程序 (Inno Setup 版本)

目前 GitHub Actions 使用 Inno Setup 6 来生成 Windows 安装程序，并启用 `WizardStyle=modern` 的现代向导界面（整体观感会比 NSIS 经典向导更现代）。

## 功能特性

### 安装程序功能
- **现代化界面**: Inno Setup 6 `WizardStyle=modern`
- **完整中文支持**: 通过 Inno Setup 语言包支持简体中文界面
- **自动文件关联**: 支持常见视频格式（.mp4, .mkv, .avi, .mov, .wmv, .flv, .webm等）
- **权限与安装目录**: 默认按用户安装（无需管理员），也可按需选择管理员模式安装
- **可选任务**: 用户可选择创建桌面快捷方式、启用文件关联等
- **卸载功能**: Inno Setup 自带完整卸载与清理
- **多语言**: 支持中文和英文界面切换

### 视觉效果
- **安装器图标**: 使用 `windows/runner/resources/app_icon.ico`
- **现代向导风格**: 采用 Inno Setup modern wizard 样式

## 文件说明

### nipaplay_installer.nsi（历史遗留）
旧的 NSIS 脚本已不再被 GitHub Actions 使用（保留仅供参考）。

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
