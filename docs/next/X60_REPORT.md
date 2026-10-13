# X60：界面发现的能力缺口

日期：2026-10-14。worktree：`x60-gaps`，分支：`next/x60-gaps`。
集成基线为 `fc6fbff42926fb2778025ae7166f49c44112eadd`，与核对时的
`next/capability-layer` 相同；仓库 `main` 为 `b694ded7`，尚无 `lib/next`。
因此以下“已有”指团队当前集成基线，而非旧 Classic main。

## 1. 完成了什么

| 缺口 | 本次结果 |
| --- | --- |
| 按状态列收藏 | 新增 `accounts.collections.list`，严格返回 `{items:[{workId,status,rating}],nextCursor}`。支持 provider、statuses、limit、cursor，不逐作品取详情。 |
| 历史身份与图片 | `history.entries` 增加 workId、libraryEpisodeId、poster、still；只读关联和已缓存图片。未绑定或未缓存为 null。 |
| 隐藏位置历史删除 | `history.remove` 接受 entryIds，与 paths/animeIds 取并集；位置不存在或不可见也能删除记录，保留视频。返回 removedEntryIds。 |
| 删除后分页 | 历史视图使用排序值游标，默认 lastWatchedAt 降序、entryId 升序；删除已读条目、包括最后锚点，下一页仍正确。 |
| 种子预览 | GUI/headless 的 `download.preview` 接受本地 .torrent、file URI、HTTP(S) 地址，复用 add 的准备、hash 校验和缓存；不创建下载任务、不下载视频。磁力仍用原生元数据解析。 |
| 任务数据 | UiTask.type 带持久 executor 类型；扫描标题为“扫描片库”。任务关联的作品已不存在时，任务仍可读取。 |
| 同步密码状态 | `sync.status.hasPassword` 仅报告是否已保存密码。 |
| 来源搜索图片/名称 | 搜索条目增加本机缓存 poster、已绑定作品 workTitle；新增 `media.sources.artwork` 显式懒加载海报，复用 X48 图片供应者。 |
| 宿主设置 | 先扩展 `host_settings.dart` 契约，再实现 Classic 接收端设置、受信任设备移除、防剧透 AI key、TMDB key。秘密只写，读取仅有布尔状态；没有新增 Action。 |
| 多作品匹配/解除 | 新增 `media.management.bind_batch/unbind_batch`，返回受影响实体、剧集、进度、来源与位置的预览，expectedPlan 检查关系变化后执行。审计与 Classic 投影沿用原服务。 |
| 其他设备管理 | `media.management.targets` 返回各设备拥有的原始作品、剧集、文件 IDs；离线保留对象并给出 source_device_offline。经现有 mesh.invoke 在拥有者执行。 |
| 远程写入契约 | Mesh tools/call 不再额外经过 Classic receiver/trusted-devices 审批；有效账号设备、双向 TLS、吊销检查、防重放继续生效，领域决定仍在目标执行。Classic 接收端本身没有改动。 |
| Finder/文件管理器 | 新增 `media.files.reveal {paths}`，逐项报告请求受理或失败。macOS/Windows 定位文件，Linux 打开父目录。 |
| 下载磁盘删除 | GUI 的 download.delete 返回文件清单 NeedsDecision；其 download.delete.request 选项创建持久 disk_deletion 任务。预览绑定调用来源、单次使用，执行重检清单，保留原应用用户确认。 |
| 设置显示名 | `danmaku.fontSize` 的 0 增加“设备默认”显示名。 |

能力族描述已随新增能力更新：accounts.collections、history、download、task、sync、
media.sources、media.management、media.files。种子、nipa、界面代码均未修改。

### 已有能力和其余缺口的取舍

| 报告条目 | 核对与处理 |
| --- | --- |
| Y8 enum 显示名、路径 format、调用来源归一、启动清弹幕缓存、设置事件 | X58/X55 已补：enumNames、format、changedBy:agent、storage.clearDanmakuOnLaunch、settings.changed。没有重复注册。标题沿用现有 presentation。 |
| Y8 缓存/更新检查 | 基线已有 storage.* 与 app.update.*，Y12 已接线。本次不新增同义能力。 |
| Y8 插件安装许可 | 没有实现后端的“永久安装许可”值，不能把 denylist 键变成虚假开关。已有 plugins.install 及应用用户确认继续使用。 |
| Y8 记忆变化通知 | HarnessMemory.edit/delete 已写 harness_discoveries，activity 和 UiDataService.changes 可观察同库变化；界面可以订阅已有流后重读，不再新增第二套记忆事实源。外部编辑 Markdown 的即时文件监听不在现有契约中。 |
| Y9 合并库搜索、只读来源搜索、在线身份入库标注 | X56 已补，Y10 已接线；本次补来源海报和 workTitle。来源/片库去重是呈现选择，没有改返回范围。 |
| Y11 多作品资料、图片、文字覆盖与清覆盖 | 基线已有 media.metadata.refresh_batch、override_batch、media.artwork.set/clear 的批量 entries；无需新造 works.refresh。 |
| Y11 剧集标题清除 | 已有 override_batch 的 mode:clear、value:null，可作用于 episodeId；缺的是适配器入口。本次写明契约。 |
| Y11 多位置文件 | media.files.list 已完整返回位置；management.targets 新增拥有者映射。界面仍需展示全部位置。 |
| Y11 已匹配集号/季号自由修改 | 本地目录可编辑；外部剧集编号属于提供方身份，改匹配使用已有真实 episodeRefs，本次不写回或伪造上游编号。 |
| Y11 字幕/弹幕来源边界 | 导入轨道的编辑/解除及弹幕绑定解除已有能力；内嵌字幕是视频字节、服务端轨道由来源拥有。本次不把“解除关联”改成修改视频/上游轨道。字幕副本磁盘删除已有 subtitle.copy_delete 的 NeedsDecision。 |
| Y12 Bangumi 取消收藏 | 仍缺。核验当前官方 v0 OpenAPI，单条收藏只公开 GET、POST、PATCH，没有删除端点或取消类型。不试探未公开写接口，不用 dropped 冒充取消。弹弹play已有 remove:true。证据见 bangumi-api.json。 |
| Y12 插件自带界面动作 | plugins.invoke / describePlugin.actions 已存在，是界面缺入口，由主控接线。 |
| Y12 就地安装应用更新 | Classic 也只打开发布页，不属于两路能力差距；本次不增加新的系统安装器。 |
| Y12 后台 × | 基线 fc6fbff4 已改成移除下载任务、保留文件，本次保留。 |

## 2. 决策与契约

### 收藏与历史

收藏 workId 保持报告约定的**提供方数字 ID**，不是合并片库 ID。
Bangumi 状态为 wish/done/doing/onHold/dropped；弹弹play为 favorited/finished/abandoned。
statuses 省略或空数组表示全部；默认 limit=100，上限 100。每页只有一个提供方列表请求，
Bangumi 按原分页列表过滤，过滤后空页也可能有 nextCursor；弹弹play列表不提供评分时 rating=null。
游标绑定 provider、排序去重后的 statuses、limit。Bangumi 是远端实时偏移分页，远端修改收藏仍可能改变分页位置。

历史的旧 episodeId 保持 Classic 数字 ID，以免破坏现有调用者；新增字符串
`libraryEpisodeId` 表示 Next/合并剧集 ID。多集文件不能唯一指定剧集时为 null。
图片只有缓存路径，读取历史不会刷新 Mesh 目录、取图或迁移 Classic 历史。
观看时间变化仍会使实时条目重排，游标不承诺全局快照。
removedEntryIds 覆盖所有删除；removedPaths **仅回显调用者明确传入的 paths**，避免
entryIds-only 删除把此前隐藏的 locator 带回来。这是本次唯一收窄的历史回执字段。

### 管理与删除

采用 media.management 作为人可操作的关联预览协议；entries/requestId 与原 identity 原语一致，
不再复制绑定结构。省略 expectedPlan 返回预览，带回执行；关系变化时返回 conflict，
播放进度改变不使预览失效。解除关联只改 NipaPlay 关联和 Classic 元数据投影，
文件、进度及来源审计保留；原关系可用预览中的身份及文件关联重建。
写入经过原操作审计及 Harness journal，动态从同一库读取。

底层 media.identity.bind_batch/unbind_batch **仍维持原直接执行、幂等重试契约**，
供扫描、既有调用者及持久操作恢复使用；新增管理入口保证先返回预览。
没有把旧原语无参数调用改成 preview，以免已有任务和回执重放变成不同语义。
因此此轮没有将“先预览”变成所有底层身份写入的强制条件。

远程管理返回拥有者原始 ID，不把合并 ID 或视频转换 URL 当作远端实体/磁盘路径。
设备离线有明确原因；在线设备缺少某能力则以目标目录/调用的真实错误为准。
没有额外远程写限制。headless 仍没有 GUI download.delete，不能宣称支持该删除确认窗口；
文件删除使用已有 media.mesh_files.delete 的决定协议。

下载删除在 GUI 组装处保护原执行器：先 NeedsDecision，选项创建删除任务，再由目标设备
现有用户窗口确认。保留第二层应用批准是为了维持“Action 不能代替用户点击批准”的
已有不变量，没有提供 approve/confirm 布尔旁路。清单指纹包含文件路径、选择、大小与
输出目录，下载字节进度变化不使它失效。重启前未提交的预览需要重新取得；已持久任务
恢复会重新询问用户。plugins.delete 的原批准方式未改变。

### 宿主设置

采用 NextHostDeviceSettings companion 接口及 NextHostSettings.deviceSettings 扩展，
让既有 UI/fake 实现仍可编译。实际 HostSettingsService 和 PendingHostSettings 已实现。
契约注释先于实现写入 host_settings.dart；不支持的宿主明确抛 UnsupportedError。

keys() 返回 UiHostKeys(spoilerAi,tmdb) 两个布尔值。setKeys 的 null 保留、空字符串清除。
防剧透密钥复用现有 CredentialStore/播放器更新接口，TMDB 使用在线元数据已消费的
CredentialRef('metadata','tmdb')。不写设置历史、任务、journal 或返回秘密。
remoteAccess/setRemoteAccess 使用同一个 WebServerService 和 Classic 受信任设备存储，
修改监听先停止，再按选择启动，失败如实返回。forgetRemoteDevice 只能撤销现有信任，
没有通过接口凭空授予信任。

## 3. 主控需要接到界面的内容

本次没有修改 `lib/next/ui/`。

| 接线点 | 数据/调用 |
| --- | --- |
| NextCollections.works | 继续读所有 nextCursor；当前适配器只读取第一页。空 items 不表示结束。 |
| 动态观看记录 | workId 打开作品，libraryEpisodeId 是 Next 剧集，旧 episodeId 是数字；poster/still 为本机路径。删除用 entryIds，读取下一页沿用游标即可。 |
| 后台面板 | 直接用 UiTask.type 识别 download/media.scan_classic 等，无需另调 task.list 判断类型。 |
| 同步 | 用 sync.status.hasPassword 恢复“已保存密码”状态；修改地址/用户名沿用原清凭据语义。 |
| 来源搜索 | poster 缓存为空时可调用 media.sources.artwork {sourceId,itemId}，显示其本机路径；workTitle 可显示已绑定作品名。 |
| 宿主设置 | core.hostSettings.deviceSettings.keys/setKeys；remoteAccess/setRemoteAccess；forgetRemoteDevice。UiRemoteAccess 含 running/autoStart/port/ipv6/receiverEnabled/devices/problem。 |
| 多作品管理 | 资料用 refresh_batch(entries:[{ref,requestId,language?}])；文字用 override_batch。匹配/解除用 management 的预览与 expectedPlan。 |
| 标题恢复 | override_batch(entries:[{entityId:episodeId,field:"title",value:null,mode:"clear"}])。value 即使清除也必填。 |
| 远端管理 | management.targets 的 entries[].targets[] 含 deviceId、原始 workId、local、online、reason，以及 episodes 的 episodeId/mergedEpisodeId/fileIds。 |
| 文件定位 | media.files.reveal {paths}；逐项 requested 和 error 反映系统是否受理，不证明用户已看到窗口。 |
| 下载删除 | 处理 download.delete 的 NeedsDecision，调用其 option ActionCall；得到的是独立 disk_deletion 任务，不能拿其 jobId 当下载任务 ID。 |
| 插件/记忆 | 已有插件动作目录可呈现；记忆可随 UiDataService.changes 重读。 |

## 4. 实验与检查

证据为 `docs/next/evidence/x60/` 的脱敏结构记录，未复制含合成登录凭据的原始测试日志。

- **Classic Bangumi 回环客户端**：两页列表得到 doing 的 workIds 10、30，评分 8、9；
  列表只请求两次，携带 subject_type=2。原更新省略字段仍保留，单项失败不丢其余结果。
- **种子回环 HTTP 与本地文件**：同一个 10-byte 两文件种子，从 path、file URI、URL
  得到相同清单，顺序为 series/a.mkv、series/b.mkv；只有种子缓存，没有 native 任务。
  路径穿越种子被拒绝。第一次 URL 实验被 Flutter 默认 HTTP 替身返回 400，改真实回环
  HttpOverrides 后通过；生产实现没有为测试放宽输入验证。
- **海报回环客户端**：初次搜索 poster=null 且未取图；显式加载后字节与合成 PNG 相同，
  后续搜索返回本机缓存路径，总取图一次；实体与绑定表仍为空。测试新增时误用了不存在的
  saveAuthData 和遗漏 JobReceipt.details，修正后运行；随后清理 singleton 会话，消除与
  既有 Quick Connect 取消测试的串扰。
- **真实双向 TLS 节点**：普通写调用成功且 Classic 审批调用次数为 0；原破坏性决定保留。
  旧 X47 普通写应拒绝的断言按本次产品决定更新。合并作品的拥有者 IDs 正确映射到
  mac-work/source-work；设备离线后仍保留 source-work，reason=source_device_offline。
  视频 Range/seek、进度、撤销证书、异账号及无效证书约束继续通过。
- **持久数据约束**：管理预览不改关联；关系变更使预览失效；观看进度从 0.4 变为 0.7
  后，解除/重建仍保留 0.7 和视频。历史删除锚点并插入新条目后，后续页仍为 2/3、4/5。
  下载预览拒绝跨来源使用、清单替换和重复提交；拒绝/取消/重启不自动批准删除。
  秘密设置的保留、清除、状态和不落明文检查通过。
- **最终队列运行**：完整 `test/next` 只运行一次，加 Classic 的 remote_control_access_guard、
  bangumi_lazy_cache、bangumi_external_auth_launch、trending_bangumi 和四个 watch_history
  文件。结果 **650 passed / 7 skipped / 0 failed**，耗时 1:37。相关迭代及最终测试均用
  Flutter 3.44.6、--no-pub、lockf 排队，移除六个代理环境变量。
- **最后局部复核**：清理海报测试 singleton 后来源文件 13 项通过；隐藏历史回执增加断言后
  local_operations 文件 6 项通过。analyze 没有 error，166 项 warning/info 中唯一 warning
  是基线 Bangumi 的 dead_null_aware_expression；git diff --check 通过。

没有构建或启动应用实例，没有线上服务账号验收，没有实际调用文件定位去打开桌面窗口。
独立 headless AOT、外部真实来源及播放器实验按其已有条件跳过；不能把这轮回环/fixture
观察当作线上 Bangumi/弹弹play、跨平台文件管理器或 Next 页面真机验收。
未改依赖/界面/种子/nipa；未读写用户钥匙串、真实数据、Codex 配置或个人 harness，未 commit/push。
回环与 TLS 实验服务已关闭，临时数据由测试 teardown 删除。

## 5. 还缺什么与主控问题

还缺：上表的界面接线；Bangumi 真正取消收藏所需的官方写接口；线上账号、桌面界面及
Windows/Linux 文件定位验收。永久插件安装许可和就地安装更新没有新增后端实现。
底层身份原语的直接执行契约已明确保留，不承诺全路径强制预览。

需要主控决定的问题：**没有**。
