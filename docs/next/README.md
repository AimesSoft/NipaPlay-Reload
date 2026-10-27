# NipaPlay Next 开发者预览文档

Next `v2.0.0-alpha.1` 是 Developer Preview：功能和数据格式仍可能变化，请先备份重要数据。 本次发行范围为 macOS、Windows、Linux、Linux headless 和 iPhone/iPad；Android、tvOS 和 HarmonyOS 不在本次发行范围。构建成功不等于对应设备已经实机验收；发行页面和关于页中的版本、构建号与提交是反馈时的依据。

## 使用者

- [快速开始](QUICKSTART.md)：安装后配置梨花并完成第一个任务。
- [使用指南](USER_GUIDE.md)：对话、媒体库、Mesh 与数据边界。
- [数据与恢复](DATA_AND_RECOVERY.md)：Classic 备份与 Next 数据的范围。
- [DSH 高级配置](DSH_ADVANCED_CONFIG.md)：模型预算、压缩和插件配置。
- [Headless](HEADLESS.md)：无界面节点的安装与运行。

## 开发者

- [Next 架构入口](../../lib/next/README.md)，以及各子目录的 README。
- [技术架构](ARCHITECTURE.md)：宿主、运行器、媒体身份、Mesh 与数据边界。
- [能力使用参考](CAPABILITIES.md)：按任务查找工具，以目标设备实时契约为准。
- [研究纲领](RESEARCH.md)：Next 的核心假设、Classic 隔离与个人 harness。
- [发布流程与平台说明](ALPHA_RELEASE.md)：本次直接 prerelease 的 CI 和可选候选流程。
- [PR 差异范围核查](PR_SCOPE_AUDIT_20261028.md)：解释 PR 的基线、规模与文件用途。

## 历史记录

本目录中的 `X*`、`Y*` 报告及 `archive/` 记录特定阶段的设计和测试，不自动代表当前版本的验收结果。请结合当前源码、构建和实机记录核对。
