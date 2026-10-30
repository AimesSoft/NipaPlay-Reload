# DSH 高级配置（Alpha）

设置 → 梨花 → 选择 DeepSeek Harness 后，提供「DSH 高级配置 · Alpha」。
常用控件和 JSON 编辑器修改同一个文档；可直接用「打开配置文件」交给系统文本编辑器。

配置源是 **Next 数据根目录下的 `dsh-config.json`**，设置页显示实际绝对路径。
应用首次打开文件时创建空配置模板。不存在此文件时沿用默认配置，读取不会创建文件。
不要编辑 `dsh/nipa-patch.json`：那是每次启动生成的运行配置，会被覆盖。

## 生效与恢复

- 保存不会中断执行中的回合或后台子任务；下一轮读取配置，等待正在执行的任务完成后重载 DSH，并续接原对话。
- 外部编辑也在下一轮读取。仅调整 JSON 空白或字段顺序不会触发重启。
- 设置页显示已生效或待应用状态；运行后用「重新读取」更新状态。
- JSON 格式、已知字段类型及压缩预算检查失败，会明确报错；启动新回合前检查失败时保留旧进程。修正文件后重试即可。
- 原生插件内部参数由对应 DSH 插件最终校验；这些错误仍可能在运行器重启时出现。Alpha 不承诺任意插件组合都能正常启动。
- 应用内保存会比对读取时的文件版本，拒绝覆盖已检测到的外部修改。不要同时在两个编辑器保存同一个文件；外部程序不共享应用的写入队列。
- 「放弃草稿并重新读取」明确丢弃应用内未保存草稿。普通设置刷新不会覆盖草稿。

## 配置结构

配置针对当前固定的 DSH `0.2.1-rc.2`。空对象表示使用默认设置：

```json
{
  "schema": 1,
  "model": {},
  "provider": {},
  "request": {},
  "compaction": {},
  "plugins": {}
}
```

| 区域 | 用途 |
| --- | --- |
| `model` | `contextWindow`、`maxTokens`、`input`、`reasoningEfforts`、`compat`、显示名称 `name` |
| `provider` | 原生 provider 参数，如 `retryPolicy`、`timeoutMs`、`streamIdleTimeoutMs`、`transport`、`cacheRetention`、`thinkingBudgets`、`headers`、`compat` |
| `request` | 当前 AgentOptions 支持的 `reasoningEffort`、`maxTokens`。后者覆盖模型输出上限，并同步到运行时模型信息用于预算计算 |
| `compaction` | 自动压缩、阈值、保留量、摘要预算、失败重试和精确模型策略 |
| `plugins` | 已有插件 ID → `{ "config": {...}, "disabled": false }`，在宿主默认插件配置之后应用 |

API 地址、协议、模型 ID 和主密钥仍在模型设置中管理；不允许 provider 覆盖宿主路由。
插件入口和宿主桥接（`nipa-app-server`、`nipa-memory`、`sdk-jsonrpc-server`）不通过该文件替换。
`llm-pi-ai` 与 `compaction-basic` 使用独立配置区。此界面不是任意 npm 插件安装器。
配置是普通本地 JSON 文件，主 API 密钥不会写入其中。

原生 provider 可用字段还包括 `displayName`、`defaultInput`、`reasoning`、
`websocketConnectTimeoutMs`、`maxRequestImageBytes`、`requestImagePixelBudget`、`requestImageMaxBytes`。
不要向 `request` 填入 DSH AgentOptions 没有的 `temperature` 或 `maxSteps`。
`model.input` 可显式指定输入类型。未指定时允许发送文字和图片，由实际 API 返回不支持的错误；不再用测试图片的回答判断能力，也不读取旧的图片探测缓存。纯文字模型可设置 `["text"]`。

## 默认预算与压缩

当前 DSH 默认上下文容量 **262144 token**、输出上限 **32768 token**，这些是运行器默认值，
**不是服务商已确认的模型容量**。应按实际模型与服务端限制填写。

默认自动压缩开启，`thresholdRatio = 0.8`、`retainRatio = 0.16`、`headroomTokens = 65536`。
实际压缩触发量同时受「上下文容量 × 触发比例」与「上下文容量 − 输出预留 − 压缩预留」限制，取较低者。
`retainTokens` 与 `retainRatio` 二选一；摘要 `maxTokens` 未指定时沿用压缩预留。
`compactionRetries` 与 `maxOverflowRetries` 默认各为 1。

原生自动压缩压缩的是下一次交给模型的上下文，原始持久历史仍可回看。
关掉 `auto` 不等于关掉上下文溢出后的恢复重试；该行为由 `maxOverflowRetries` 控制。

例如（仅演示配置关系，不代表推荐的服务商容量）：

```json
{
  "schema": 1,
  "model": {"contextWindow": 131072, "maxTokens": 8192},
  "provider": {"retryPolicy": {"mode": "normal", "maxRetries": 3}},
  "request": {},
  "compaction": {
    "auto": true,
    "thresholdRatio": 0.8,
    "retainRatio": 0.16,
    "headroomTokens": 16384,
    "maxTokens": 8192,
    "compactionRetries": 1,
    "maxOverflowRetries": 1
  },
  "plugins": {"tool-web": {"config": {"fetch": true}}}
}
```

`compaction.modelPolicies` 支持按 `provider` + `model` 精确覆盖，宿主 provider ID 为 `nipaplay`。
摘要目标的 `summarizationProvider` 和 `summarizationModel` 必须成对设置或成对清空；
所指模型必须在 DSH 中可用，本文件不会注册额外模型路由。
