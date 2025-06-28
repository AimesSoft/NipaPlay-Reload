# NipaPlay Windows 安装程序

这个目录包含了用于创建NipaPlay Windows安装程序的配置文件。

## 功能特性

### 安装程序功能
- **现代化界面**: 使用Inno Setup的现代风格界面
- **自动文件关联**: 支持常见视频格式（.mp4, .mkv, .avi, .mov, .wmv, .flv, .webm）
- **架构支持**: 自动检测和支持x64和ARM64架构
- **多语言**: 支持中文和英文界面
- **卸载功能**: 提供完整的卸载支持
- **快捷方式**: 可选择创建桌面和快速启动栏图标

### 视觉效果
- **自定义图标**: 使用项目logo作为安装程序图标
- **品牌背景**: 使用项目主视觉图片作为安装程序背景
- **统一风格**: 与应用主体保持一致的视觉风格

## 文件说明

### nipaplay_installer.iss
Inno Setup脚本文件，包含：
- 应用程序信息和版本
- 文件和目录配置
- 注册表项（文件关联）
- 界面自定义设置
- 多语言支持配置

### 安装程序生成的文件
构建过程中会自动生成：
- `nipaplay_icon.ico` - 从项目icon.png转换的安装程序图标
- `installer_banner.bmp` - 从main_image.png裁剪的大横幅图片
- `installer_small.bmp` - 从main_image.png裁剪的小图标图片

## 构建流程

安装程序的构建过程集成在GitHub Actions工作流中：

1. **图片处理**: 
   - 使用ImageMagick处理项目美术素材
   - 将icon.png转换为ICO格式
   - 从main_image.png裁剪合适尺寸的背景图片

2. **环境准备**:
   - 安装Inno Setup
   - 复制必要文件到构建目录

3. **脚本定制**:
   - 根据目标架构（x64/ARM64）定制安装脚本
   - 设置正确的文件名和架构限制

4. **编译打包**:
   - 使用Inno Setup编译器生成安装程序
   - 输出格式：`NipaPlay_{version}_Windows_{arch}_Setup.exe`

## 输出文件

每次构建会生成两种Windows分发包：
- **压缩包**: `NipaPlay_{version}_Windows_{arch}.zip` - 绿色版，直接解压运行
- **安装程序**: `NipaPlay_{version}_Windows_{arch}_Setup.exe` - 完整安装包，包含文件关联

## 注意事项

- 安装程序会自动注册视频文件关联
- 支持静默安装和卸载
- ARM64版本仅在ARM64设备上可安装
- x64版本兼容x64和兼容的x86设备 