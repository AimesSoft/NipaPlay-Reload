# NipaPlay Next 使用文档

NipaPlay Next 是 NipaPlay 的新界面：媒体库、播放器之外，多了一位叫**梨花**的 AI 助手。你用对话说出想做的事——找片、下载、整理资料、调整首页——梨花查询信息、调用 NipaPlay 的功能完成它，结果出现在片库、作品详情和播放器里。

Next 目前是**开发者预览**。梨花拥有完整的用户级系统权限，可以读写和删除文件、运行程序、联网。开启前请读完[下载与开启](start/install.md)里的风险说明，并在可以承受损失的环境中试用。

> **文档版本**：本文档跟随 `next` 开发分支更新，可能描述尚未发布的功能。已安装 Alpha 2 的用户，请阅读 [Alpha 2 时的文档](https://github.com/AimesSoft/NipaPlay-Reload/tree/v2.0.0-alpha.2/docs/next)。各版本的更新内容见[更新说明](release-notes.md)。

## 第一次使用

照着下面三篇做完，就能和梨花对话、看上第一部片：

1. [下载与开启 Next](start/install.md)：下载哪个安装包，怎样从 Classic 进入 Next。
2. [配置梨花](start/setup-nipa.md)：推荐的模型配置、填写步骤，以及怎样确认配置真的可用。
3. [第一次使用](start/first-day.md)：添加一个视频文件夹，匹配作品，播放，再和梨花说第一句话。

## 日常使用

- [和梨花对话](use/nipa.md)：怎么提要求，怎么看她做了什么，提醒、确认、记忆和对话历史。
- [媒体库与来源](use/library.md)：本机文件夹、SMB、WebDAV、Jellyfin、Emby；匹配作品、整理资料、作品详情页。
- [播放](use/playback.md)：播放器菜单、字幕与弹幕、播放内核、续播和截图。
- [下载](use/downloads.md)：磁力链接、种子和 HTTP 下载，qBittorrent 等下载后端。
- [首页与书架](use/home.md)：首页书架、主视觉、媒体库分类和图片。
- [多台设备](use/devices.md)：设备组网，在 iPad/iPhone 上使用另一台设备的梨花。
- [可以让梨花做什么](use/examples.md)：按场景列出可以直接说的请求。

## 进阶

- [自动化与个人工具](advanced/automation.md)：定时任务、事件触发、个人工具和数据库查询。
- [DSH 高级配置](advanced/dsh-config.md)：上下文预算、压缩和插件。
- [数据与恢复](advanced/data-and-recovery.md)：备份什么、怎样恢复和迁移。
- [Linux 无界面版](advanced/headless.md)：在服务器上运行 NipaPlay 和梨花。

## 遇到问题

- [常见问题](help/faq.md)：测试连接成功却不会用工具、模型拒绝下载、设备在线却不能播放等。
- [故障排查](help/troubleshooting.md)：复制诊断信息、查看日志、提交反馈。
- [已知问题](help/known-issues.md)：当前版本的限制。

---

想了解 Next 的设计与实现、`nipa` 命令行和完整能力目录，请看[开发者文档](development/README.md)。

**➡️ 下一篇：[下载与开启 Next](start/install.md)**
