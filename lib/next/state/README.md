# 只读公开状态

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

根页默认 50 行，最多 200 行；根行与展开关系合计最多 200 行。数组字段最多
200 项，超限标记 `field_limit`。扫描合计最多 5000 行，关系最多两级，执行预算
默认及最多 1000 ms，可用 timeoutMs 缩小；结果最多 256 KiB，输入最多 64 KiB。
最多同时存在两个来源读取，包括超时后仍未结束的读取。只读读取超时不取消任务。

`truncated` 同时表示分页与资源截断；`warnings` 区分 scan_limit、time_limit、
relation_limit、row_limit、byte_limit 和 field_limit。根 cursor 固定查询参数，
关联截断返回可独立查询的 nextQuery。扫描窗口之外可以续查；发生扫描截断时，
排序只作用于该窗口，并报告 sort_within_scan_window。单行超过输出预算返回
`unavailable: row_exceeds_output_budget`；并发超限为 query_concurrency_limit。
来源的原始异常归一为 `internal: state_read_failed`；来源 Failure 保留错误码与可重试语义，说明归一为 state_source_failed，不携带原始路径或认证信息。

所有层级都由闭合白名单投影；新增存储字段默认不可见。任务的 input、checkpoint、
任意 details、Decision 的原始调用参数和原始错误消息不进入结果。回执只开放注册
字段；设置历史值复用对应 SettingEntry 的 schema 投影，以 JSON 文本表示。
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
