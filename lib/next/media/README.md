# MA 身份与刮削

`MediaRuntime.create` 接收 NextCore 提供的数据库、设备身份及宿主端口，提供
`executors` 与 `capability`。NextCore 在 `engine.start()` 之前调用 `attach`
注入唯一引擎，启动后调用 `start()` 补交旧 outbox。
HTTP clients 的关闭由 NextCore 负责。完整接入顺序见 [应用组合点](../README.md)。

## 存储与合并

当前播放和 Classic 列表中的文件可按需登记 File/FileLocation。`media.identity.get`
和 `media.identification.start` 支持 path/current（默认当前文件）；后者仍在授权媒体
目录中探测内容。位置登记不读取文件内容、不建立作品身份、不修改已有修订或绑定。
首次补充空 probe 或仅有 legacy 标记的 probe 只丰富文件信息；已有内容证据发生变化时
才递增修订并使绑定失效。探测和补充证据在识别任务中完成。
Classic Action 的文件列表与播放回执共用 `FileIndexingCapability` 登记位置，保持原输出。

`next_database.dart` 按顺序执行 v1 任务表和 v2 媒体身份表迁移；v1 的 jobs
和 job_events SQL、数据与公开 Task Engine API 都未修改。身份迁移独立位于
`media_migration.dart`，后续领域在统一序列中追加版本，新库执行全部迁移。

| 表 | 实际字段（JSON 列注明） |
|---|---|
| media_entities | id PK, kind(work/release/episode/file), parent_id FK, revision, attributes JSON |
| media_locations | id PK, file_id FK, source, owner_device_id, locator, available；UNIQUE(source,owner_device_id,locator) |
| media_file_episodes | file_id FK + episode_id FK 联合 PK, relation, ordinal, start_ms, end_ms |
| media_external_objects | id PK, provider, object_type, external_id TEXT, scope；UNIQUE(provider,object_type,external_id,scope) |
| media_bindings | id PK, entity_id FK, object_id FK, relation, scope JSON, status(proposed/accepted/rejected/revoked), source, bound_by(automatic/agent/user，可空), revision, supersedes FK, invocation_id, job_id, created_at |
| media_evidence | id PK, binding_id FK 可空, job_id, source, payload JSON, created_at |
| media_snapshots | id PK, object_id FK, language, fetched_at, fields JSON |
| media_overrides | entity_id FK + field 联合 PK, value JSON, invocation_id |
| media_candidates | id PK, job_id, file_id FK, file_revision, binding_revision, payload JSON, source, state |
| media_identifications | job_id PK, file_id FK, file_revision, binding_revision, state, context JSON |
| media_projection_outbox | id PK, file_id FK, file_revision, binding_revision, payload JSON, state |
| media_legacy_history | location_id PK/FK, fingerprint, payload JSON |
| media_scan_items | job_id + file_id FK 联合 PK, file_revision, identification_job_id |

`Work → Release → Episode` 通过 `parent_id` 关联；File 不依赖外部来源 ID。
File 属性保存 probe(size/modifiedAt/headMd5) 和独立 bindingRevision。
识别上下文和证据保存当时的文件修订与 probe；换文件后仍能追溯旧哈希请求。
Episode/Release 属性保存 title/type/number/season/order。FileEpisode 支持一文件
多集、一集多文件和可空时间段。MB 可以复用 File/Episode 的本地 ID、任意来源
external object 与 evidence，再追加它自己的偏移/对齐存储；本阶段不实现 MB。

## 相对 R4 的简化

- 四类实体合用一张带 kind 的表，保留全部六层语义；不另建 EpisodeOrder 表，
  编号与顺序保留在实体属性、候选记录和绑定 scope 中。
- 文件稳定 ID 按已索引位置创建，probe 变化增加修订；头部 MD5 用于请求 hashOnly，
  不作为跨路径内容去重的充分证据。没有新增 Anitomy/FFI 依赖。
- 未接受的绑定差异保存在 candidates；接受后写 bindings、保留拒绝候选与撤销记录。
  旧历史仅进入 legacy_history，不推断 boundBy，也不把旧 ID 自动提升为 accepted。
- 普通文件名搜索即使只有一个候选也生成 Decision。唯一且无冲突的 hashOnly，或
  明确指定已接受 release 后的唯一目录集号，才允许自动绑定；不使用未校准的概率。
- 扫描采用子识别任务，扫描成功只证明枚举与调度完成。Agent 补证需来源详情与目录
  成员校验；识别工作最多并行四项，排队任务取消时不启动文件探测或来源请求。
  补证后执行 reconsider 生成新的持久 Decision。defer/skip 可用新的
  requestId 重新识别，不提供自动补证触发器或永久忽略策略。
- Task Engine 先原子记录选择，恢复执行器再原子提交身份、证据、候选状态和 outbox。
  两步之间崩溃会用持久 checkpoint 恢复，不声称两步或两个数据库是同一事务。
- 元数据按字段取最近的非空已接受来源快照，再应用用户覆盖；字段输出携带来源、
  语言、抓取时间。刷新只追加快照。没有社区映射抓取或自动跨来源合并；Agent 可
  显式传 workId 将新的 release 归到已存在作品。
- 扫描/内容探测首期使用已配置的原生本地媒体目录，校验真实路径并拒绝逃逸符号链接。
  SMB/WebDAV/服务器历史可导入旁路位置证据；不在 MA 新增远端枚举或 Web 存储实现。
- 仅弹弹play 的明确单集关系投影到 Classic；合集不自动选择单个弹幕库。
  Next 库通过 media.library.works/work 暴露，M1 Action 与 Classic 展示维持原语义。

## 凭据与测试

TMDB 的 v3 API key 由宿主 `CredentialRef('metadata', 'tmdb')` 读取保险库。
首次启动逐项迁移 `<AppStorage>/next/credentials.json`，回读核对后只保留引用。只在宿主 HTTP 请求中使用，
不进入 Action 输入、快照、事件、工作区或日志。POSIX 创建临时空文件后先
chmod 0600 再写入；Windows 用当前用户独占 ACL（PowerShell FileSecurity）。Windows
ACL 路径未在本机验证。Bangumi 使用公共接口；弹弹play 复用现有宿主签名与账号
传输边界，不获取或预取弹幕。

所有测试只回放 `test/next/fixtures/media` 的离线 JSON 或 MockClient 响应，
不访问线上 API，也没有真实密钥。该目录中的响应对象是按 API 结构构造的
最小测试样本，ID 是占位值；本次没有获得真实服务的录制文件，不将这些样本
当作真实目录、长安十二时辰真实 TMDB ID 或线上成功证据。真实账号与真实响应
回放验收由主控补齐。
