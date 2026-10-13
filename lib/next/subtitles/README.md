# 字幕事实与当前内容

GUI 和 headless 共用 `file_subtitles`；`revision` 由每次事实保存增加，旧事实从 0 起算，
无需改变已发布迁移。`subtitle.update/remove` 只编辑导入关联，并要求读取到的修订号。
解除关联保存 `detachedPaths`，阻止当前播放注册到 Classic 的候选被再次发现。
重新导入同一内容允许恢复关联；磁盘副本默认保留。

`reset_selection` 清除显式选择并记录自动选择意图；GUI 恢复语言偏好，headless 没有
Classic 偏好，selection 为 null。`select` 的 null 仍表示禁用。单文件与批量选择会
同步当前内部播放器。GUI 候选带持久的语言、标题、来源和 trackId。

`copy_delete` 只接受管理目录中的明确路径，校验全库引用、VobSub companion、符号链接
及内容指纹；返回 NeedsDecision 后才能确认删除。导入与删除共用存储串行锁。
解除关联和更正的前后事实保存在 body_changes，清理不会删除这份审计。

`subtitle.cues` 由有播放器的宿主注册，读取活跃外挂字幕的定时文本；包含当前行及
前后行，并应用全局和每轨延迟。内嵌文字尚未抽取，位图字幕需要 OCR，均返回明确限制。
它描述字幕时间线，不声称做过像素观察。所有实时能力契约见 `nipa describe subtitle`。

`subtitle.tracks` 可用 limit/afterFileId 按文件分页，nextAfterFileId 为 null 表示结束；
不传 limit 保留完整列表语义，指定 fileIds 时返回全部指定文件，不与分页输入混用。
