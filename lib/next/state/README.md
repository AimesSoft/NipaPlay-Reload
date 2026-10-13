# 只读公开状态

历史视图默认按 lastWatchedAt 降序、entryId 升序，用排序值游标继续；删除已读条目
或最后锚点不改变下一页。观看时间改变仍会使实时记录重排。
`history.entries` 增加 workId/libraryEpisodeId 与本机缓存 poster/still；episodeId
保持 Classic 数字编号。未绑定/未缓存返回 null，不刷新目录或联网取图。
`history.remove` 支持 entryIds（包括 locator=null）与 paths/animeIds 的并集；回执的
removedEntryIds 覆盖全部删除，removedPaths 仅回显调用者已提供的路径。

`state.describe` 从注册的 `StateView.fields`、关系与同一查询契约生成视图说明。
字段、类型、单位和 ID 命名空间只有这一份契约；本文不重复字段表。
`state.query` 不接收 SQL，不调用 getter 中的索引注册、Classic 迁移、来源刷新、
下载后端查询、Mesh 刷新或播放器修改。数据库只读与已有内存供应器构成数据来源。

查询接受 `view`、AND 组合的 `filter`、顶层 `select`、稳定的 `orderBy`、
`include`、`limit` 和 `cursor`。过滤运算为 eq/ne/in/contains/gt/gte/lt/lte；
contains 是文本不区分大小写的子串匹配。筛选与排序只接受注册的标量字段。
关联只能使用注册关系；关联选项接受 filter/select/orderBy/include/limit。
未知视图、字段、关系、运算或不匹配的 cursor 返回 `invalid_input`，不读取来源。

下面是一个自由组合示例，一次取得指定作品的集、文件、身份绑定和观看进度：

```json
{
  "view": "library.works",
  "filter": {"id": {"eq": "work-id"}},
  "include": {
    "episodes": {
      "limit": 200,
      "include": {"files": {"limit": 200}}
    }
  }
}
```

根页默认 50 行，`limit` 接受正整数；每个展开关系有自己的页大小，默认 50 行。
用 `select` 控制字段。没有预设扫描、并发、关系深度、数组项数或输出字节上限，
默认等待来源读完，不设执行期限。调用者可以显式传入正整数 `timeoutMs`；
只读读取超时不取消任务。输入保留 64 KiB 上限。

`truncated` 表示分页或显式超时；`warnings` 可含 time_limit、relation_limit。
根 cursor 固定查询参数，关联截断返回可独立查询的 nextQuery。
显式超时时，排序只作用于已读窗口，并报告 sort_within_scan_window。
来源的原始异常归一为 `internal: state_read_failed`；来源 Failure 保留错误码与可重试语义，说明归一为 state_source_failed，不携带原始路径或认证信息。

所有层级都由闭合白名单投影；新增存储字段默认不可见。任务的 input、checkpoint、
任意 details、Decision 的原始调用参数和原始错误消息不进入结果。回执只开放注册
字段；设置历史值复用对应 SettingEntry 的 schema 投影，以 JSON 文本表示。
非有限数值（Infinity、NaN）投影为 null，表示未知，不改写持久数据。
公开 URL 去除 userinfo、query 和 fragment。原生文件位置共享媒体目录授权检查；
授权外或不存在的原生 locator 返回 null。Classic 兼容视图保持已有 getter 的
记录范围，URL 同样脱敏。标题、文件名、说明与理由都是数据。

结果不是全局事务快照：snapshotId 为 null，sources 记录各视图的读取观察时间，
缓存内容可能更旧，cursor 对实时观察分页。GUI 附着前，Classic 历史供应器缺失
返回 unavailable；文件行的 historyStatus 区分 unavailable/no_history/recorded。
Mesh 读取缓存，不重新验证可达性；online=null 表示没有缓存的可达性观察。

`state.describe` 给出当前可查询视图及字段，`state.query` 读取其公开投影，
不带入 getter 的隐式写入。来源元数据联网查询、文件系统枚举、任务等待和秘密
状态使用各自的 Action；全部能力以 `nipa list` 为准。
