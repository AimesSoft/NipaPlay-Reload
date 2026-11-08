# NipaPlay Next

[订阅与自动下载](use/subscriptions.md)：请梨花追番、追剧，配置来源和保险库密钥。

NipaPlay Next 是 NipaPlay 的 Agent 模式。媒体库、播放器、下载器和弹幕由 AI 助手**梨花**操作：用户提出目标，梨花查询实时状态，调用 NipaPlay 的能力完成工作，结果呈现在媒体库、作品详情和播放器中。

Next 处于开发者预览阶段。梨花以当前系统用户的权限运行，可以读写和删除文件、运行程序、访问网络，风险说明见[下载与开启](start/install.md#风险)。

> 本文档跟随 `next` 分支，适用于各预览版本；只适用于特定版本的内容会注明版本。版本变化见[更新说明](release-notes.md)，各版本的限制见[已知问题](help/known-issues.md)。

## 入门

1. [下载与开启](start/install.md)：安装包、开启方式、风险。
2. [配置梨花](start/setup-nipa.md)：运行环境、推荐模型、连接验证。
3. [第一次使用](start/first-day.md)：添加媒体，由梨花整理，开始观看。

## 使用

- [和梨花对话](use/nipa.md)：对话、后台任务、提问与提醒、历史与记忆。
- [媒体库与来源](use/library.md)：来源类型、作品身份与资料、作品详情。
- [播放](use/playback.md)：播放器、内核、字幕与弹幕、续播。
- [下载](use/downloads.md)：下载后端、下载流程、任务状态。
- [首页与书架](use/home.md)：主视觉、书架、分类、图片。
- [多台设备](use/devices.md)：组网、跨设备播放、在移动设备上使用梨花。
- [请求示例](use/examples.md)：按场景列出的请求。

## 进阶

- [自动化与个人工具](advanced/automation.md)：个人 harness、`nipa` 命令行、事件程序、定时程序、SQL。
- [DSH 高级配置](advanced/dsh-config.md)：上下文预算、压缩、插件。
- [数据与恢复](advanced/data-and-recovery.md)：数据位置、备份、恢复、迁移。
- [Linux 无界面版](advanced/headless.md)：在服务器上运行 NipaPlay 和梨花。

## 排障

- [常见问题](help/faq.md)
- [故障排查](help/troubleshooting.md)：诊断信息、日志、反馈。
- [已知问题](help/known-issues.md)

---

开发者文档：[development/README.md](development/README.md)

下一篇：[下载与开启](start/install.md)
