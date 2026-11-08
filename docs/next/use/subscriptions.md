# 订阅与自动下载

可以对梨花说：“帮我追这部番，按我们确认的版本，每周检查，有更新就下载。”
追剧和电影也一样。仅仅说“找找资源”不会建立订阅。先说明要追的作品，已有的字幕、
清晰度、来源和目录偏好可以一并告诉她。

## 她会建立什么

梨花先确认作品身份，选来源，写下过滤规则，预览一次候选给你看，然后建立订阅和定时程序。
每条订阅保存作品、状态、她写给你看的一句话、巡查程序路径、规则和出处。
到点时脚本取候选、执行她写的规则、去重，命中后直接调用下载；普通检查不需要每次唤醒她。
规则要求询问、同集候选冲突、下载结果不明或连续失败时，再请她处理。

订阅只在**运行梨花的设备**上执行：电脑或[无界面宿主](../advanced/headless.md)。
关掉应用、关闭 Next 或停掉宿主后，巡查也停止；重启不会补跑错过的时间。不提供 NAT 穿透，
Jackett、Prowlarr 或 RSS 必须能从执行巡查的设备访问。

## 在哪里看和管理

订阅数据会推送给界面，包含作品标题、已有海报、状态、最近检查、最近下载和来源设备。
手机、平板和电视读取所选梨花设备的数据；合并多台设备时标明来源，不会在手机重复巡查。
“在追”的页面视觉由界面层接入；当前可以直接让梨花“列出我的订阅”或“暂停这部作品”。
查询入口为 `subscription.list/get` 和 `state.query` 的 `subscriptions` 视图。

暂停和恢复使用 `subscription.set_state`；结束可设 `ended`。删除用 `subscription.remove`，
只删除订阅与检查记录，保留下载任务、文件、程序和已保存的凭据。暂停不会取消已发起的下载。
远程操作在来源设备执行，例如 `nipa --device 家里的电脑 call subscription.set_state ...`。

## Jackett、Prowlarr 和 PT RSS

先安装并配置自己的索引器，给梨花**明确指定的 API 端点**。Jackett 通常由每个索引器的
Torznab feed 页面提供地址；Prowlarr 同样提供 Torznab 地址。不要让她猜服务器地址或搜索其他账号的凭据。
告诉她：“把这个 API Key 存到这台巡查电脑的保险库，名字叫 `jackett-main`。”
`secrets.set` 会记录这句用户授权。名字可查，值不会进入审计、数据库、回执或 harness Git。
请勿把密钥写进对话后的笔记、脚本参数、规则 JSON 或来源 URL。

脚本用 `torznab.py caps --url API地址 --secret jackett-main` 查询能力；
`search` 接受 `--q`、`--cat`、`--tmdbid`、`--imdbid`、`--season`、`--ep`；
`rss` 读取这个端点的最新条目。没有内置站点、索引器和版本选择。

PT 标准 RSS 可用 `rss.py 'https://站点/rss?passkey={secret}' --secret pt-rss`。
passkey 由 `secrets.get` 在进程内注入；输出只留下 `{secret}` 模板，不打印原始认证 URL。
RSS、Atom 和 enclosure 中的种子链接都作为来源证据。具体过滤规则仍由梨花写在个人巡查程序中。
更改或移除密钥也在巡查设备上操作；密钥读取不开放 Mesh，手机可让目标梨花处理配置。

## 给梨花的模板约定

[种子工具](../../../assets/next/harness/tools/README.md) 提供 `tools/patrol.py` 与
`hooks/download.file_completed.py`。这是可改可删的个人程序，不是宿主的自动选片策略。
来源和规则保存在订阅的 `facts`，例如（作品 ID、来源与绑定须先核实）：

```json
{
  "sources": [{"kind": "rss", "url": "https://example.invalid/rss", "credentialName": "pt-rss", "credentialParameter": "passkey"}],
  "rules": {
    "include": ["用户指定字幕组", "1080p"],
    "exclude": ["用户不要的版本"],
    "episodeRegex": " - (?P<episode>[0-9]+)",
    "minBytes": 100000000,
    "maxBytes": 4000000000,
    "priority": ["用户首选版本"],
    "ask": false,
    "errorWakeAfter": 3
  },
  "download": {"createFolderForTask": true},
  "bindings": {
    "03": {"files": {"0": {
      "ref": {"provider": "tmdb", "objectType": "episode", "externalId": "已核实ID", "scope": "已核实scope"},
      "localEpisodeIds": ["已核实的Next剧集ID"],
      "reason": "用户确认的本作品第3集"
    }}}
  }
}
```

`include` 的表达式全部需命中，`exclude` 任一命中即排除；声明大小范围时未知大小不通过。
剧集必须显式提供带 `episode` 命名组的正则，捕获值原样用作映射键（`03` 与 `3` 不自动转换）。
`priority` 越靠前越优先，同集同优先级的多个候选要询问；电影使用 `movie` 键。
`sources.kind` 支持 `mikan`（给出 RSS URL）、`rss`、`torznab`；后者可带 `operation` 与
`params`（q、cat、tmdbid、imdbid、season、ep、indexer）。来源凭据只写 `credentialName` 名字。
RSS 的参数名写 `credentialParameter`，URL 只写无凭据部分，由脚本组装 `{secret}` 模板；
不要把带 passkey 参数的 URL 放入订阅事实，否则公共输出的 URL 脱敏会遮掉它。

先把完整订阅声明写到临时 JSON，用 `python3 tools/patrol.py --preview 声明.json` 预览，
它只读来源，不保存、不下载。确认后调用 `subscription.put`，`program` 填 `tools/patrol.py`，
并在 `hooks/schedules.json` 加入一项，例如：

```json
[{"id":"subscription-patrol", "program":"tools/patrol.py", "everySeconds":1800}]
```

不要覆盖已有的定时项。工具只处理 `program` 指向自身且状态为 active 的订阅；
路径是 harness 内相对路径，macOS/Linux 要有可执行位。Windows 使用 `.py` 后缀。
`facts` 最多 16384 UTF-8 字节；每台设备最多 500 条订阅。检查回报每次最多 32768 字节，
包含时间、候选、下载的 jobId/标题/集号、错误；保留最近 20 次，另保留最近有下载的一批。
`subscription.report` 的 `reportId` 是重试键，同键不同内容会拒绝。

巡查将去重记录与 jobId → 订阅、作品、集号、明确绑定写入被 Git 忽略的 `records/subscriptions/`。
下载请求结果不明时保留 intent，请核对 `task` / `download` 后再修复记录，不直接重下。
不要删除记录来“重试”，否则会失去去重依据。更新规则不会自动忘记已处理的集。

完成钩子只使用梨花预先写明的**文件索引 → 身份**映射调用 `media.identity.bind_batch`，
不会按文件名猜集号，也不把一集身份套到整个合集。缺映射、远端文件尚未传输时请她判断。
绑定后读取既有 `library.fileOrganization` 和 `library.fileOrganizationRules`：off 保持文件原样，
ask 或 auto 交给梨花沿用原有整理流程；不另做命名、移动和刮削引擎。
仍需保留身份、进度、字幕、弹幕与做种关系；无法保留时报告，不能冒充归档成功。

---

返回[下载](downloads.md)或[文档首页](../README.md)。
