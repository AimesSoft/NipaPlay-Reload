# 字幕和弹幕

先确认目标设备、文件/剧集与当前播放会话，再用 `nipa describe subtitle`、`nipa describe danmaku` 和具体 Action 查询 schema、来源和前置。没有播放器的宿主可以保存部分事实，但不能证明画面上已显示。

## 字幕

1. `subtitle.tracks` 读取文件候选、trackId、语言、来源、选择及 revision；播放中另查 `playback.tracks`。使用 `subtitle.cues` 可读活跃外挂字幕时间线；内嵌文本或位图不因此变成已识别文字。
2. 用户需要外挂字幕时用 `subtitle.import` 交入，再用 `subtitle.select` 记住选择，或用 `playback.select_track` 只控制当前会话；检查 `remember` 与目标返回事实。`subtitle.select` 的 null 表示禁用；`subtitle.reset_selection` 清除显式选择并恢复自动选择，headless 的选择可能为 null。
3. `subtitle.update/remove` 按读取到的 revision 修改或解除关联；解除关联保留磁盘副本。删除未引用的管理副本用 `subtitle.copy_delete`：先检查预览和指纹，在用户同意后按契约确认；引用变化会拒绝。不要把移除关联当成删除原始文件。
4. 用 `subtitle.tracks` 和当前播放器状态回读选择。会话发生变化或 revision 冲突时重新读取事实，不沿用旧预览。

## 弹幕

1. `danmaku.sources/search/episodes/resolve` 提供来源与候选；核对作品、准确剧集和实际来源 ID。正常整理只用 `danmaku.bind` 或媒体身份绑定记录判断；它不等同于已下载或已挂载。
2. 用户明确要求提前准备时用 `danmaku.prepare` / `danmaku.fetch`，并查看任务与回执。`danmaku.import` 交入已有 XML/JSON 文件并保存来源；同平台视频的再次导入可能替换已有池，先确认目标与意图。批量动作逐项返回，非原子，检查每项结果。
3. `danmaku.tracks` 读绑定、启用、偏移、loaded 等事实；`loaded` 表示已挂载，不证明画面上此刻可见。调整用 `danmaku.update` 或对应兼容入口，按 revision 核验；对齐先用 `danmaku.analyze_alignment`，再明确选择修改。`danmaku.align` 仅保留旧请求恢复，不用于新对齐。
4. 清理或删除弹幕池、导出文件和在线 `danmaku.send` 都有副作用；先查看具体 Action 的影响与用户授权。发送发布到线上，响应丢失不能盲目重发。

`outcome_unknown` 时保留原设备、请求 ID 和来源，先查询任务、绑定及相关回执；只按目标 Action 明示的幂等契约重试。批量中部分成功时不要把整批当作未执行。

参考：[字幕能力](../../../../lib/next/subtitles/README.md)、[弹幕能力](../../../../lib/next/danmaku/capability.dart)、[过程事实契约](../../OBSERVABILITY_CONTRACT.md)。
