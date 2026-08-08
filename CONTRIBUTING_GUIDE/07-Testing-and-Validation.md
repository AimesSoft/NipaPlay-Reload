# 7. 测试与验证

提交 PR 前，先根据改动范围选择分层验证，不要把第三方源码和生成目录的诊断结果当作主应用质量指标。

## 常用命令

```bash
# 只检查主应用和测试目录
flutter analyze lib test

# 检查格式（不写回文件）
dart format --output=none --set-exit-if-changed lib test packages/danmaku_canvas/lib

# 运行单元测试/组件测试
flutter test test/path/to/changed_test.dart
flutter test
```

平台依赖切换后先运行 `flutter clean` 和对应的依赖配置脚本。不要在没有确认目标平台的情况下直接执行会重生成原生插件注册文件的命令。

## 改动类型与最低验证

| 改动 | 最低验证 |
|---|---|
| 纯 Dart helper、模型、解析器 | 对应测试 + `flutter analyze lib test` |
| Provider、Service、设置页 | 对应测试 + 至少一个真实平台启动 smoke test |
| 播放器/弹幕 | 本地文件、网络文件、字幕/弹幕各一条；记录内核和渲染器 |
| 原生插件或 FFI | 目标平台构建 + 生命周期（创建、resize、dispose）验证 |
| Erika 依赖或 API | Erika 仓库的 fmt/test/clippy + NipaPlay 对应平台 smoke test |
| 文档、脚本、CI | Markdown 链接检查 + 脚本 dry-run；不应生成无关 lockfile 或注册文件 |

## 测试报告要求

报告中写明平台、系统版本、Flutter/Dart 版本、设备型号、NipaPlay commit、Erika commit 或 prebuilt tag。若测试没有完成，应明确写“未完成/卡住”，不要写成“失败断言”。

## 已知测试边界

某些窗口和媒体插件测试需要真实平台 runner。纯函数测试不应依赖平台插件初始化；如果单个测试在 loading 阶段卡住，请先单独运行该文件，再检查插件注册、测试隔离和 runner 生命周期。
