# 下载与开启

Next 与 Classic 同属一个 NipaPlay 安装包，在 Classic 的实验室中开启。

## 安装包

[GitHub 发行页](https://github.com/AimesSoft/NipaPlay-Reload/releases) 中版本号为 `2.0.0-alpha.*` 的预发布版本包含 Next。当前预览的附件：

| 平台 | 文件 | 其他格式 |
|---|---|---|
| macOS（Apple 芯片） | `NipaPlay_…_macOS_AppleSilicon.dmg` | `.pkg`、`.zip`；`Universal` 同时支持 Apple 芯片和 Intel |
| macOS（Intel） | `NipaPlay_…_macOS_Intel.dmg` | `.pkg`、`.zip` |
| Windows x64 | `NipaPlay_…_Windows_x64_Setup.exe` | `.zip` 便携包、`.msix` |
| Linux | `NipaPlay-…-Linux-amd64.deb` 等 | amd64、arm64 的 DEB、RPM、tar.gz；amd64 另有 AppImage |
| Linux 无界面版 | `NipaPlay-Headless_…_Linux_amd64.tar.gz` | arm64 版本；见 [Linux 无界面版](../advanced/headless.md) |
| iPhone、iPad | `NipaPlay_…_iOS_arm64.ipa` | 未签名，需自行签名侧载；TestFlight 以发行页说明为准 |
| Apple TV | `NipaPlay-…-tvOS-arm64-sideload.ipa` | 未签名，需自行签名侧载；TestFlight 与 iPhone 版同属一个 App |

本次预览不包含 Android 和 HarmonyOS。macOS 的 App Sandbox 版本不提供 Next 开关，需使用 GitHub 发行的完整版。

## 风险

梨花在运行她的设备上以当前系统用户的权限工作：

- 读写、覆盖和删除该用户可访问的文件，范围包括媒体库以外的位置；
- 运行程序、访问网络，使用该用户已有的账号和登录状态。

NipaPlay 对删除磁盘文件要求本机确认；梨花通过命令行或脚本执行的操作不经过这一确认。模型误判、软件缺陷，以及网页、文件名、字幕中的恶意文字，可能导致数据丢失、凭据泄露、账号操作和额外费用。关闭 Next、切回 Classic 或卸载应用，不会撤销已经执行的操作。

组网后，同账号的已认证设备可以调用本机开放的能力，读取本机进程可访问的文件。开启「允许别的设备在这里运行程序」后，其他设备上的梨花可以在本机执行程序。

建议在测试设备、独立的系统账号或数据副本上使用，开启前按[数据与恢复](../advanced/data-and-recovery.md)备份。

## 开启

1. 打开 NipaPlay，进入 Classic 的「设置」→「实验室」。
2. 打开「开启 NipaPlay Next（开发者预览）」。
3. 阅读风险说明和免责声明，选择「我了解风险，开启」。界面切换到 Next。

iPhone、iPad 和 Apple TV 本机不运行梨花，开启时的说明针对其他设备上的梨花操作本机的情形；删除文件和账号登录在本机确认。

## 界面

顶栏依次为「首页」「媒体库」「发现」「动态」、搜索、「设置」和梨花的对话入口。尚未配置模型时，对话入口显示为「设置梨花」。

手机上，各页面和搜索位于底栏，底栏上方一行是梨花的对话入口，点麦克风直接开始听写；顶栏右侧的菜单中有「设置」和「回到经典界面」。电视上用遥控器在顶栏和页面之间移动焦点。

| 页面 | 内容 |
|---|---|
| 首页 | 主视觉、继续观看、最近添加、梨花摆放的书架 |
| 媒体库 | 所有来源的作品，按分类或来源原有结构浏览 |
| 发现 | 放送表和推荐，来自弹弹play 等来源 |
| 动态 | 进行中的后台任务、梨花在追的作品、下载、观看记录 |

## 回到 Classic

「设置」→「经典界面」→「回到经典界面」，顶栏菜单中也有同一入口。再次进入 Next 使用实验室中的同一开关。

观看进度和部分设置由两套界面共用，Next 中明确的作品绑定会同步给 Classic。Next 的作品资料、对话和梨花的记忆保存在 Next 自己的数据库与个人 harness 中，切换界面不改变这些数据，见[数据与恢复](../advanced/data-and-recovery.md)。

---

上一篇：[文档首页](../README.md) · 下一篇：[配置梨花](setup-nipa.md)
