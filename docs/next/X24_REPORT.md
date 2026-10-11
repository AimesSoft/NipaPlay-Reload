# X24：连接实例事实、界面截图与能力可发现性

2026-10-11。工作目录 `~/Desktop/nipaplay-next-wt/ui-facts`，分支 `next/ui-facts`。

## 1. 完成了什么

- `nipa status.instance` 与新只读能力 `app.instance` 报告实际 PID、可执行文件路径、应用包路径、主窗口标题/ID、Flutter view ID、实验配置及版本。
- 新增 `ui.capture`，把所连接进程主窗口的整个 Flutter 内容写成 Agent 可直接读取的临时 PNG；返回尺寸、时间、实例事实与截图局限。
- 删除 `ui.navigate`、其 Action/输入输出模型及旧测试，没有内部兼容层。运行时提供 `ui.open`；切页观察实际渲染页体，等待现有标签动画结束。更新活跃说明和种子 AGENTS.md；历史实验和 v1 归档保留当时的工具名。
- 种子补入多份 NipaPlay 并存的事实，说明应用名/bundle id 与当前连接实例的关系，以及 `ui.*` 的实例归属，没有新增操作步骤。
- `media.identity.bind_batch` 的实时 describe 给出两种输入模式、三层关系、各 ID 字段含义、provider ref 的 scope 写法和完整批量示例。层级错误给出期望及实际父实体；目录集 ref 错误给出可直接采用的完整期望 ref 与精确字段路径。拒绝该层级不消费的父 ID/时间段等字段，避免静默忽略。
- 来源登录的三个成功分支（已认证 checkpoint 恢复、Quick Connect、密码/登录窗口）在同一次持久化更新中保存 `state=succeeded`、`phase=connected` 和回执。

## 2. 决策

**实例事实由宿主报告。** macOS 从当前进程的 Bundle 和持有的主窗口读取路径、标题及窗口/view ID；不按应用名查找。其余平台报告进程可执行文件，应用包路径无对应概念时为 null。实验标记表示 LabProfile，不表示 Next 开关。CLI 状态、Action 和截图复用 InstanceFacts。

**截图取 Flutter 主窗口场景。** 使用当前窗口 view ID 定位 RenderView，以原始物理尺寸栅格化根场景，无需屏幕录制权限或全屏截图。页面、控件、弹窗和 Flutter 提示均在范围内。OS 窗口边框、其他窗口、外部播放器，以及场景外的原生视频覆盖层/平台视图不在范围内；Erika 原生弹幕和 `playback.capture` 一样不包含。describe 和每次回执都明示这些局限。PNG 保存在宿主临时目录，Mesh 不传图片；本轮真实窗口验证在 macOS Debug 完成。

截图 Action 单独注册，避免通用 FileIndexingCapability 将输出图片登记成媒体文件；`ui.open` 仍保留原有播放位置登记。没有增加截图按钮：用户本来就在观看此界面，新增能力补的是 Agent 的观察入口。

**身份说明随工具提供。** 不新增引导流程或要求先读 README；已知作品/集编号时，describe 足够生成一批输入。内置目录模式的作品 → 版本 → 集关系由已有事务校验，任意来源的 direct 模式保持显式绑定，不替 Agent 判断跨来源对应关系。来源编号与本地实体 ID 分开说明；scope 是来源命名空间字符串。错误保留批量原子性。

**登录阶段与终态一起保存。** 给 JobContext.succeed 增加可选 phase，由来源登录指定 `connected`；其他调用保留原语义。没有改写旧回执或执行数据迁移，也没有改 Classic 导航/登录行为；切页修正仅在 Next 的观察适配器中。

## 3. 实验与真实输出

### 环境与验证范围

全部构建在本 worktree，Flutter 固定 `~/development/flutter-3.44.6`，build/analyze/test 均 `--no-pub`，构建使用 `ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache`。只直接运行：

```bash
NIPAPLAY_PROFILE=x24facts \
  ~/Desktop/nipaplay-next-wt/ui-facts/build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay
```

该实验配置从空目录创建，只预置 Next 开关和本地协议 fixture 地址。应用进程清空代理变量，CLI 自带回环 DIRECT；测试中的 HttpClient 同样绕开代理。fixture 在 `127.0.0.1:65523` 提供合成弹弹play目录和 Jellyfin 登录协议，源码见 [fixture.py](evidence/x24/fixture.py)。这些是实际 NipaPlay 进程、真实窗口和真实回执，服务器响应是本地合成协议数据，不是生产服务器登录实验。

没有启动 `/Applications/NipaPlay.app`，没有按名称/bundle id 查找应用，没有使用用户登录钥匙串或真实数据目录，没有操作 lab10。实验凭据由已有 LabFileVault 保存到临时配置内。

### 3.1 用 status 与 ps 认出实例

从临时 harness 调用 `nipa status`，最后验证实例的真实输出节选如下，完整输出见 [status.json](evidence/x24/status.json)：

```json
{
  "status": "running",
  "instance": {
    "pid": 21098,
    "viewId": 1,
    "windowId": 44350,
    "windowTitle": "NipaPlay · LAB [x24facts]",
    "executablePath": "~/Desktop/nipaplay-next-wt/ui-facts/build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay",
    "appBundlePath": "~/Desktop/nipaplay-next-wt/ui-facts/build/macos/Build/Products/Debug/NipaPlay.app",
    "experimentalProfile": true,
    "profileName": "x24facts",
    "version": "1.11.10"
  }
}
```

`ps -p 21098 -o pid=,ppid=,command=`：

```text
21098     1 ~/Desktop/nipaplay-next-wt/ui-facts/build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay
```

PID 与可执行文件路径一致，应用包在本 worktree，标题明确显示 `LAB [x24facts]`。[app.instance 的回执](evidence/x24/instance.json) 返回相同事实。中途为了修正观察适配器及截图登记，先前实例 15924、18709 均先按 PID 退出再重建/启动。

### 3.2 打开媒体库并读截图

先 `ui.open {"page":"home"}`，再 `ui.open {"page":"media_library"}`。后一调用：

```json
{
  "status": "completed",
  "result": {
    "opened": true,
    "interface": "classic",
    "target": {
      "page": "media_library"
    },
    "actual": {
      "kind": "page",
      "page": "media_library"
    },
    "reason": null,
    "message": null
  }
}
```

随后 `ui.capture {}` 的真实回执节选（完整回执包含与 status 相同的实例事实）：

```json
{
  "path": "~/Library/Application Support/NipaPlay/LabProfiles/x24facts/temp/ui-captures/1791726432745323.png",
  "bytes": 133287,
  "mimeType": "image/png",
  "width": 3024,
  "height": 1744,
  "capturedAt": "2026-10-11T13:47:12.746155Z",
  "surface": "main_window_flutter_content",
  "limitations": [
    "Erika native danmaku is not included, as with playback.capture.",
    "Native video overlays and platform views outside the Flutter scene are not included.",
    "The OS window frame, other windows and external players are not included."
  ]
}
```

已经用图片读取工具打开 [Agent 截图](evidence/x24/media-library.png)，并打开 [同一原生窗口截图](evidence/x24/native-window.png) 作人工对照。对照图仅通过回执的窗口 ID 44350 调用 `screencapture -x -o -l 44350` 获取，不查应用名。两图的选中媒体库标签、搜索框、空库提示、LAB 角标及右下角启动提示一致；原生对照多出左上角系统交通灯和窗口圆角，符合回执局限。PNG 为 3024 × 1744，整个界面可读。该库为空符合本实验只绑定身份、没有登记可播放文件的输入；截图没有声称绑定会创建 Classic 观看历史。

`ui.open {"page":"webdav"}` 返回 `opened=false`，原因是 `Classic 当前没有可见的 webdav 页面。`，见 [ui-unavailable.json](evidence/x24/ui-unavailable.json)。实时能力目录只有 `ui.open`、`ui.capture`，调用已删除的 `ui.navigate` 得到：

```json
{"error": "NipaPlay returned HTTP 404"}
```

首次窗口实验还发现两个问题并完成修正：

1. X22 的祖先 AppNavigationScope.selectedPageId 不随内部 scaffold 的切页重建，首次切页虽然界面变了，回执却是 false，见 [initial-ui-open.json](evidence/x24/initial-ui-open.json)。Next 现在等待现有标签动画，再观察主 scaffold 实际 SwitchableView.currentIndex；最后从首页切到媒体库返回 true，并通过两张图核实。
2. 原通用文件包装将两个临时 PNG 当成媒体位置登记。分离截图能力后，最后截图前后 SQLite 的实际观察如下；2 个旧实验图片事实保留到整个临时配置删除，没有在运行中清除持久记录：

```json
{
  "beforeFileCount": 2,
  "afterFileCount": 2,
  "locationsUnchanged": true,
  "newCaptureIndexed": false
}
```

### 3.3 新 Agent 只读 describe，一次绑定三层

独立实验 Agent 使用 `fork_turns=none`，只允许读运行实例导出的 [bind-describe.json](evidence/x24/bind-describe.json)。任务只提供已核实的来源事实：弹弹play animeId=7001、版本为该 anime 目录、第一集实际 episodeId=7101；不提供输入字段写法或 scope 提示。它生成 [fresh-agent-input.json](evidence/x24/fresh-agent-input.json)，显式含 work/release/episode 三条，省略本地 ID 和 releaseRef，用 `scope=""` 与 `scope="anime/7001"`。其判断见 [fresh-agent-notes.txt](evidence/x24/fresh-agent-notes.txt)。

该文件提交一次即成功，[完整输出](evidence/x24/bind-result.json)：

```json
{
  "status": "completed",
  "result": {
    "entries": [
      {
        "index": 0,
        "workId": "work-ff948ed78c87cee1521ed4890da5025b27c71c57b5e2def8941a4b91003b22f1",
        "releaseId": null,
        "episodeIds": [],
        "fileId": null,
        "bindingIds": [
          "binding-7fec0451be71944af9b306fd8201568ac1bd2bb6a58455032946f840f0b0f026"
        ]
      },
      {
        "index": 1,
        "workId": "work-ff948ed78c87cee1521ed4890da5025b27c71c57b5e2def8941a4b91003b22f1",
        "releaseId": "release-ff948ed78c87cee1521ed4890da5025b27c71c57b5e2def8941a4b91003b22f1",
        "episodeIds": [],
        "fileId": null,
        "bindingIds": [
          "binding-7fec0451be71944af9b306fd8201568ac1bd2bb6a58455032946f840f0b0f026",
          "binding-886d2f77f83bf0d14cf998197807d7acbea679cb1e594b3dc62ae9c28df0af21"
        ]
      },
      {
        "index": 2,
        "workId": "work-ff948ed78c87cee1521ed4890da5025b27c71c57b5e2def8941a4b91003b22f1",
        "releaseId": "release-ff948ed78c87cee1521ed4890da5025b27c71c57b5e2def8941a4b91003b22f1",
        "episodeIds": [
          "episode-7ea457eb0f136703b38cead2964a0d04375e6c258f42ba544a69ca6974234466"
        ],
        "fileId": null,
        "bindingIds": [
          "binding-7fec0451be71944af9b306fd8201568ac1bd2bb6a58455032946f840f0b0f026",
          "binding-886d2f77f83bf0d14cf998197807d7acbea679cb1e594b3dc62ae9c28df0af21",
          "binding-9e329cfb6a2d86b22ba49a1d5791c9e1d75756099eb81c0d9db66c34799424fa"
        ]
      }
    ]
  }
}
```

故意将 episode ref.scope 改成 `release/7001`，使用新的 requestId 提交一次，得到：

```json
{
  "status": "failed",
  "error": {
    "code": "invalid_input",
    "message": "Entry 0: Episode ref {\"provider\":\"dandanplay\",\"objectType\":\"episode\",\"externalId\":\"7101\",\"scope\":\"release/7001\"} is not a member of the selected release catalogue {\"provider\":\"dandanplay\",\"objectType\":\"anime\",\"externalId\":\"7001\",\"scope\":\"\"}. Expected episodeRefs to contain [{\"provider\":\"dandanplay\",\"objectType\":\"episode\",\"externalId\":\"7101\",\"scope\":\"anime/7001\"}]; scope is the provider namespace string, not a local release ID.",
    "retryable": false,
    "violations": [
      {
        "path": "/entries/0/episodeRefs/0",
        "message": "Expected [{\"provider\":\"dandanplay\",\"objectType\":\"episode\",\"externalId\":\"7101\",\"scope\":\"anime/7001\"}]."
      }
    ]
  }
}
```

同一新 Agent 随后只读错误输入和错误回执，生成 [修正输入](evidence/x24/fresh-agent-corrected.json)，将 scope 改为 `anime/7001`，不需要查代码或猜字段；提交一次成功，见 [bind-corrected-result.json](evidence/x24/bind-corrected-result.json)。[身份读回](evidence/x24/identity-readback.json) 与 [SQLite 只读审计](evidence/x24/binding-audit.json) 确认只有 1 个 work、1 个 release、1 个 episode 和 3 条 accepted 绑定；成功操作回执为 2 条，错误请求未保存操作回执。

### 3.4 来源登录回执

`media.sources.add` 添加本地 Jellyfin fixture，随后 `media.sources.login` 使用 Quick Connect。批准前 task.get 的真实字段节选：

```json
{
  "state": "running",
  "phase": "awaiting_approval"
}
```

批准 fixture 返回的合成代码后，`nipa watch` 返回：

```json
{
  "status": "completed",
  "result": {
    "job": {
      "code": "246810",
      "jobId": "source-login-0fbcae4d-e719-46e9-b784-41eda68b354a",
      "type": "media.sources.login",
      "title": "Log in to X24 loopback fixture",
      "state": "succeeded",
      "phase": "connected",
      "progress": {
        "completed": 0,
        "unit": "items"
      },
      "createdAt": "2026-10-11T13:40:33.861770Z",
      "updatedAt": "2026-10-11T13:40:36.075637Z",
      "ownerDeviceId": "device-fd73ce7b3bac5e587ab1ee75e8632535",
      "revision": 4,
      "receipt": {
        "verification": "verified",
        "details": {
          "sourceId": "jellyfin:1791725929562",
          "connected": true,
          "method": "quickConnect"
        }
      }
    }
  }
}
```

另用合成密码走一次 password 分支，也得到成功；字段节选，完整输出见 [password-receipt.json](evidence/x24/password-receipt.json)：

```json
{
  "state": "succeeded",
  "phase": "connected",
  "receipt": {
    "verification": "verified",
    "details": {
      "sourceId": "jellyfin:1791725929562",
      "connected": true,
      "method": "password"
    }
  }
}
```

[来源实时检查](evidence/x24/source-check.json) 返回 `checked=true`、`connected=true`、`connectionState=connected`。[重启后的任务读回](evidence/x24/login-receipt-after-restart.json) 仍为 succeeded/connected，说明终态阶段已持久保存。

fixture 首轮漏了 POST /QuickConnect/Initiate，实际返回 `Bad state: Quick Connect HTTP 404`，见 [失败回执](evidence/x24/source-login-fixture-failure.json)；补齐 fixture 后登录成功。首轮 /UserViews 也缺失，来源检查返回 `Exception: 请求的资源未找到 (HTTP 404)`；补齐后检查成功。这两次修正只涉及实验 fixture。

### 3.5 构建、约束测试与清理

- macOS Debug 构建通过：[build.log](evidence/x24/build.log)，实际末行 `✓ Built build/macos/Build/Products/Debug/NipaPlay.app`。
- 相关范围 analyze：[analyze-scoped.log](evidence/x24/analyze-scoped.log)，`No issues found!`。
- 身份事务/原子性、来源凭据与回执约束、SQLite 任务持久化、Classic 观看历史和 Jellyfin 授权回归：[tests.log](evidence/x24/tests.log)，`00:01 +46: All tests passed!`。
- 补入 connected 阶段重开数据库断言后，SQLite 任务约束复验：[receipt-tests.log](evidence/x24/receipt-tests.log)，`00:00 +10: All tests passed!`。
- endpoint 凭据隔离/轮换、仓库文件保持等约束：[endpoint-constraints.log](evidence/x24/endpoint-constraints.log)，`00:01 +4: All tests passed!`。自动化没有用于证明 UI 功能。
- `git diff --check` 通过。没有 commit/push，没有改依赖。

最初构建缺忽略的 .dart_tool/package_graph.json 和原生 Swift Package 生成配置；从 lock 完全相同的 activity worktree 补回并重定位生成路径及链接，未运行 pub get。首次恢复漏掉目录 symlink，Swift 包解析失败，保留于 [build-metadata-failure.log](evidence/x24/build-metadata-failure.log)，补回链接后构建通过。CocoaPods 自动改写 Podfile.lock 的 Erika pod 版本/校验值已恢复原值。首次全仓 analyze 报 6003 条问题，包含初版截图代码的 Flutter Action 导入名冲突，以及大量独立 package 测试、vendored 示例的解析/分析问题，见 [原始输出](evidence/x24/analyze.log)。导入冲突已修正；根场景访问的 protected 提示附上准确理由并局部忽略，随后相关范围 analyze 无问题。现有原生/脚本构建警告保留在日志中。

已按 PID 退出最后 App 21098 与 fixture 16704，先前 App 15924、18709 也已退出；仅删除 `LabProfiles/x24facts` 和 fixture 临时端口文件。[清理证据](evidence/x24/cleanup.json)：

```json
{
  "stopped": [
    {
      "role": "app",
      "pid": 21098,
      "runningAfter": false
    },
    {
      "role": "fixture",
      "pid": 16704,
      "runningAfter": false
    }
  ],
  "profileExists": false,
  "fixturePortFileExists": false
}
```

回执中的临时图片原路径随实验目录删除；供审阅的 PNG 副本、真实输出和报告保存在本 worktree 的 evidence/x24。

## 4. 需要主控决定的问题

没有。
