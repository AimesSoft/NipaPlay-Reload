# PR #1043 差异范围核查（2026-10-28）

这是针对异常差异规模和部分文件的只读抽查，不是逐文件安全审计或清理提案。统计以本地 `origin/main=7e4e80428ab11509779be635d2c394b6405542e3`、`origin/next=82e7c3d1739f5744dfbfeb983e31b362aa75c4e0` 为准；这是本文等文档提交前的快照。工作区未提交内容不计入 Git 比较，后续提交或分支更新后数字会变化。

## 比较基线

`git merge-base origin/main origin/next` 为 `2b37af04de470346959f50903e842520fa56c9eb`，2025-03-19 的 `0.0.1` 初始提交；仓库不是浅克隆。两边自共同祖先分别有 3122 和 3782 个各自可达的提交。因此 GitHub PR 的三点比较包含大量两个分支各自积累的历史，不等于 Next 最近新写了 150 万行。

| 比较方式 | 文件 | 新增行 | 删除行 |
| --- | ---: | ---: | ---: |
| GitHub PR 显示的三点差异 | — | 1,518,777 | 2,393 |
| 本地 `git diff origin/main...origin/next` | 6,110 | 1,518,712 | 2,364 |
| 本地 `git diff origin/main origin/next`（两个 tip） | 1,497 | 322,837 | 10,234 |

GitHub 与本地三点数字略有差异；比较方式和工具设置可能影响统计，未逐项核实差异原因。双点比较表示两个当前树的不同，不是 PR 的实际合并结果，也不排除正常代码以外的内容。其新增行主要分布如下：

| 路径 | 新增行 |
| --- | ---: |
| `lib/next` | 162,175 |
| `test/next` | 72,374 |
| `docs/next` | 29,707 |
| `rust` | 11,545 |
| `server` | 10,626 |
| `scripts/next` | 8,544 |
| `packages/nipa_harness` | 5,159 |

## 抽查结果

- `lib/next/ui/dev/fake_world.dart` 和 `fake_calls.dart` 是界面截图、实验和测试的模拟数据与操作；前者用 Dart `part` 包含后者。`ui/data/services.dart` 在 `kDebugMode` 下尝试开发服务；`NextUiDev` 通常要求 Debug 与 LabProfile，iOS 模拟器另有 Debug 临时文件入口。源码由应用引用，不能仅凭名字声称没有编译进入产物；已核对的选择路径有 Debug 门控，未对各平台 release 二进制做符号或运行验证。
- `assets/next/agent/dsh-runtime.json` 双点新增 2,096 行，是 DSH/Node 版本、下载地址、大小与 SHA-256 的运行时清单。`scripts/next/dsh_runtime/build_lock.py` 从 npm 安装及平台加载 trace 生成它。`pubspec.yaml` 将清单列为 Flutter 资源；headless 打包脚本也复制 `assets/next/agent`。清单进入资源不等于把列出的全部依赖包直接打进安装包；实际安装和完整性仍由运行时处理。
- `scripts/next` 包含 X 系列实验、Windows lab 工具、DSH trace 与发布/打包脚本。trace 用于识别运行时实际加载的模块以构建清单；不能把整个目录简单归为垃圾。抽查发现手动构建工作流引用发布清单脚本，headless 打包引用自己的脚本；没有逐一核查其他脚本被 CI 或人工流程使用的情况，也没有证明它们都进入发行包。
- `test/next` 有 fake driver、fake qBittorrent 和媒体 JSON fixtures，服务于测试和可复现实验。名称显示用途，不能据此证明每个 fixture 的来源、许可或隐私状态均已审计。测试源码不是 `pubspec.yaml` 所列上述 Flutter 资源；未逐平台检查最终归档每个文件。
- 按扩展名抽查双点差异，未见新增的 `.log`、`.tmp`、`.sqlite`、`.db`、`.pem`、`.key`、`.env`、`__pycache__`、`node_modules` 或构建/覆盖率目录；匹配到的四个 `docs/webdav/evidence/*.log` 在双点比较中是**删除**，不是 Next 新增。依赖 lock 文件属于匹配结果，应按依赖审查而不是当临时文件。扩展名搜索不能发现改名的秘密、嵌入源码/JSON 的凭据或其他私人数据，因此不能断言不存在泄漏。
- 当前工作区有未跟踪 `scripts/next/__pycache__/` 和其他用户工作；它们不属于以上已提交树比较。本次未读取私人数据库、输出秘密、删除文件或改写分支历史。

## 合并与待核实

PR 合并前需单独处理比较基线与合并策略，并逐项核对 main 后续修复在 Next 中是否缺失、冲突或需要移植。当前 `origin/main` 有 Next 不可达的后续提交，包括离线弹幕缓存、桌面对话框、Emby 季和手动匹配扫描状态修复；这里只确认提交历史，未判断各修复在 Next 树中是否已通过其他提交等价实现。双点差异中 main 独有内容也不能直接解释为可安全删除。

从 `next` 构建 Developer Preview 与合并 PR 是不同操作：当前从 Next 出包不以先合并 main 为前提。发行前仍应按实际提交、目标平台和包内容核验。

尚需单独审查：可疑大文件与生成物的来源和必要性；实验脚本、fixtures 和历史证据中的隐私、凭据与许可；各平台 release 实际资源与 Debug 门控；main 后续修复及合并冲突；完整 CI 与实机验证。本报告的抽查不证明所有文件安全、必要或已覆盖。
