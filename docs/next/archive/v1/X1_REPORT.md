# X1 报告：知情同意、Agent 权限与弹幕交入

日期：2026-10-11。分支：`next/capability-layer`，主仓库目录。

实现已完成；两组测试通过。指定的全量静态分析尚未通过：有五项实验室之外的 Classic 遗留诊断，需要主控决定是否扩展修复范围。

## 1. 完成了什么

- 实验室开关改名为「NipaPlay Next」。每次从关闭到开启都展示简体、繁体或英文的警示：正文红色，取消按钮默认获得焦点，关闭窗口也视为取消；只有明确确认才保存开启状态。
- 每次端点重新开启生成新的 32 字节随机令牌，旧令牌不能访问新端点；重写工作区说明与配置。运行中重复 start 不轮换。端点更新队列保留开关切换时的值，避免快速关闭再开启被合并。
- 工作区配置提供完整执行权限、无需逐条批准及实时搜索。按 Action 的 Effect 自动保留破坏性 MCP 工具的 `approval_mode = "prompt"`。配置先写入空临时文件并设置私有权限，再写令牌并替换旧文件；Unix 为 0600，Windows 使用仅当前用户的 ACL。
- 新增写能力 `danmaku.import`：从本地 B 站标准 XML 或规范化 JSON 文件交入弹幕，绑定到 File、Episode 或当前播放文件。无需注册平台适配器或取得 NipaPlay 内置会话。
- 宿主记录平台、视频 ID、actor、调用 origin、UTC 时间、文件路径和可选说明。相同平台/视频再次交入替换旧池，保留启用、偏移、折叠设置；解析或数据库提交失败不改变旧绑定、缓存指针和播放器轨道。
- 交入结果接入现有即时挂载和播放恢复机制；来源出现在 `danmaku.tracks`、`state.query` 的 `danmaku.bindings` / `danmaku.tracks` 视图中。数据库追加 v7 来源字段迁移。
- 弹幕来源和会话的登录提示改为平台与当前状态，不再包含设置导航；内置 WebView、会话存储、注销和请求流程保持原有机制。
- 添加可复现的本机 Codex 探测脚本：`scripts/next/verify_codex_workspace.py`。

没有 commit、push、pub get、新依赖或构建配置修改。Classic 代码仅改了实验室开关。未操作原有 `macos/Podfile.lock` 修改；执行期间出现的外部 `docs/next/TEAM.md` 修改也未覆盖。

## 2. 决策

1. **整集数据使用本地文件交入。** Action 参数只含路径、来源、目标和说明；文件内容在 isolate 中解析，不通过 MCP 参数传输几 MB JSON。不新增平台白名单、权限层、网络路线或兼容接口。
2. **格式与身份分开。** XML 使用 B 站标准容器与 p 属性，不据 XML 格式推断来源；平台及视频 ID 来自调用参数。JSON 为数组或 `{"comments":[...]}`，必填 `sourceTimeMs`、`text`、`mode`、`colorRgb`。可选 ID、发送者、字体和发送时间字段见弹幕 README。逐条验证后一次提交；允许明确的空池刷新。
3. **刷新是缓存、绑定、来源和审计事件的一次事务。** 不先清空旧轨道。沿用既有显示设置和视频元数据；File/Episode 重叠轨道恢复时选择最新交入结果。播放恢复串行执行；抓取提交检查缓存修订，防止交入前已启动的抓取覆盖新池。后来明确发起的宿主抓取仍可刷新，并清除当前池的旧交入来源标记，历史来源留在事件中。
4. **只验证数据约束。** 新测试覆盖 50000 条文件、同平台视频唯一性、刷新设置保留、错误文件整池拒绝、事务回滚、来源、恢复和迟到抓取冲突。播放器采用离线端口，来源采用合成夹具；没有把测试通过写作真实优酷获取成功。
5. **Codex 权限使用实测生效的项目配置：**

   ```toml
   sandbox_mode = "danger-full-access"
   approval_policy = "never"
   web_search = "live"
   ```

   完整权限本身允许联网，无需添加仅作用于 workspace-write 的网络配置。Codex 需要先信任项目才加载项目配置，保留现有工作区信任提示；应用不改用户的全局 Codex 配置。
6. **知情同意保留为 GUI 入口。** 沿用现有实验室设置及 Agent 端点的宿主启停方式；不开设让 Agent 代替用户确认警示的 Action。本批新增弹幕能力已提供对应 Action 与 schema。

## 3. 实验与验收命令、真实输出

### 本机 Codex 项目配置

版本和复现命令：

```sh
codex --version
python3 -u scripts/next/verify_codex_workspace.py
```

脚本直接调用生产 `writeAgentWorkspace`，生成临时工作区。使用独立临时 CODEX_HOME，只设置项目信任和本地合成模型服务；执行权限来自项目配置，没有通过 CLI 或 thread/start 参数覆盖权限。真实 Codex app-server 使用 `--strict-config`，通过 `config/read` 核对值及 project 来源；通过 `thread/start` 核对线程权限，再用本地合成模型响应触发真实线程的 exec_command，写入、读取并删除工作区外的临时文件，并请求本地 HTTP 服务。

真实输出（退出码 0）：

```text
codex-cli 0.144.1
config file mode: 600
sandbox_mode: "danger-full-access" (origin: project)
approval_policy: "never" (origin: project)
web_search: "live" (origin: project)
destructive tools: {"danmaku_cache_delete": {"approval_mode": "prompt"}, "download_delete": {"approval_mode": "prompt"}, "mesh_invoke_destructive": {"approval_mode": "prompt"}}
thread: {"approvalPolicy": "never", "sandbox": {"type": "dangerFullAccess"}}
live web_search tool: present
command execution: {"exitCode": 0, "aggregatedOutput": "outside workspace\nnetwork available\n", "status": "completed"}
turn status: completed; approval requests: 0
```

意外与修正：最初用独立 `command/exec` 做探测，写工作区外文件得到 `PermissionError: [Errno 1] Operation not permitted`。该调用默认使用服务级配置，不能代表指定项目线程。改为在指定 cwd 的线程中执行后，项目配置、实际文件操作、网络请求均通过，审批请求数为 0。验证未请求线上模型、网站或真实浏览器登录数据，也未执行真实破坏性 MCP 操作。

### Harness

```sh
cd packages/nipa_harness
~/development/flutter-3.44.6/bin/dart test
```

真实输出尾部（退出码 0）：

```text
00:00 +85: test/mcp_test.dart: serve allocates a loopback port and serves initialize and tools/call over HTTP
00:00 +86: test/mcp_test.dart: serve allocates a loopback port and serves initialize and tools/call over HTTP
00:00 +87: All tests passed!
```

### Next 测试

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub test/next
```

真实输出尾部（退出码 0）：

```text
00:25 +354: ~/Desktop/NipaPlay-Reload/test/next/mesh_integration_test.dart: an untrusted issuer is rejected by real mutual TLS
Shell: mesh connection rejected: invalid peer certificate: BadSignature
00:25 +355: ~/Desktop/NipaPlay-Reload/test/next/mesh_integration_test.dart: (tearDownAll)
00:25 +355: All tests passed!
```

共 355 项通过。测试没有访问线上服务；TLS/MCP 测试使用回环服务，平台请求使用 MockClient。新增弹幕夹具中的 JSON 超过 4 MB，50000 条数据交入和恢复均保留；坏条目及触发器模拟的提交失败保持旧池不变。初版实验中，假播放器无法覆盖 Classic 的 extension 方法；随后改用明确的 DanmakuPlayerPort 离线端口。另一次夹具失败来自 macOS /var 与 /private/var 的路径差异，夹具改用索引器返回位置对应的实际路径。上述初版失败未列作最终验收通过。

### 指定全量静态分析

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/next test/next lib/settings
```

真实输出（退出码 1）：

```text
Waiting for another flutter command to release the startup lock...
Analyzing 3 items...                                            

   info • 'onReorder' is deprecated and shouldn't be used. Use the onReorderItem callback instead. The onReorderItem callback adjusts the newIndex parameter for a removed item at the oldIndex. This feature was deprecated after v3.41.0-0.0.pre. Try replacing the use of the deprecated member with the replacement • lib/settings/adaptive_settings_widgets.dart:988:11 • deprecated_member_use
   info • Unnecessary braces in a string interpolation. Try removing the braces • lib/settings/pages/danmaku_settings_content.dart:1309:29 • unnecessary_brace_in_string_interps
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/settings/pages/plugin_settings_content.dart:60:18 • prefer_const_constructors
warning • This default clause is covered by the previous cases. Try removing the default clause, or restructuring the preceding patterns • lib/settings/pages/remote_media_library_settings_content.dart:1563:7 • unreachable_switch_default
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/settings/pages/storage_settings_content.dart:44:14 • prefer_const_constructors

5 issues found. (ran in 2.9s)
```

五个诊断所在文件均未修改。没有添加 lint 忽略、改分析配置或放宽验收参数来掩盖它们。

补充验证本批代码范围：

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/next test/next lib/settings/pages/labs_settings_content.dart
```

真实输出（退出码 0）：

```text
Analyzing 3 items...
No issues found! (ran in 2.5s)
```

`git diff --check` 退出码 0，无输出。尚未进行真实账号弹幕获取或完整 GUI 播放实验，主控可用生成的工作区和 `danmaku.import` 在真机观察。

## 4. 问题：需要主控决定的事项

**是否允许修复实验室之外五个 Classic 设置文件的原有静态分析诊断？** 当前「Classic 代码只限实验室开关这一处」的约束与「指定全量 analyze 全部通过」在现有基线上无法同时满足。已完成范围内的实现、测试及 Codex 实测；没有越界改这五个文件。

除此之外，没有需要主控决定的问题。

