# Next Action 参考（源码快照）

本表记录当前源码中可定位的公开 Action **候选并集**，包含静态和可枚举动态注册；不是任何一台设备的实时目录，也不证明线上来源可用。每个 Action 的输入、输出、实际 effect、前置及错误，以目标设备 `nipa describe ACTION`、`nipa list` 和 `app.capabilities` 为权威。用 `nipa --device NAME describe ACTION` 查询目标；不同实现可共享 ID 而有不同 schema。

列中的 read / write / destructive 是 ActionSpec 的 effect，表示接口分类，不等于纯函数、可撤销或自动确认。read 可能联网或准备缓存；write 可能产生任务、修改文件、发网络请求；destructive 也不保证弹出确认。领域预览、回执、幂等与撤回规则以具体 describe 为准。尤其 `media.mesh_files.confirm` 由调用方在用户同意后执行，宿主不会替它弹窗；`danmaku.send` 发布在线评论；SQL 提交未知先查原键回执。`danmaku.align` 是退役兼容入口，不可用于新对齐。

**宿主列**是源码组合位置的导航：Core 为桌面 Core 注册，Runtime 为 GUI 宿主额外注册，Headless 为专用实现，通用为共享领域实现或多个宿主；不等于该平台一定注册或实际可用。Headless 过滤 `download.delete` 和 `media.library.import_history`，其根目录实现与 GUI 不同。iOS body-only 过滤 `window.*`、`program.*`、`chat.*`、`agent.*`、`memory.*`、`app.quit`、`app.restart`。Mesh 列“允许”仅表示 `meshActionAllowed` 静态白名单允许对应名称，目标还须注册、可达、认证并满足授权；“本地”是白名单不允许直接远程调用（`mesh.delegate` 在发起方执行）。设备、来源、参数和用户在场约束仍以目标自省为准。完整盘点方法与已知缺口见 [覆盖说明](ACTION_COVERAGE.md)。

| Action | Effect | 用途或限制 | 宿主代码 | Mesh | 定义 |
| --- | --- | --- | --- | --- | --- |
| `accounts.bangumi.sync` | write | Synchronize watch history to Bangumi | Core | 允许 | [源码](../../../lib/next/accounts/capability.dart) |
| `accounts.bangumi.sync_status` | read | Read Bangumi sync statistics | Core | 允许 | [源码](../../../lib/next/accounts/capability.dart) |
| `accounts.collections.get` | read | Read favorites, ratings and work status | Core | 允许 | [源码](../../../lib/next/accounts/capability.dart) |
| `accounts.collections.list` | read | 按状态列出收藏 | Core | 允许 | [源码](../../../lib/next/accounts/capability.dart) |
| `accounts.collections.update` | write | Update favorites, ratings and work status | Core | 允许 | [源码](../../../lib/next/accounts/capability.dart) |
| `accounts.episodes.get` | read | Read account episode watch state | Core | 允许 | [源码](../../../lib/next/accounts/capability.dart) |
| `accounts.episodes.update` | write | Update account episode watch state | Core | 允许 | [源码](../../../lib/next/accounts/capability.dart) |
| `accounts.login` | write | Initiate account login | Core | 允许 | [源码](../../../lib/next/accounts/capability.dart) |
| `accounts.logout` | write | Log out of an account | Core | 允许 | [源码](../../../lib/next/accounts/capability.dart) |
| `accounts.status` | read | Read account login state | Core | 允许 | [源码](../../../lib/next/accounts/capability.dart) |
| `activity.report` | write | 记录带来源的发现 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `agent.dispatch` | write | 派发宿主管理的独立回合 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `agent.dispatch.report` | write | 报告派发回合的工作进展 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `agent.wake` | write | 排队唤醒指定或主会话 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `app.capabilities` | read | Read host capability facts | 通用/组合 | 允许 | [源码](../../../lib/next/app_capabilities.dart) |
| `app.instance` | read | Identify the connected NipaPlay process | 通用/组合 | 允许 | [源码](../../../lib/next/instance_facts.dart) |
| `app.quit` | write | Quit the connected application | Runtime/部分共享 | 允许 | [源码](../../../lib/next/player/features/operation_specs.dart) |
| `app.restart` | write | Restart the connected application | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/app_runtime_capability.dart) |
| `app.runtime` | read | Read how this device is set up | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/app_runtime_capability.dart) |
| `app.update.check` | read | 立即检查应用更新 | Core | 允许 | [源码](../../../lib/next/system/diagnostics.dart) |
| `app.update.open` | write | 打开已核对的发布页 | Core | 允许 | [源码](../../../lib/next/system/diagnostics.dart) |
| `app.update.status` | read | 上次更新检查 | Core | 允许 | [源码](../../../lib/next/system/diagnostics.dart) |
| `appearance.reset_home_sections` | write | 重置首页分区 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `backup.export` | write | 导出 Classic 备份，不是完整 Next 备份 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `backup.history_export` | write | 导出观看进度 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `backup.history_restore` | destructive | 恢复观看进度 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `backup.preview` | read | 预览 Classic 备份，不是完整 Next 备份 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `backup.restore` | destructive | 恢复选定 Classic 数据，非完整 Next 恢复 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `cache.plan` | read | 分类缓存回收预览 | Core | 允许 | [源码](../../../lib/next/system/storage.dart) |
| `cache.prune` | write | 回收预览中的可重取缓存 | Core | 允许 | [源码](../../../lib/next/system/storage.dart) |
| `capability.describe` | read | Describe a capability family | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/family_descriptions.dart) |
| `chat.read` | read | Read the latest turns of a conversation | Headless | 允许 | [源码](../../../lib/next/headless/chat_capability.dart) |
| `chat.send` | write | Say something to Nipa on this host | Headless | 允许 | [源码](../../../lib/next/headless/chat_capability.dart) |
| `chat.session.list` | read | 列出会话及当前状态 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `chat.session.main` | write | 选择持久主会话 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `chat.session.new` | write | 创建新会话 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `chat.session.switch` | write | 切换会话，忙时拒绝 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `chat.status` | read | How the turn on a conversation stands | Headless | 允许 | [源码](../../../lib/next/headless/chat_capability.dart) |
| `chat.stop` | write | Stop the turn running on a conversation | Headless | 允许 | [源码](../../../lib/next/headless/chat_capability.dart) |
| `chat.turn.process` | read | 回看工作过程 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `credentials.retry` | write | 主动重试指定凭据 | 通用/组合 | 允许 | [源码](../../../lib/security/credential_capability.dart) |
| `credentials.status` | read | 凭据保险库状态 | 通用/组合 | 允许 | [源码](../../../lib/security/credential_capability.dart) |
| `danmaku.align` | write | Legacy recovery only: execute an existing persisted alignment decision option with a task revision check | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.align_apply` | write | 应用对齐预览 | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.align_keep` | write | 保留当前对齐 | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.analyze_alignment` | read | Estimate a fixed offset from up to 100 supplied source/media time anchors | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.attach` | write | Compatibility alias for danmaku.prepare: this downloads danmaku as well as binding the source | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.attach_batch` | write | 批量执行 attach；逐项回执，非原子 | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.bind` | write | Record a confirmed danmaku source identity only | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.bind_batch` | write | 批量执行 bind；逐项回执，非原子 | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.cache_delete` | destructive | Explicitly delete a saved danmaku pool and unload bindings using it | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.cache_prune` | write | Collect unreferenced content files only | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.detach` | write | Revoke this managed binding; unreferenced imported content files are deleted, provenance remains | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.entries` | read | Read the current merged and filtered display timeline near current/positionMs (windowMs default 5000) or explicit startMs/endMs, with stable pagination within this list version | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_inspection.dart) |
| `danmaku.episodes` | read | Read a finite catalogue page | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.export` | write | Export one committed binding as JSON to a new file in an authorized media folder | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.fetch` | write | Explicitly download and persist danmaku for one video/range; not part of normal scraping | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.fetch_batch` | write | 批量执行 fetch；逐项回执，非原子 | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.import` | write | 导入本地弹幕并保存来源，播放目标时可挂载 | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.import_batch` | write | 批量执行 import；逐项回执，非原子 | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.offset` | write | Compatibility alias for danmaku.update: set an absolute fixed offset in integer milliseconds, positive advances, zero resets | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.prepare` | write | Explicitly prepare danmaku now: bind the source, download and persist its pool, then refresh applicable player tracks | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.prepare_batch` | write | 批量执行 prepare；逐项回执，非原子 | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.resolve` | read | Resolve a public URL or platform ID | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.search` | read | Bounded transient title search | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.send` | write | Send a danmaku comment | Runtime/部分共享 | 允许 | [源码](../../../lib/next/player/features/operation_specs.dart) |
| `danmaku.set_dedup` | write | 设置弹幕显示去重；保留来源缓存 | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.set_enabled` | write | 设置弹幕轨道启用状态；需绑定修订 | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.sources` | read | List registered sources and capabilities | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.tracks` | read | 列出弹幕绑定和当前播放器轨道 | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `danmaku.update` | write | Update 1 to 100 bindings or current player tracks in input order | 通用/组合 | 允许 | [源码](../../../lib/next/danmaku/capability.dart) |
| `db.describe` | read | Describe next.db | 通用/组合 | 允许 | [源码](../../../lib/next/db/capability.dart) |
| `db.query` | read | Read next.db with SQL | 通用/组合 | 允许 | [源码](../../../lib/next/db/capability.dart) |
| `db.receipt` | read | 查询数据库提交回执 | 通用/组合 | 允许 | [源码](../../../lib/next/db/capability.dart) |
| `db.undo` | write | Undo a direct database write | 通用/组合 | 允许 | [源码](../../../lib/next/db/capability.dart) |
| `db.write` | write | Write next.db with SQL | 通用/组合 | 允许 | [源码](../../../lib/next/db/capability.dart) |
| `diagnostics.clear` | destructive | 清空诊断日志 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `diagnostics.directory` | read | 查询日志目录 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `diagnostics.errors` | read | 未捕获错误与异常退出 | Core | 允许 | [源码](../../../lib/next/system/runtime_diagnostics.dart) |
| `diagnostics.export` | write | 导出诊断日志 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `diagnostics.file_logs` | read | 脱敏持久日志摘录 | Core | 允许 | [源码](../../../lib/next/system/diagnostics.dart) |
| `diagnostics.logs` | read | 读取诊断日志 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `diagnostics.operations` | read | 查询调用过程与关联标识 | Core | 允许 | [源码](../../../lib/next/system/operation_observations.dart) |
| `diagnostics.player_log` | read | 播放器内核日志 | Core | 允许 | [源码](../../../lib/next/system/runtime_diagnostics.dart) |
| `diagnostics.player_log_file` | write | 播放器完整日志文件 | Core | 允许 | [源码](../../../lib/next/system/runtime_diagnostics.dart) |
| `diagnostics.recover` | write | 运行常见恢复操作 | Core | 允许 | [源码](../../../lib/next/system/diagnostics.dart) |
| `diagnostics.status` | read | 健康检查与运行诊断 | Core | 允许 | [源码](../../../lib/next/system/diagnostics.dart) |
| `discover.calendar` | read | 读取放送日历 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/discover_capability.dart) |
| `discover.home` | read | 读取已挂载的 Classic 首页事实 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/discover_capability.dart) |
| `discover.recommendations` | write | 读取或切换推荐组 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/discover_capability.dart) |
| `discover.refresh` | write | 请求刷新 Classic 首页 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/discover_capability.dart) |
| `discover.search` | read | 按条件搜索发现内容 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/discover_capability.dart) |
| `discover.search_batch` | read | 批量执行独立搜索 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/discover_capability.dart) |
| `discover.search_config` | read | 读取发现搜索的可用筛选项 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/discover_capability.dart) |
| `discover.trending` | read | 读取排行 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/discover_capability.dart) |
| `discover.trending_batch` | read | 批量读取排行 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/discover_capability.dart) |
| `download.add` | write | 添加下载并返回任务，支持多个后端 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `download.delete` | destructive | 删除下载数据，先预览并遵循用户确认 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `download.delete.request` | destructive | 请求删除预览中的下载文件 | 通用/组合 | 允许 | [源码](../../../lib/next/tasks/user_consent.dart) |
| `download.directories` | read | 读取默认及最近下载目录 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_metadata_capability.dart) |
| `download.forget_directories` | write | 移除最近目录记录，不移动文件 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_metadata_capability.dart) |
| `download.import` | write | 将已完成的本地视频登记到 Next | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `download.limits.get` | read | 读取下载会话限速 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `download.limits.set` | write | 修改下载会话限速 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `download.pause` | write | 暂停任务的兼容入口 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `download.play` | write | Play a download file | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_playback_capability.dart) |
| `download.preview` | read | 预览下载源及文件信息，不创建下载 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_metadata_capability.dart) |
| `download.read` | read | 读取任务、文件与进度事实 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `download.remove` | write | 移除下载会话条目，保留数据 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `download.resume` | write | 恢复任务的兼容入口 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `download.select_files` | write | 调整所选文件，不删除数据 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `download.set_paused` | write | 按任务设置暂停状态 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `download.wait_files` | read | Wait for download files | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/download_capability.dart) |
| `events.describe` | read | 身体事件契约 | 通用/组合 | 允许 | [源码](../../../lib/next/events/capability.dart) |
| `events.wait` | read | 等待身体变化 | 通用/组合 | 允许 | [源码](../../../lib/next/events/capability.dart) |
| `followup.cancel` | write | 取消尚未启动的后续 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `followup.list` | read | 查询后续及投递状态 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `followup.register` | write | 登记任务或事件触发的持久后续 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/capability.dart) |
| `history.continue_watching` | read | Get continue watching | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/history_capability.dart) |
| `history.mark_watched_batch` | write | 标记本地观看状态 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/watched_history.dart) |
| `history.remove` | write | Remove watch history | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/local_library_operations.dart) |
| `knowledge.index` | read | 安装版本知识目录与来源 | 通用/组合 | 允许 | [源码](../../../lib/next/knowledge/capability.dart) |
| `knowledge.locate` | read | 实时 ActionSpec 与静态源码引用 | 通用/组合 | 允许 | [源码](../../../lib/next/knowledge/capability.dart) |
| `knowledge.outline` | read | 分页浏览文档章节与精确读取位置 | 通用/组合 | 允许 | [源码](../../../lib/next/knowledge/capability.dart) |
| `knowledge.read` | read | 分页读取安装包文档 | 通用/组合 | 允许 | [源码](../../../lib/next/knowledge/capability.dart) |
| `knowledge.search` | read | 受限关键词检索安装包文档 | 通用/组合 | 允许 | [源码](../../../lib/next/knowledge/capability.dart) |
| `media.artwork.clear` | write | 清除图片覆盖 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/capability.dart) |
| `media.artwork.set` | write | 设置媒体图片覆盖 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/capability.dart) |
| `media.entities.put_batch` | write | 建立或修改本地目录 | 通用/组合 | 允许 | [源码](../../../lib/next/media/catalog_capability.dart) |
| `media.entities.remove_batch` | write | 解除本地目录关联 | 通用/组合 | 允许 | [源码](../../../lib/next/media/catalog_capability.dart) |
| `media.entities.restore` | write | 撤回目录移除 | 通用/组合 | 允许 | [源码](../../../lib/next/media/catalog_capability.dart) |
| `media.files.list` | read | Return the complete recursive video file list for root, or every indexed file location for workId | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.files.reveal` | write | 在文件管理器中定位文件 | Core | 允许 | [源码](../../../lib/next/system/desktop.dart) |
| `media.frames` | read | Take pictures from a video file at given times | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/media_frames.dart) |
| `media.hash.match` | read | Match multiple native files against Dandanplay using the MD5 of their first 16 MiB | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.identity.bind_batch` | write | Atomically accept explicit bindings in one batch | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.identity.get` | read | Read identity by entityId, path or current (default) | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.identity.restore_classic_batch` | write | Undo the revocation of classic_match bindings made by unbind_batch, by name | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.identity.unbind_batch` | write | Atomically revoke Agent/user bindings and retain provenance | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.indexers.status` | read | 自动行为实际状态 | Core | 允许 | [源码](../../../lib/next/system/diagnostics.dart) |
| `media.library.import_history` | write | Explicitly import Classic paths and visible Dandanplay matches into Next, preserving source observations and conflicts | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.library.progress` | write | 记录并同步跨设备观看进度 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/library_capability.dart) |
| `media.library.readable` | read | 解析剧集在本机或 Mesh 的可读地址 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/library_capability.dart) |
| `media.library.refresh` | read | 刷新认证设备目录，失败保留旧目录 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/library_capability.dart) |
| `media.library.roots.add` | write | Add local scan folders | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/local_library_operations.dart) |
| `media.library.roots.cleanup` | write | Clean missing scan folders | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/local_library_operations.dart) |
| `media.library.roots.list` | read | Read local scan folders | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/local_library_operations.dart) |
| `media.library.roots.remove` | write | Remove local scan folders | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/local_library_operations.dart) |
| `media.library.scan` | write | Index video files under an authorized native root: enumeration, probe, head hash and file locations only | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.library.scan_classic` | write | Classic 识别扫描；Next 激活时不可用 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/local_library_operations.dart) |
| `media.library.search` | read | Search the media library | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/library_capability.dart) |
| `media.library.search_merged` | read | 搜索合并媒体库 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/library_capability.dart) |
| `media.library.series` | read | Get a library series | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/library_capability.dart) |
| `media.library.status` | read | 立即读取目录刷新与可达性观察 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/library_capability.dart) |
| `media.library.work` | read | Read one Next work with its release and episode structure | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.library.works` | read | List Next works including TMDB-only and Bangumi-only identities, releases, catalogue episodes and file locations | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.management.bind_batch` | write | 预览或提交多作品身份绑定 | 通用/组合 | 允许 | [源码](../../../lib/next/media/management.dart) |
| `media.management.merge_work` | write | 预览或合并重复作品 | 通用/组合 | 允许 | [源码](../../../lib/next/media/work_merge.dart) |
| `media.management.targets` | read | 读取作品管理的来源设备和实体 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/library_capability.dart) |
| `media.management.unbind_batch` | write | 预览或撤销多作品身份绑定 | 通用/组合 | 允许 | [源码](../../../lib/next/media/management.dart) |
| `media.management.undo_merge` | write | 预览或撤回作品合并 | 通用/组合 | 允许 | [源码](../../../lib/next/media/work_merge.dart) |
| `media.mesh_files.begin` | write | 在目标设备暂存文件传输 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/files.dart) |
| `media.mesh_files.cancel` | write | 取消暂存传输 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/files.dart) |
| `media.mesh_files.chunk` | write | 按偏移上传暂存块 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/files.dart) |
| `media.mesh_files.confirm` | destructive | 用户同意后执行预览的覆盖或删除 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/files.dart) |
| `media.mesh_files.delete` | write | 预览目标文件删除 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/files.dart) |
| `media.mesh_files.finish` | write | 校验并发布暂存文件，覆盖先预览 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/files.dart) |
| `media.mesh_files.readable` | read | 获取目标文件可读地址 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/files.dart) |
| `media.metadata.get` | read | Fetch an external object without persisting it | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.metadata.get_batch` | read | Read multiple external works, seasons or episodes in one call; identical refs are fetched once | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.metadata.import_batch` | write | Append structured snapshots for accepted external identities, including arbitrary HTTPS origin namespaces | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.metadata.override` | write | Edit title (display title), originalTitle, overview (synopsis) or legacy imageUrl | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.metadata.override_batch` | write | 批量编辑文字 | 通用/组合 | 允许 | [源码](../../../lib/next/media/catalog_capability.dart) |
| `media.metadata.put` | write | 交一部作品的资料 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/capability.dart) |
| `media.metadata.refresh` | write | Schedule a metadata snapshot refresh for an accepted external object | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.metadata.refresh_batch` | write | 批量刷新来源资料 | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.metadata.search` | read | Search a metadata source | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.metadata.search_batch` | read | Search multiple metadata sources or queries in one call | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.metadata.snapshots` | read | Read all retained source snapshots and host provenance for an entity | 通用/组合 | 允许 | [源码](../../../lib/next/media/media_capability.dart) |
| `media.metadata.ui_facts` | read | 读取作品资料完整性和来源 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/capability.dart) |
| `media.metadata.ui_facts_batch` | read | 批量读取资料完整情况 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/capability.dart) |
| `media.sources.add` | write | Configure a media source | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.addresses` | write | List or modify Classic server addresses in one batch | Core | 允许 | [源码](../../../lib/next/media_sources/remote_admin.dart) |
| `media.sources.artwork` | read | 读取来源海报 | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.browse` | write | Browse remote content | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.check` | write | Check a media source connection | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.discover` | read | 发现局域网共享来源 | Core | 允许 | [源码](../../../lib/next/system/desktop.dart) |
| `media.sources.libraries` | read | List available source libraries | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.list` | read | List media sources | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.login` | write | Initiate media source login | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.play` | write | 播放远程影片 | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.query` | read | Query remote item metadata | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.remote_admin.connections` | write | Manage peer WebDAV/SMB connections | Core | 允许 | [源码](../../../lib/next/media_sources/remote_admin.dart) |
| `media.sources.remote_admin.folders` | write | Manage peer scan roots in bulk | Core | 允许 | [源码](../../../lib/next/media_sources/remote_admin.dart) |
| `media.sources.remote_admin.status` | write | Refresh the selected NipaPlay peer management state through the Classic provider: folders, saved WebDAV/SMB configurations (LAN url/host/port and WAN wanUrl/wanHost/wanPort, empty … | Core | 允许 | [源码](../../../lib/next/media_sources/remote_admin.dart) |
| `media.sources.remove` | destructive | Remove a media source | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.scrape` | write | 识别远程媒体 | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.search` | read | 只读搜索媒体来源 | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.select` | write | Select source libraries | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.sort` | write | 设置媒体库排序 | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.sync` | write | Synchronize source discovery | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `media.sources.update` | write | Update a media source | Core | 允许 | [源码](../../../lib/next/media_sources/capability.dart) |
| `memory.context` | read | 读取常驻记忆及最近事实 | 通用/组合 | 允许 | [源码](../../../lib/next/memory/capability.dart) |
| `memory.delete` | write | 按 revision 删除记忆并提交 | 通用/组合 | 允许 | [源码](../../../lib/next/memory/capability.dart) |
| `memory.edit` | write | 按 revision 修改记忆并提交 | 通用/组合 | 允许 | [源码](../../../lib/next/memory/capability.dart) |
| `memory.list` | read | 列出记忆文件及版本 | 通用/组合 | 允许 | [源码](../../../lib/next/memory/capability.dart) |
| `memory.read` | read | 读取指定记忆文件并脱敏 | 通用/组合 | 允许 | [源码](../../../lib/next/memory/capability.dart) |
| `mesh.delegate` | write | Hand a task to the Nipa of another device | 通用/组合 | 本地 | [源码](../../../lib/next/mesh/delegation.dart) |
| `mesh.devices` | read | 列出设备、认证描述及能力 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/capability.dart) |
| `mesh.invoke` | write | 调用目标设备非破坏性 Action | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/capability.dart) |
| `mesh.invoke_destructive` | destructive | 调用目标设备破坏性 Action，遵守目标确认契约 | 通用/组合 | 允许 | [源码](../../../lib/next/mesh/capability.dart) |
| `network.check` | read | 检查网络来源 | 通用/组合 | 允许 | [源码](../../../lib/next/network/capability.dart) |
| `network.status` | read | 网络路由与故障事实 | 通用/组合 | 允许 | [源码](../../../lib/next/network/capability.dart) |
| `notification.cancel` | write | 取消系统通知 | Core | 允许 | [源码](../../../lib/next/system/desktop.dart) |
| `notification.list` | read | 列出系统已投递或待投递通知 | Core | 允许 | [源码](../../../lib/next/system/desktop.dart) |
| `notification.send` | write | 发送系统通知 | Core | 允许 | [源码](../../../lib/next/system/desktop.dart) |
| `notification.status` | read | 读取系统通知授权状态 | Core | 允许 | [源码](../../../lib/next/system/desktop.dart) |
| `playback.authorize_directory` | write | Open directory permission picker | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_controls_capability.dart) |
| `playback.cancel_auto_next` | write | Cancel the running countdown to the next episode, as the countdown bar does | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_inspection.dart) |
| `playback.capture` | write | Save a screenshot or GIF | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_controls_capability.dart) |
| `playback.chapters` | read | Read container chapter markers, current index and all detected opening/ending segments with provenance (source: agent = set by playback.set_skip_segment, mediaServer, aniskip, danm… | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_inspection.dart) |
| `playback.close` | write | Close current playback | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_controls_capability.dart) |
| `playback.external` | write | Control an external player session | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_controls_capability.dart) |
| `playback.external.danmaku` | write | Set external session danmaku | Runtime/部分共享 | 允许 | [源码](../../../lib/next/player/features/operation_specs.dart) |
| `playback.external.danmaku_state` | read | Read external session danmaku | Runtime/部分共享 | 允许 | [源码](../../../lib/next/player/features/operation_specs.dart) |
| `playback.external_player_path` | write | Choose or detect an external player | Runtime/部分共享 | 允许 | [源码](../../../lib/next/player/features/operation_specs.dart) |
| `playback.external_state` | read | Read external playback telemetry | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_controls_capability.dart) |
| `playback.failures` | read | Read playback failures recorded in this process while Next is on, newest first: failureId, at, sessionId, path, kernel, stage (file_check, stream_session, remote_path, media_open, … | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_inspection.dart) |
| `playback.info` | read | Read what the kernel playing now reports about the media, queried from the kernel at call time: kernel (id mdk/media_kit/video_player/erika, name, configured = the kernel setting),… | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_inspection.dart) |
| `playback.kernel` | read | Read the player kernel | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/kernel_control.dart) |
| `playback.kernel_command` | write | Run an mpv command | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/kernel_control.dart) |
| `playback.kernel_invoke` | write | Invoke an Erika method | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/kernel_control.dart) |
| `playback.levels` | write | Read or set playback levels | Runtime/部分共享 | 允许 | [源码](../../../lib/next/player/features/operation_specs.dart) |
| `playback.load_subtitle` | write | Load an external subtitle | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_controls_capability.dart) |
| `playback.navigate` | write | Use exactly one chapterIndex, frameDelta (-1 or +1), or skipKind (current/opening/ending) | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_inspection.dart) |
| `playback.open` | write | Open a video | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_capability.dart) |
| `playback.playlist` | read | Read the current playback detail source and its exact ordered cached/loaded episodes | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_inspection.dart) |
| `playback.remove_subtitle` | write | Unmount an external subtitle | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_controls_capability.dart) |
| `playback.reopen_with_kernel` | write | Reopen this media on another kernel | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/kernel_control.dart) |
| `playback.restore_kernel_properties` | write | Restore kernel properties | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/kernel_control.dart) |
| `playback.retry` | write | Explicitly reload the current internal source | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_inspection.dart) |
| `playback.seek` | write | Seek in the current video | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_capability.dart) |
| `playback.select_stream` | write | Apply stream choices | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_controls_capability.dart) |
| `playback.select_track` | write | Select a player track | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_controls_capability.dart) |
| `playback.set_kernel_properties` | write | Change kernel properties for this playback | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/kernel_control.dart) |
| `playback.set_paused` | write | Set playback pause | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_capability.dart) |
| `playback.set_skip_segment` | write | Set or clear the opening or ending of the file that plays now | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_inspection.dart) |
| `playback.state` | read | Get playback state | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_capability.dart) |
| `playback.stream_options` | read | Read stream versions and quality | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_controls_capability.dart) |
| `playback.switch_episode` | write | Switch the current episode | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_capability.dart) |
| `playback.tracks` | read | List player tracks | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_controls_capability.dart) |
| `playback.wait` | read | Bounded observation of this session only | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_inspection.dart) |
| `playback.watch_kernel_properties` | read | Watch kernel properties | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/kernel_control.dart) |
| `plugins.delete` | destructive | 删除插件 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `plugins.install` | destructive | 安装或更新插件 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `plugins.invoke` | destructive | 执行插件 UI 动作 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `plugins.list` | read | 查询已安装插件 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `plugins.market` | read | 查询市场与更新 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `plugins.set_enabled` | write | 启用或停用插件 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `program.repository.receive` | write | 接收 harness Git bundle | 通用/组合 | 允许 | [源码](../../../lib/next/programs/repository.dart) |
| `program.run` | write | 在设备上运行程序 | 通用/组合 | 允许 | [源码](../../../lib/next/programs/runtime.dart) |
| `settings.describe` | read | 描述已注册设置和 schema | 通用/组合 | 允许 | [源码](../../../lib/next/settings/capability.dart) |
| `settings.get` | read | 读取设置值 | 通用/组合 | 允许 | [源码](../../../lib/next/settings/capability.dart) |
| `settings.history` | read | 查询设置更改历史 | 通用/组合 | 允许 | [源码](../../../lib/next/settings/capability.dart) |
| `settings.prefs.get` | read | Read stored application preferences | 通用/组合 | 允许 | [源码](../../../lib/next/settings/prefs.dart) |
| `settings.prefs.history` | read | List preference writes | 通用/组合 | 允许 | [源码](../../../lib/next/settings/prefs.dart) |
| `settings.prefs.list` | read | List stored application preferences | 通用/组合 | 允许 | [源码](../../../lib/next/settings/prefs.dart) |
| `settings.prefs.set` | write | Write a stored application preference | 通用/组合 | 允许 | [源码](../../../lib/next/settings/prefs.dart) |
| `settings.prefs.undo` | write | Undo a preference write | 通用/组合 | 允许 | [源码](../../../lib/next/settings/prefs.dart) |
| `settings.reset` | write | 恢复设置默认值 | 通用/组合 | 允许 | [源码](../../../lib/next/settings/capability.dart) |
| `settings.set` | write | 按来源与理由修改设置；敏感项可能需要用户确认 | 通用/组合 | 允许 | [源码](../../../lib/next/settings/capability.dart) |
| `settings.set.request` | write | 请求用户确认设置修改 | 通用/组合 | 允许 | [源码](../../../lib/next/settings/consent.dart) |
| `share.open` | write | 打开预览的系统分享面板 | Core | 允许 | [源码](../../../lib/next/system/desktop.dart) |
| `share.prepare` | read | 预览系统分享内容 | Core | 允许 | [源码](../../../lib/next/system/desktop.dart) |
| `shortcuts.reset` | write | 恢复默认快捷键 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `state.describe` | read | 说明只读状态视图和字段 | 通用/组合 | 允许 | [源码](../../../lib/next/state/query.dart) |
| `state.query` | read | 查询只读状态视图 | 通用/组合 | 允许 | [源码](../../../lib/next/state/query.dart) |
| `storage.status` | read | 全局空间与缓存事实 | Core | 允许 | [源码](../../../lib/next/system/storage.dart) |
| `storage.unwatch` | write | 取消空间订阅 | Core | 允许 | [源码](../../../lib/next/system/storage.dart) |
| `storage.watch` | write | 订阅空间阈值变化 | Core | 允许 | [源码](../../../lib/next/system/storage.dart) |
| `subtitle.copy_delete` | destructive | 删除未引用字幕副本 | 通用/组合 | 允许 | [源码](../../../lib/next/subtitles/edit_capability.dart) |
| `subtitle.cues` | read | Read timed text from active external subtitle tracks, including current cues and surrounding lines | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/playback_inspection.dart) |
| `subtitle.import` | write | 交入并保存字幕 | 通用/组合 | 允许 | [源码](../../../lib/next/subtitles/capability.dart) |
| `subtitle.remove` | write | 移除字幕记录 | 通用/组合 | 允许 | [源码](../../../lib/next/subtitles/edit_capability.dart) |
| `subtitle.reset_selection` | write | 重置字幕选择 | 通用/组合 | 允许 | [源码](../../../lib/next/subtitles/edit_capability.dart) |
| `subtitle.select` | write | 记录默认字幕 | 通用/组合 | 允许 | [源码](../../../lib/next/subtitles/capability.dart) |
| `subtitle.select_batch` | write | 批量记录默认字幕 | 通用/组合 | 允许 | [源码](../../../lib/next/subtitles/edit_capability.dart) |
| `subtitle.tracks` | read | 读取文件字幕事实 | 通用/组合 | 允许 | [源码](../../../lib/next/subtitles/capability.dart) |
| `subtitle.update` | write | 更新字幕记录 | 通用/组合 | 允许 | [源码](../../../lib/next/subtitles/edit_capability.dart) |
| `sync.configure` | write | 配置远端同步 | Core | 允许 | [源码](../../../lib/next/media_sources/sync.dart) |
| `sync.enable` | write | 启用或停用同步 | Core | 允许 | [源码](../../../lib/next/media_sources/sync.dart) |
| `sync.login` | write | 开始同步登录 | Core | 允许 | [源码](../../../lib/next/media_sources/sync.dart) |
| `sync.run` | write | 发起同步任务 | Core | 允许 | [源码](../../../lib/next/media_sources/sync.dart) |
| `sync.status` | read | 读取同步状态 | Core | 允许 | [源码](../../../lib/next/media_sources/sync.dart) |
| `sync.test` | write | 测试同步连接 | Core | 允许 | [源码](../../../lib/next/media_sources/sync.dart) |
| `task.cancel` | write | 请求取消任务 | 通用/组合 | 允许 | [源码](../../../packages/nipa_harness/lib/src/tasks/actions.dart) |
| `task.control` | write | 批量控制后台任务 | 通用/组合 | 允许 | [源码](../../../lib/next/tasks/resources.dart) |
| `task.get` | read | 读取指定任务和回执 | 通用/组合 | 允许 | [源码](../../../packages/nipa_harness/lib/src/tasks/actions.dart) |
| `task.list` | read | 列出任务 | 通用/组合 | 允许 | [源码](../../../packages/nipa_harness/lib/src/tasks/actions.dart) |
| `task.resources` | read | 后台容量与占用 | 通用/组合 | 允许 | [源码](../../../lib/next/tasks/resources.dart) |
| `task.wait` | read | 有界等待任务 | 通用/组合 | 允许 | [源码](../../../packages/nipa_harness/lib/src/tasks/actions.dart) |
| `ui.capture` | read | Capture this NipaPlay main interface | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/ui_capture.dart) |
| `ui.close` | write | Close current dialog | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/ui_capability.dart) |
| `ui.library.configure` | write | 调整来源展示形式 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/library_capability.dart) |
| `ui.library.items` | read | 分页读取分类作品 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/library_capability.dart) |
| `ui.library.move` | write | 调整可见分类的本机顺序 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/library_capability.dart) |
| `ui.library.page` | read | 读取来源类别和本机隐藏状态 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/library_capability.dart) |
| `ui.library.put` | write | 建立或替换本机分类 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/library_capability.dart) |
| `ui.library.remove` | write | 移除整理分类或隐藏原分类，不删源数据 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/library_capability.dart) |
| `ui.library.restore` | write | 恢复本机隐藏的原分类 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/library_capability.dart) |
| `ui.library.sources` | read | 列出媒体库来源 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/library_capability.dart) |
| `ui.open` | write | 打开页面 | Runtime/部分共享 | 允许 | [源码](../../../lib/next/capabilities/ui_open.dart) |
| `ui.notify` | write | 发布 Agent 自主提醒 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/inbox_capability.dart) |
| `ui.ask` | write | 非阻塞异步询问 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/inbox_capability.dart) |
| `ui.detail.layout` | read | 读取作品详情页的展示规则与位置说明 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/capability.dart) |
| `ui.detail.layout.set` | write | 修改本机或单部作品的详情页展示规则 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/capability.dart) |
| `ui.inbox.list` | read | 分页读取提醒与问题 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/inbox_capability.dart) |
| `ui.inbox.respond` | write | 用户回答与原会话投递 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/inbox_capability.dart) |
| `ui.inbox.dismiss` | write | 收起或取消提醒 | 通用/组合 | 允许 | [源码](../../../lib/next/followups/inbox_capability.dart) |
| `ui.present` | write | 在会话展示卡片 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/capability.dart) |
| `ui.shelves.put` | write | 创建或替换首页书架或主视觉 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/capability.dart) |
| `ui.shelves.remove` | write | 移除指定首页书架 | 通用/组合 | 允许 | [源码](../../../lib/next/ui_data/capability.dart) |
| `webdav_quick.reset` | destructive | 重置 WebDAV 快捷设置 | Core | 允许 | [源码](../../../lib/next/settings/operations.dart) |
| `window.bounds.get` | read | 读取主窗口位置与尺寸 | Core | 允许 | [源码](../../../lib/next/system/desktop.dart) |
| `window.bounds.set` | write | 主窗口位置与尺寸 | Core | 允许 | [源码](../../../lib/next/system/desktop.dart) |
| `window.control` | write | Control a window | Runtime/部分共享 | 允许 | [源码](../../../lib/next/player/features/operation_specs.dart) |
| `window.state` | read | Read window state | Runtime/部分共享 | 允许 | [源码](../../../lib/next/player/features/operation_specs.dart) |
