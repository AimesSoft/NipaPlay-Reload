# NipaPlay 文件关联设置指南

本指南将帮助您在不同操作系统上将 NipaPlay 设置为视频文件的默认打开方式，以及如何使用拖拽功能。

## 支持的视频格式

NipaPlay 支持以下视频格式：
- MP4 (.mp4)
- Matroska (.mkv)
- AVI (.avi)
- QuickTime (.mov)
- WebM (.webm)
- Windows Media Video (.wmv)
- MPEG-4 (.m4v)
- 3GP (.3gp)
- Flash Video (.flv)
- MPEG Transport Stream (.ts, .m2ts)

## 拖拽播放功能

### 桌面平台（Windows/macOS/Linux）

NipaPlay 支持直接拖拽视频文件到应用窗口或应用图标/任务栏图标进行播放：

#### 拖拽到应用窗口
1. 打开 NipaPlay 应用
2. 从文件管理器中选择视频文件
3. 直接拖拽到 NipaPlay 窗口中
4. 松开鼠标，视频将自动开始播放

#### 拖拽到应用图标/任务栏图标
1. 从文件管理器中选择视频文件
2. 拖拽到以下位置之一：
   - **Windows**: 任务栏中的 NipaPlay 图标，或桌面/开始菜单中的快捷方式
   - **macOS**: Dock 中的 NipaPlay 图标，或 Applications 文件夹中的应用图标
   - **Linux**: 桌面或启动器中的 NipaPlay 图标
3. 松开鼠标，NipaPlay 将启动并播放该视频

#### 多文件拖拽
- 如果同时拖拽多个文件，NipaPlay 将自动选择第一个支持的视频文件进行播放
- 不支持的文件格式将被自动忽略

## Android 设置

### 自动设置
1. 安装 NipaPlay 后，尝试打开任何支持的视频文件
2. Android 系统会询问您要使用哪个应用打开该文件
3. 选择 "NipaPlay" 并勾选 "始终使用此应用打开"

### 手动设置
1. 进入 "设置" > "应用管理"
2. 找到并点击 "NipaPlay"
3. 点击 "默认打开"
4. 添加支持的文件类型关联

## iOS 设置

### 通过文件应用
1. 在 "文件" 应用中找到视频文件
2. 长按视频文件，选择 "共享"
3. 选择 "NipaPlay" 打开

### 通过其他应用
1. 在其他应用中找到视频文件
2. 点击 "分享" 按钮
3. 选择 "在 NipaPlay 中打开"

注意：iOS 系统限制较严，可能无法完全替代系统默认播放器。

## macOS 设置

### 方法一：右键菜单设置
1. 右键点击任意视频文件
2. 选择 "打开方式" > "其他..."
3. 选择 NipaPlay 应用
4. 勾选 "始终以此方式打开"

### 方法二：文件信息设置
1. 选中视频文件，按 Cmd+I 打开文件信息
2. 在 "打开方式" 部分选择 NipaPlay
3. 点击 "全部更改..." 应用到所有同类型文件

### 方法三：系统偏好设置
1. 打开 "系统偏好设置" > "通用"
2. 设置默认应用程序（如果可用）

## Windows 设置

### 方法一：应用内设置（推荐）
1. 打开 NipaPlay 应用
2. 进入 "设置" > "通用"
3. 找到 "文件关联设置" 卡片
4. 点击 "配置文件关联" 按钮
5. 在弹出的 UAC 对话框中点击 "是" 以获得管理员权限
6. 等待配置完成

### 方法二：安装脚本
1. 导航到 NipaPlay 安装目录
2. 右键点击 `install_file_association.bat` 文件
3. 选择 "以管理员身份运行"
4. 按提示完成安装

### 方法三：手动设置
1. 右键点击任意视频文件
2. 选择 "打开方式" > "选择其他应用"
3. 浏览并选择 NipaPlay.exe
4. 勾选 "始终使用此应用打开 .xxx 文件"

### 方法四：设置应用（Windows 10/11）
1. 打开 "设置" > "应用" > "默认应用"
2. 点击 "按文件类型选择默认应用"
3. 找到相应的视频格式，设置为 NipaPlay

## Linux 设置

### 通过桌面环境
1. 右键点击视频文件
2. 选择 "属性" 或 "打开方式"
3. 选择 NipaPlay 作为默认应用

### 通过命令行
```bash
# 使用 xdg-mime 设置默认应用
xdg-mime default nipaplay.desktop video/mp4
xdg-mime default nipaplay.desktop video/x-matroska
xdg-mime default nipaplay.desktop video/avi
xdg-mime default nipaplay.desktop video/quicktime
xdg-mime default nipaplay.desktop video/webm
```

### 通过 desktop 文件
确保 `io.github.MCDFsteve.NipaPlay-Reload.desktop` 文件已正确安装到：
- `/usr/share/applications/` （系统级）
- `~/.local/share/applications/` （用户级）

## 验证设置

设置完成后，您可以：
1. 双击任意支持的视频文件
2. 确认 NipaPlay 自动启动并开始播放
3. 如果未成功，请重复上述步骤或重启设备

## 故障排除

### 文件关联未生效
- 重启文件管理器或系统
- 检查应用是否有足够权限
- 确认文件格式在支持列表中

### 应用无法启动
- 检查 NipaPlay 是否正确安装
- 确认应用有执行权限
- 查看系统错误日志

### 权限问题
- Android：确保应用有存储权限
- macOS：检查安全性与隐私设置
- Windows：以管理员身份运行

## 技术说明

### 文件关联实现
- **Android**：使用 Intent Filter 声明支持的 MIME 类型和文件扩展名
- **iOS**：通过 CFBundleDocumentTypes 声明文档类型，使用 UTImportedTypeDeclarations 定义自定义类型
- **macOS**：类似 iOS，使用 UTImportedTypeDeclarations 和 CFBundleDocumentTypes
- **Windows**：通过注册表项和批处理脚本自动配置文件关联
- **Linux**：通过 MIME 类型和 desktop 文件设置，支持 XDG 标准

### 拖拽功能实现
拖拽到应用图标/任务栏图标的实现原理：
1. **命令行参数传递**：操作系统将拖拽的文件路径作为命令行参数传递给应用
2. **启动时解析**：应用在 `main()` 函数中解析命令行参数 `List<String> args`
3. **自动播放**：验证文件格式后自动切换到播放页面并开始播放

拖拽到应用窗口的实现：
1. **平台通道**：通过 Flutter MethodChannel 与原生代码通信
2. **事件监听**：原生代码监听拖拽事件并传递文件路径
3. **回调处理**：Flutter 接收拖拽事件并处理文件播放

这种实现方式确保了在所有桌面平台上的一致体验，用户可以通过多种方式快速打开视频文件。

如有问题，请查看应用内的调试日志或联系开发者。 