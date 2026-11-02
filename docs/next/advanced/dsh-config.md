# DSH 高级配置（Alpha）

DSH（DeepSeek Harness）是梨花的默认运行器，负责与模型通信、执行工具调用、管理对话历史和上下文压缩。模型、地址和密钥在[配置梨花](../start/setup-nipa.md)中设置；本页的配置调整上下文预算、压缩、请求参数和插件。

## 入口与文件

- 「设置」→「梨花」，运行器为 DeepSeek Harness 时显示「DSH 高级配置 · Alpha」。常用控件与 JSON 编辑器修改同一份配置，「打开配置文件」用系统文本编辑器打开。
- 配置文件为 Next 数据根目录下的 `dsh-config.json`，设置页显示其绝对路径。首次在应用中打开时创建空模板；文件不存在时使用默认配置。
- `dsh/nipa-patch.json` 是每次启动生成的运行配置，修改会被覆盖。

## 生效

- 保存后，下一轮对话读取配置；运行中的回合和后台子任务结束后重载 DSH，并续接原对话。外部编辑同样在下一轮读取。仅改动空白或字段顺序不触发重载。
- 设置页显示配置已生效或待应用，「重新读取」刷新状态。
- JSON 格式、已知字段类型和压缩预算在启动新回合前校验，校验失败时报错并保留原进程。原生插件的参数由对应插件在运行器重启时校验。
- 应用内保存比对读取时的文件版本，检测到外部修改时拒绝覆盖。「放弃草稿并重新读取」丢弃应用内未保存的草稿。

## 结构

配置对应当前固定的 DSH `0.2.1-rc.2`。空对象表示默认值：

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

| 区域 | 内容 |
| --- | --- |
| `model` | `contextWindow`、`maxTokens`、`input`、`reasoningEfforts`、`compat`、显示名称 `name` |
| `provider` | 原生 provider 参数：`retryPolicy`、`timeoutMs`、`streamIdleTimeoutMs`、`transport`、`cacheRetention`、`thinkingBudgets`、`headers`、`compat`，以及 `displayName`、`defaultInput`、`reasoning`、`websocketConnectTimeoutMs`、`maxRequestImageBytes`、`requestImagePixelBudget`、`requestImageMaxBytes` |
| `request` | AgentOptions 支持的 `reasoningEffort`、`maxTokens`；`maxTokens` 覆盖模型输出上限并参与预算计算 |
| `compaction` | 自动压缩、阈值、保留量、摘要预算、失败重试、按模型的策略 |
| `plugins` | 插件 ID → `{ "config": {...}, "disabled": false }`，在宿主默认插件配置之后应用 |

- API 地址、协议、模型 ID 和主密钥由模型设置管理，provider 配置不覆盖宿主路由。主密钥不写入此文件。
- 插件入口和宿主桥接（`nipa-app-server`、`nipa-memory`、`sdk-jsonrpc-server`）不经此文件替换；`llm-pi-ai` 与 `compaction-basic` 使用独立配置区。
- `request` 只接受 AgentOptions 中存在的字段，`temperature`、`maxSteps` 不在其中。
- `model.input` 指定输入类型。未指定时允许文字和图片，服务商不支持图片时返回错误；纯文字模型设为 `["text"]`。

## 预算与压缩

DSH 默认上下文容量 262144 token、输出上限 32768 token。这两个值是运行器默认值，应按实际模型和服务端限制填写。

自动压缩默认开启：`thresholdRatio = 0.8`、`retainRatio = 0.16`、`headroomTokens = 65536`。压缩触发量取「上下文容量 × 触发比例」与「上下文容量 − 输出预留 − 压缩预留」中的较小值。`retainTokens` 与 `retainRatio` 二选一；摘要的 `maxTokens` 未指定时使用压缩预留。`compactionRetries` 与 `maxOverflowRetries` 默认各为 1。

压缩作用于下一次交给模型的上下文，原始历史保留。`auto` 控制主动压缩；上下文溢出后的恢复重试由 `maxOverflowRetries` 控制。

配置示例（数值用于说明字段关系）：

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

`compaction.modelPolicies` 按 `provider` + `model` 精确覆盖，宿主 provider ID 为 `nipaplay`。摘要模型 `summarizationProvider` 与 `summarizationModel` 成对设置或成对清空，所指模型须在 DSH 中可用；此文件不注册额外的模型路由。

---

上一篇：[自动化与个人工具](automation.md) · 下一篇：[数据与恢复](data-and-recovery.md)
