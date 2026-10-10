# 媒体智能任务书：多来源身份、Agent 刮削与多平台弹幕

> 工作方式见 `docs/next/TEAM.md`。调研输入见 `research/METADATA_IDENTIFICATION.md`（R4）与 `research/DANMAKU_AGGREGATION.md`（R5）。

## 目标

- 任何视频都能被识别、进入媒体库、获得元数据和弹幕，不论它是不是动画、弹弹play 有没有收录。
- 识别和刮削由确定性程序完成高置信度部分，歧义交给 Agent（可联网查证）或用户。
- 弹幕可以直接来自各视频平台，并与弹弹play 的聚合结果合并、去重、对齐。

### 验收场景

1. **非动画剧集**：《长安十二时辰》（弹弹play 没有收录，优酷独播）。
   - 扫描后以 TMDB 身份进入媒体库，带海报和剧集结构；
   - 用户说“给这集加上优酷弹幕”，Agent 定位到优酷对应的剧集并加载弹幕，回执写明来源、条数与覆盖情况。
2. **动画季与 cour 的歧义**：一部 TMDB 与 Bangumi 季集划分不一致的番剧。
   - 确定性层无法高置信度绑定时生成 Decision；
   - Agent 依据证据选择，或交给用户；
   - 绑定记录来源、证据与绑定者。
3. **正在播放时**：用户说“再加上 B 站弹幕”。新轨道加入当前播放，与弹弹play 已有的 related 条目去重。

---

## 全局契约

### 1. 身份与元数据

- **弹弹play 只是来源之一。** 作品、剧集、文件的身份都不依赖弹弹play ID。只有 TMDB、Bangumi 或其他来源身份的条目，同样是“已识别”。
- **实体层级**与 R4 §6.1 一致：Work / Release / Episode / File / FileLocation / FileEpisode，并支持“一文件多集、一集多文件”。实现者可以简化内部表结构，但这些语义必须能表达。
- **外部对象、绑定、证据、元数据快照分开保存**，见 R4 §6.2。绑定必须记录：
  - `relation` 与 `scope`；
  - `status`：proposed / accepted / rejected / revoked；
  - `source`；
  - `boundBy`：automatic / agent / user。**该值由宿主依据调用来源（`Invocation.origin`）写入，模型无法自称“用户已确认”。**
- 存储在 `<AppStorage>/next/next.db`。
- 元数据按字段合成；用户的覆盖优先；刷新元数据不得悄悄改变身份。
- **元数据来源以插件化端口接入**（`MetadataProvider`）。首批来源为 TMDB、Bangumi、弹弹play。
  - 凭据只通过引用传递。凭据保险库落地之前，TMDB 等密钥暂存于 `<AppStorage>/next/credentials.json`（权限 0600），保险库完成后再迁移。

### 2. 弹幕

- **弹幕绑定是多来源的。** Episode 或 File 可以绑定到任意 `DanmakuSource` 的外部视频对象，例如弹弹play episodeId、B 站 cid、优酷 vid，每个绑定各自记录偏移与对齐规则、证据和绑定者。
- **`DanmakuSource` 契约从第一天起按插件接口设计**，见 R5 §5：
  - 能力声明、搜索与定位、可分段可取消的获取；
  - 凭据只通过宿主提供的引用使用，**来源实现不直接读取浏览器 cookie**；
  - 限流与缓存。
- 首批来源：
  - **弹弹play**：保留 related 聚合中每条弹幕的原始平台来源，用于去重；
  - **B 站**；
  - **优酷**：参考 download-harness 的实现，但修正其成功语义，缺字段不能当作空列表。
- 弹幕合并进播放器现有的多轨机制。每条轨道可以单独开关、单独偏移，并保留来源信息。
- 研究阶段的边界：只使用公开接口与用户自己的登录态；不绕过会员、DRM 或付费墙；不做全站抓取。

### 3. Classic 共存

- 观看进度在首期仍以 `watch_history.db` 为准。
- 只有与弹弹play 相关的绑定才投影回 `WatchHistoryItem` 的匹配字段，且采用可靠投影：next.db 写入时同时写待投影队列，回读确认后才标记完成。
- **不得把 TMDB 等 ID 塞进旧的 `animeId` 字段来绕过媒体库过滤。**
- M1 Action 中 `animeId` / `episodeId` 的含义保持不变，仍表示弹弹play 身份。新的身份通过新 Action 或新参数暴露。

### 4. Action 与任务

- 以 R4 §8、R5 §6.1 的 Action 目录为基础。实现者可以调整命名与拆分，但必须满足：
  - 查询类为 `read`，不创建持久绑定或任务；
  - 会写入绑定、缓存或创建任务的为 `write`；
  - 删除缓存或数据的为 `destructive`；
  - 歧义返回 `NeedsDecision`，每个选项都可以直接执行。
- 扫描、批量识别、元数据刷新、弹幕获取与对齐，都运行在 Task Engine 上。回执如实写明验证等级，以及部分成功的情况。
- `media.library.*` 需要能列出非弹弹play 的作品：新增参数或新 Action，M1 的输出语义保持兼容。

---

## 阶段

### 阶段 MA：身份地基与 Agent 刮削

- next.db 身份存储，从 `watch_history.db` 导入为旁路索引，不推断绑定者；
- `MetadataProvider` 端口，以及 TMDB、Bangumi、弹弹play 三个来源；
- 文件名解析与确定性识别层，见 R4 §7；
- 扫描与识别任务，以及歧义 Decision；
- 识别与绑定相关的 Action；`media.library.*` 支持非弹弹play 作品；
- 向 Classic 的弹弹play 投影。

### 阶段 MB：多平台弹幕

- `DanmakuSource` 端口，以及弹弹play（保留来源）、B 站、优酷三个来源；
- 多来源弹幕绑定，存储在 next.db，挂在 MA 的实体上；
- 获取、对齐、去重，接入播放器多轨；
- `danmaku.*` Action。

MB 依赖 MA 的身份实体。实现者可以在 MA 定下存储结构之后开始 MB。

### 阶段 MC：Classic 媒体库展示（另行确认）

- 让 Classic 媒体库能显示只有 TMDB 等身份的作品。这会改变 Classic 的可见行为，开始前先与用户确认。

## 验收

- 各阶段的单元与契约测试：
  - 来源适配器用录制的响应夹具（fixture）测试，不依赖线上服务；
  - 测试和夹具里不得含有任何凭据。
- 上述三个验收场景，由主控在真机上用真实账号完成端到端验收。

## 平台会话（2026-10-10 决定，依赖凭据保险库）

- 需要登录态的弹幕源（例如优酷、部分 B 站接口），由 **NipaPlay 内置 WebView 登录**获取会话：用户在 NipaPlay 中打开平台登录页登录一次，宿主把会话存入凭据保险库，来源实现只拿到 `CredentialRef`。
- 备选方案：用户手动粘贴会话。
- **不读取系统浏览器的 cookie 数据库**：静默读取用户的浏览器数据越界了。
- 该通道在凭据保险库（`MESH_TASKBOOK.md` 阶段 V）合入后实现，同时实现 `YoukuSessionBridge`。
