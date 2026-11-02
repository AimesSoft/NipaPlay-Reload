# 下载与开启 Next

Next 不是单独的应用：它和 Classic 装在同一个 NipaPlay 里，在 Classic 的实验室开启后进入。本篇说明下载哪个包、怎样开启，以及开启前必须知道的风险。

## 下载哪个安装包

从 [GitHub 发行页](https://github.com/AimesSoft/NipaPlay-Reload/releases) 下载带 `2.0.0-alpha` 字样的预发布版本。以 Alpha 2 为例：

| 平台 | 文件 | 说明 |
|---|---|---|
| macOS（Apple 芯片） | `NipaPlay_…_macOS_AppleSilicon.dmg` | 也有 `.pkg` 和 `.zip`；`Universal` 同时支持 Apple 芯片和 Intel |
| macOS（Intel） | `NipaPlay_…_macOS_Intel.dmg` | 同上 |
| Windows x64 | `NipaPlay_…_Windows_x64_Setup.exe` | 安装程序；另有 `.zip` 便携包和 `.msix` |
| Linux | `NipaPlay-…-Linux-amd64.deb` 等 | amd64、arm64 的 DEB、RPM、tar.gz；amd64 另有 AppImage |
| Linux 服务器（无界面） | `NipaPlay-Headless_…_Linux_amd64.tar.gz` | 没有图形界面，见 [Linux 无界面版](../advanced/headless.md) |
| iPhone / iPad | `NipaPlay_…_iOS_arm64.ipa` | 未签名，需自行签名侧载；TestFlight 是否开放以发行页为准 |

Android、tvOS 和 HarmonyOS 不在本次预览范围内。

**macOS 必须用 GitHub 下载的完整版。** App Store 版运行在 App Sandbox 中，不提供 Next。

## 开启前：梨花能做什么

Next 里的梨花是一个**拥有完整用户级权限的 AI Agent**，不是只会回答问题的聊天窗口。在运行梨花的电脑上，她可以在当前系统用户的权限范围内：

- 读写、覆盖或删除文件，范围不限于媒体库；
- 运行程序、联网，使用这个用户可访问的账号和浏览器登录状态；
- 并非每一步都会再弹窗确认。

模型可能判断错误，网页、文件名、字幕、简介里的恶意文字也可能误导她，造成数据丢失、隐私或凭据泄露、账号操作和额外费用。关闭 Next、切回 Classic 或卸载应用，都不会撤销她已经做过的操作。

组网后风险会延伸到其他设备：同账号认证的设备可以调用本机开放的能力、读取可访问的文件；开启"允许别的设备在这里运行程序"后，别的设备上的梨花还能在本机执行程序。

建议：

- 在测试设备、独立系统账号或可丢弃的数据副本上试用；
- 开启前按[数据与恢复](../advanced/data-and-recovery.md)备份；
- 只加入你信任的设备，只选你信任的模型服务商。

## 开启 Next

1. 安装并打开 NipaPlay，进入 Classic 的「设置」→「实验室」。
2. 打开「开启 NipaPlay Next（开发者预览）」。
3. 阅读弹出的风险说明和免责声明，选择「我了解风险，开启」。界面会直接切换到 Next。

在 iPhone/iPad 上开启时，提示内容不同：手机本身不运行梨花，风险说明的是同账号其他设备上的梨花可以操作这台设备上的 NipaPlay；删除文件和账号登录仍需要在本机确认。

## Next 的界面

顶栏从左到右是「首页」「媒体库」「发现」「动态」和搜索，右侧是「设置」和梨花的对话入口。还没有配置模型时，对话入口显示「设置梨花」，下一篇就从这里开始。

- **首页**：继续观看、最近添加、梨花摆的书架。
- **媒体库**：所有来源的作品，可以按分类或原始来源浏览。
- **发现**：放送表和推荐，依赖弹弹play 等来源。
- **动态**：进行中的后台任务、下载和观看记录。

## 回到 Classic

在 Next 的「设置」→「经典界面」选择「回到经典界面」；顶栏菜单里也有同一入口。之后再进入 Next，仍然用实验室里的同一个开关。

两套界面的数据并非完全隔离。观看进度和部分设置是共用的，某些明确的媒体操作会同步到 Classic；Next 的作品资料、对话和梨花的记忆则保存在 Next 自己的数据库里。所以切换界面不等于回滚，见[数据与恢复](../advanced/data-and-recovery.md)。

---

上一篇：[文档首页](../README.md) · **➡️ 下一篇：[配置梨花](setup-nipa.md)**
