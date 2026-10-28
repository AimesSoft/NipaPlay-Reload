# 按任务操作 Next

先在实际执行设备用 `nipa status`、`nipa list`、`nipa describe ACTION` 和 `nipa call app.capabilities '{}'` 查询当前事实。目标是其他设备时使用 `nipa --device NAME list` / `describe`；具体 schema、可用前置和设备差异以目标实时结果为准。Windows 使用 `python nipa`，JSON 可由 UTF-8 文件或标准输入传入。受理任务不是完成，查看任务状态及回执。

- [播放、控制与诊断](playback.md)
- [Mesh 跨设备操作](mesh.md)
- [媒体身份、资料与合并](media-identity.md)
- [字幕和弹幕](subtitles-danmaku.md)
- [媒体来源与下载](downloads-sources.md)
- [首页、分类与图片](library-presentation.md)
- [任务、自动化与记忆](automation-memory.md)
- [账号、设置与维护](maintenance-accounts.md)

推荐不等于执行：用户明确要求后执行对应操作；涉及删除、覆盖或其他设备上的写入时遵循用户授权和目标设备的确认规则。参考 [能力总览](../../CAPABILITIES.md)、[Action 源码参考](../ACTION_REFERENCE.md) 和 [过程事实契约](../../OBSERVABILITY_CONTRACT.md)。
