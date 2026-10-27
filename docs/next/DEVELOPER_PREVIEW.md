# NipaPlay Next Alpha 1 · Developer Preview

`v2.0.0-alpha.1` 是面向开发者和愿意参与实验、反馈的用户的开发者预览。Next 探索一种以对话为操作入口的媒体体验：Agent 根据实时信息判断，NipaPlay 宿主执行操作并提供验证和回执，海报墙、播放器与弹幕呈现结果。

每个人的 Git harness 可以保留并逐步发展自己的工具、经验与记忆。它连接 NipaPlay 的领域工具，也可以使用 SQL 查询与整理数据；Mesh 则让同账号设备上的能力和媒体参与工作。具体能力及验证状态仍在演进，请以实际环境和操作结果为准。

## 可以探索的场景

- **整理媒体库**：Agent 查询文件和作品候选，决定归属并显式绑定；宿主执行、检查冲突并记录结果，作品资料在界面中呈现。领域工具与 SQL 为不同整理任务提供入口。
- **跨设备播放**：通过 Mesh 浏览另一台设备提供的媒体，在当前设备播放；来源端可以是桌面或 headless 节点。设备之间需要可达的直连网络。
- **让个人助手逐步适应你**：与梨花对话，使用 DSH 和配置的模型处理媒体任务；个人 harness 中的工具与经验可以随实际使用演进。

## 平台角色

| 平台 | 本次定位 |
| --- | --- |
| macOS / Windows | 主要验证平台，提供完整桌面体验。 |
| Linux | 实验性桌面构建；环境兼容性和实机体验仍需反馈。 |
| Linux headless | 实验性无界面宿主，可作为 Mesh 媒体来源和运行环境；参见 [headless 指南](https://github.com/AimesSoft/NipaPlay-Reload/blob/next/docs/next/HEADLESS.md)。 |
| iPad / iOS | 实验性远程 Nipa 身体：提供界面、播放器和 Mesh，通过其他设备上的 Nipa 工作；不启动本地 Agent 或对话宿主。计划上传 TestFlight；GitHub 无签名 IPA 仍需自行签名侧载。 |

本次不分发 Android、tvOS 或 HarmonyOS；移动端仅包含 iPhone/iPad。TestFlight 上传、Apple 处理及测试组状态以实际结果为准；尚不承诺公开邀请或外部 Beta 审核完成。可用文件以实际 Release 附件为准。

## 开始使用

- [Next 文档入口](https://github.com/AimesSoft/NipaPlay-Reload/blob/next/docs/next/README.md) · [快速开始](https://github.com/AimesSoft/NipaPlay-Reload/blob/next/docs/next/QUICKSTART.md) · [用户指南](https://github.com/AimesSoft/NipaPlay-Reload/blob/next/docs/next/USER_GUIDE.md)
- [技术架构](https://github.com/AimesSoft/NipaPlay-Reload/blob/next/docs/next/ARCHITECTURE.md) · [能力与边界](https://github.com/AimesSoft/NipaPlay-Reload/blob/next/docs/next/CAPABILITIES.md) · [研究纲领](https://github.com/AimesSoft/NipaPlay-Reload/blob/next/docs/next/RESEARCH.md)
- [数据与恢复](https://github.com/AimesSoft/NipaPlay-Reload/blob/next/docs/next/DATA_AND_RECOVERY.md) · [已知问题](https://github.com/AimesSoft/NipaPlay-Reload/blob/next/docs/next/KNOWN_ISSUES.md) · [DSH 高级配置](https://github.com/AimesSoft/NipaPlay-Reload/blob/next/docs/next/DSH_ADVANCED_CONFIG.md)

## 已知限制与反馈

这是仍在演进的预览：完整的 Next 产品内备份恢复尚未完成，真实切网、睡眠恢复和长时间播放尚缺本轮验收。请在试用和更新前备份重要数据。元数据完整度取决于来源；Mesh 不承诺穿透或中继；DSH 插件的任意组合不保证可用。各平台的构建与实机验证状态见[已知问题](https://github.com/AimesSoft/NipaPlay-Reload/blob/next/docs/next/KNOWN_ISSUES.md)。

请通过 [Bug 报告](https://github.com/AimesSoft/NipaPlay-Reload/issues/new?template=bug_report.yml) 提供版本、系统、复现步骤和关于页复制的诊断信息。Mesh 问题请附两端版本、诊断和连接方式；DSH 问题请附模型、服务商及相关配置。公开提交前请移除密钥、令牌和个人信息。
