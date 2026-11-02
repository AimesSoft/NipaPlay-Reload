# Next 开发者文档

这里描述 Next 的设计、能力目录和实现边界，面向想了解内部结构、调用 `nipa` 或参与开发的人。具体行为以当前源码和目标设备的实时能力（`nipa list` / `nipa describe`）为准。

## 从这里开始

- [设计原则](principles.md)：梨花与 NipaPlay 怎样分工，什么不该做。
- [技术架构](ARCHITECTURE.md)：宿主、运行器、媒体身份、Mesh 与数据边界。
- [应用模型](reference/README.md)：媒体、执行、设备与 Agent 的概念和生命周期。

## 能力与工具

- [能力使用参考](CAPABILITIES.md)：按任务查找能力。
- [按任务操作](guides/README.md)：播放、Mesh、媒体身份、字幕与弹幕等跨能力流程。
- [完整 Action 参考](ACTION_REFERENCE.md)：逐项列出应用动作的用途、影响和源码位置。
- [Action 覆盖核对](ACTION_COVERAGE.md)：目录怎样从源码提取，动态注册与校验的边界。
- [工具指引契约](TOOL_GUIDANCE.md)：随工具一起提供给梨花的调用说明，以及维护要求。
- [界面、书架与图片能力](UI_CAPABILITIES.md)：首页主视觉、分类排列、图片覆盖与设备归属。

## 运行与诊断

- [可观测性契约](OBSERVABILITY_CONTRACT.md)：运行状态、回执与诊断的统一约定。
- [安装包内的知识参考](KNOWLEDGE.md)：打包进应用、供梨花检索的只读知识，以及版本边界。
- [自动化与个人工具](../advanced/automation.md) · [DSH 高级配置](../advanced/dsh-config.md) · [Linux 无界面版](../advanced/headless.md)

## 设计稿

- [交互规范](design/INTERACTION.md)
- [播放会话层](design/player-core.md)

## 源码

- [源码架构入口](../../../lib/next/README.md)：各领域的实现与子目录文档。

---

返回[用户文档](../README.md)。
