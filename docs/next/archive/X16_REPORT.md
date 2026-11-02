# X16：截图与原生弹幕的事实陈述

## 1. 完成了什么

在 worktree `~/Desktop/nipaplay-next-wt/capture-fact`、分支 `next/capture-fact` 完成。已阅读 `TEAM.md` 与 `EXPERIMENTS.md` 的实验 8。

`playback.capture` 的截图结果保留 `path`、`bytes`、`kind`，新增：

| 字段 | 含义 |
| --- | --- |
| `danmakuRequested` | 显式 `includeDanmaku`，或省略参数时采用的截图设置 |
| `danmakuIncluded` | 本次截图是否保留显示中的弹幕层；Erika 一律为 `false` |
| `danmakuReason` | 排除原因；保留弹幕层时为 `null` |

Erika 的原因明确写出原生弹幕不在 snapshot 中，即使 `includeDanmaku=true` 也不包含；不能据此推断轨道未加载或屏幕上没有弹幕。其他内核的排除原因区分截图参数/默认设置关闭与弹幕显示开关关闭。

能力 description、输出 schema 与 `player.screenshotIncludeDanmaku` 设置说明都公开了这一事实。GIF 结果未增加这些截图字段。

检查了 Next 的 `danmaku.tracks`、`state.query` 的 `danmaku.bindings` / `danmaku.tracks` 视图，以及 `danmaku.visible` 设置：

- `loaded` 来自播放器轨道注册表，Erika 原生弹幕也有轨道记录；不是从 Flutter 弹幕 overlay 是否为空推断。未发现需要改动的加载状态计算。
- 轨道 `enabled` 和全局 `danmaku.visible` 是显示开关，不是当前帧可见弹幕的遥测。补充相关字段与能力说明，明确已挂载/已启用不能证明当前时刻有可见评论。
- 现有 Next 接口没有原生渲染器当前可见评论的遥测。没有根据截图、轨道数或开关虚构这种状态。

Classic 截图实现、渲染器、播放器适配器和弹幕安装/加载逻辑均未修改。生产代码仅改 Next 返回元数据与说明。没有改依赖、commit 或 push，没有构建主仓库、启动真实应用、访问用户钥匙串或真实数据目录。

## 2. 决策

1. 在 Next 的 `ClassicPlaybackControls.capture` 桥接层描述既有截图行为，继续原样传递截图参数给 Classic；不为了满足请求而改 Erika 的原生截图。
2. 用与现有截图分支相同的 `getPlayerKernelName() == 'Erika'` 条件判断限制，避免把截图设置或选中的 Flutter 弹幕内核当成有效的原生截图能力。
3. `danmakuIncluded=true` 表示保留弹幕层，不保证层里当前有评论像素。能力与 schema 明确说明这一语义：时间位置、过滤、透明度和轨道开关仍可能使画面没有评论。没有可见性遥测就不宣称“已经在屏幕上看到了弹幕”。
4. 输出字段为增量扩展，GIF 继续返回原有结果；截图的实际文件生成、默认目录、格式与覆盖保护保持原有路径。
5. 实验采用隔离测试夹具：原生帧使用合成蓝色 PNG；Flutter 截图边界使用纯红标记代表显示中的弹幕层，并遵守播放器 UI 相同的显示/截图开关。调用真实 Classic 截图方法与 Next Action，解码实际保存的 PNG 并检查像素。内核身份/原生支持由夹具提供，并未启动真实 Erika、MDK、Media Kit 或 Video Player 实例。这验证返回契约与既有截图分支，不替代真机渲染观察。

## 3. 实验

以下命令均在本 worktree 执行，使用 Flutter 3.44.6，均带 `--no-pub`。临时文件写入测试专属系统临时目录；设置使用 `SharedPreferences` mock，路径使用测试专属 `PathProvider`，结束后删除截图目录。

### 截图结果与像素

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub --reporter expanded test/next/capture_fact_experiment_test.dart
```

四个内核身份各覆盖六种组合：显式包含、显式排除、省略参数且默认关闭、显式包含覆盖关闭的默认值、省略参数且默认开启、包含请求但全局显示关闭。共 24 次截图，验证实际文件、返回 schema、请求默认值与截图后设置恢复。Erika 六次均走 snapshot，其他身份均走 repaint boundary。

最终运行真实输出节选（日志打印结果时省略随机临时路径）：

```text
X16 Erika input=true setting=true visible=true result={"bytes":86,"kind":"screenshot","danmakuRequested":true,"danmakuIncluded":false,"danmakuReason":"Erika native danmaku is not included in snapshots, even when includeDanmaku is true. This does not indicate unloaded tracks or invisible on-screen danmaku."} rgb=0,0,255
X16 Erika input=null setting=true visible=true result={"bytes":86,"kind":"screenshot","danmakuRequested":true,"danmakuIncluded":false,"danmakuReason":"Erika native danmaku is not included in snapshots, even when includeDanmaku is true. This does not indicate unloaded tracks or invisible on-screen danmaku."} rgb=0,0,255
X16 MDK input=true setting=true visible=true result={"bytes":97,"kind":"screenshot","danmakuRequested":true,"danmakuIncluded":true,"danmakuReason":null} rgb=255,0,0
X16 MDK input=false setting=true visible=true result={"bytes":97,"kind":"screenshot","danmakuRequested":false,"danmakuIncluded":false,"danmakuReason":"Danmaku was excluded by includeDanmaku or the screenshot setting."} rgb=0,0,255
X16 MDK input=null setting=false visible=true result={"bytes":97,"kind":"screenshot","danmakuRequested":false,"danmakuIncluded":false,"danmakuReason":"Danmaku was excluded by includeDanmaku or the screenshot setting."} rgb=0,0,255
X16 MDK input=true setting=false visible=true result={"bytes":97,"kind":"screenshot","danmakuRequested":true,"danmakuIncluded":true,"danmakuReason":null} rgb=255,0,0
X16 MDK input=true setting=true visible=false result={"bytes":97,"kind":"screenshot","danmakuRequested":true,"danmakuIncluded":false,"danmakuReason":"The danmaku display switch is off."} rgb=0,0,255
X16 Media Kit input=true setting=true visible=true result={"bytes":97,"kind":"screenshot","danmakuRequested":true,"danmakuIncluded":true,"danmakuReason":null} rgb=255,0,0
X16 Media Kit input=false setting=true visible=true result={"bytes":97,"kind":"screenshot","danmakuRequested":false,"danmakuIncluded":false,"danmakuReason":"Danmaku was excluded by includeDanmaku or the screenshot setting."} rgb=0,0,255
X16 Video Player input=true setting=true visible=true result={"bytes":97,"kind":"screenshot","danmakuRequested":true,"danmakuIncluded":true,"danmakuReason":null} rgb=255,0,0
X16 Video Player input=false setting=true visible=true result={"bytes":97,"kind":"screenshot","danmakuRequested":false,"danmakuIncluded":false,"danmakuReason":"Danmaku was excluded by includeDanmaku or the screenshot setting."} rgb=0,0,255
X16 Erika registry: loaded=true enabled=true displaySwitch=false
00:00 +4: All tests passed!
```

蓝色为合成视频/无弹幕标记，红色为显示层标记。Erika 的包含请求如实返回 `false` 和原生限制原因；其他身份仍按参数、默认值与显示开关保留或排除标记。

注册表观察来自给播放器注册表放入一条合成绑定轨道，再经 `VideoDanmakuPort.loaded` / `registry` 读取。显示关闭时仍可同时 `loaded=true`、`enabled=true`，说明这些值不能当成屏幕可见性；该观察不声称测试启动了原生弹幕引擎。夹具也验证 Erika 的显示关闭被送到原生 visibility delegate。

### 相关回归

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub --reporter expanded \
  test/next/playback_controls_constraints_test.dart \
  test/next/danmaku_player_update_test.dart \
  test/next/danmaku_import_test.dart \
  test/next/danmaku_unification_test.dart \
  test/next/state_query_test.dart \
  test/next/settings_registry_test.dart \
  test/native_danmaku_visibility_test.dart
```

```text
00:01 +53: All tests passed!
```

覆盖输出文件不覆盖、GIF 参数约束、绑定与导入、轨道更新和统一注册表、状态查询、设置 schema 与原生弹幕 visibility delegate。该组输出包含既有无 UI 测试的 wakelock channel 不可用诊断，测试仍全部通过。

### 静态检查

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
  lib/next/capabilities/classic_playback_controls.dart \
  lib/next/capabilities/playback_controls_capability.dart \
  lib/next/danmaku/capability.dart \
  lib/next/state/views.dart \
  lib/next/settings/application_settings.dart \
  test/next/capture_fact_experiment_test.dart
git diff --check
```

```text
Analyzing 6 items...
No issues found! (ran in 3.4s)
```

`git diff --check` 退出码为 0，无输出。

### 意外与失败

- 初版夹具编译失败，真实错误为 `Required named parameter 'duration' must be provided` 与重复 `_` 参数声明；补齐媒体元数据和参数名。
- 夹具的 `DecoderManager` 初始化曾报 `UnimplementedError: setDecoders`；补上测试 delegate 的解码器/属性接口。
- 非原生截图需要等待异步文件检查后进入重绘阶段；初版只 pump 一次未完成截图，终止该次运行，改为在有界时间内持续驱动帧。
- 初版像素断言把 Material 色板误当纯色，真实输出为 `Expected: <255> / Actual: <244>` 与 `Expected: <0> / Actual: <33>`。改用明确的纯红/纯蓝颜色值，保持严格像素断言；最终四项实验全部通过。

## 4. 问题

需要主控决定的问题：没有。
