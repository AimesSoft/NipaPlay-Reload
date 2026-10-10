# X7：交入弹幕复用 Classic 本地解析

日期：2026-10-11。工作分支：`next/capability-layer`。

## 1. 完成了什么

`danmaku.import` 读取文件字节后，复用 Classic 本地加载的
`parseLocalDanmakuBytes` → `parseDanmakuListInBackground` →
`parseDanmakuColorToInt` 路径，再转换为 Next 的缓存条目。
删除导入器自己的 XML 解析与 24 位颜色上限检查。优酷 XML 中的
`0xFFRRGGBB` 按 Classic 的方式取 RGB，不需要 Agent 清洗文件。

同时接入 Classic 已有的 JSON 数组、`comments`/`data` 包装、字符串化数组、
弹弹play `p`/`m` 格式，以及 BOM、UTF-16、旧字符编码处理。更新了 Action
描述和弹幕模块说明。时间、文本、显示模式、原模式、颜色、弹幕 ID、发送者、
字号及发送时间保留到 Next 条目；平台/视频身份仍使用调用参数。

真正的解析错误返回 `invalid_input` 和实际错误信息，解析失败不会提交缓存或
改写已有绑定、轨道。原有事务提交、刷新替换、设置保留、审计和播放恢复路径继续使用。

变更文件：

- `lib/next/danmaku/import.dart`：复用解析、格式转换与错误报告。
- `lib/utils/local_danmaku_file.dart`：增加默认关闭的显式空池选项。
- `lib/next/danmaku/capability.dart`、`lib/next/danmaku/README.md`：更新支持范围。
- `test/next/danmaku_import_test.dart`：合成数据完整性、编码兼容及失败保留检查。
- `test/next/danmaku_import_experiment.dart`：通过环境变量接收真实文件只读副本的实验入口。

没有 commit、push、新增依赖或运行 pub get。开始工作时已有的
`macos/Podfile.lock` 修改保持原样。没有退出、重启用户的 NipaPlay，也没有写入
用户的 `~/nipaplay-harness`。

## 2. 决策

1. **使用 Classic 的本地加载入口。** 不仅修补颜色上限，也移除重复 XML
   解析。默认值、条目筛选和颜色转换直接采用现有解析器，避免两个入口继续分化。
   Classic 本地加载本身使用 Dart 解析入口；这里没有另选 C++ XML 解析路径。
2. **保留既有规范化 JSON 契约。** `sourceTimeMs`、`text`、`mode`、`colorRgb`
   的 JSON 仍可交入；只在这类 Next 条目上检查契约所需的字段类型。
   颜色也复用 Classic 转换，不再因 alpha 位拒收。先按 Classic 标准化，只有无法
   生成 Classic 条目时才识别规范化 JSON，避免文件内其他元数据触发更严格的校验。
   缓存继续保存整数毫秒和 24 位 RGB。
3. **空刷新是导入入口已有的语义。** 共享解析器增加 `allowEmpty=false` 参数，
   仅交入入口显式开启。只接受明确空数组或没有 `<d>` 元素的 `<i/>`；
   损坏 XML、含有无法生成弹幕的 `<d>`、非空输入无法产生可解析条目时报告失败。
   Classic 调用保持默认值，仍拒绝空池，未改变 Classic 行为。
4. **先完成解析，再沿用原子提交。** 文件读取错误保留 `not_found`，
   格式错误与外部输入类型错误返回 `invalid_input`；不能转换成整数毫秒的非有限时间
   明确报告。错误不被转成成功的空刷新。
5. **实验独立于用户应用。** 使用真实 Harness Action、弹幕服务与临时 SQLite，
   播放端口为内存端口；Classic 对照调用 GUI 本地加载所用的两级解析函数。
   数据库重开验证仅作用于实验实例。没有访问应用正在使用的数据库或回环服务。

## 3. 实验

### 真实 XML：复现与修复

只读取用户指定的第 1 集 XML，将原始字节复制到系统临时目录，副本权限设为
`0400`。没有修改颜色、文本或其他字段；实验输入、真实源路径和弹幕内容均未放入
仓库夹具。源文件特征检查实际输出：

```text
bytes=1272683; XML comments=16203; ARGB comments=135; first ARGB index=3263; first ARGB=0xff02cc92; sha256=4e067efcf9b97902424a6ef70cfe22f82017169677fc488063afd10ab39b4111; mode=0o400
```

实验入口运行命令（副本路径由环境变量传入，无真实路径硬编码）：

```sh
NIPAPLAY_X7_XML_COPY=/absolute/path/to/read-only-copy.xml \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub --reporter expanded \
  test/next/danmaku_import_experiment.dart
```

修改实现前运行同一实验，真实输出：

```text
X7 Classic local parser: count=16203; sha256=4e067efcf9b97902424a6ef70cfe22f82017169677fc488063afd10ab39b4111
X7 danmaku.import: invalidInput; Invalid comment at index 3263.
00:00 +0 -1: Some tests failed.
```

完成修复后的真实输出：

```text
00:00 +0: X7 read-only XML import compared with Classic local loading
X7 Classic local parser: count=16203; sha256=4e067efcf9b97902424a6ef70cfe22f82017169677fc488063afd10ab39b4111
X7 danmaku.import: count=16203; loaded=true; cached=16203; all rows match Classic time/text/type/RGB/id/sender; restored=16203; input unchanged=true; network requests=0
X7 ARGB: input rows=135; all 135 RGB values preserved
X7 malformed XML: invalidInput; ">" expected; previous binding/cache/mounted pool unchanged=true
00:00 +1: All tests passed!
```

除了条数，还逐条比较原始缓存载荷与 Classic 解析结果的时间、文本、显示模式、
RGB、弹幕 ID、发送者、字号和发送时间。缓存读取、挂载和重开数据库后的恢复
均为 16203 条。135 条 ARGB 的 RGB 也全部一致。合成损坏 XML `<i><d` 返回
解析器的 `">" expected`，原绑定、缓存行和已挂载的完整池均未变化。

实验结束前再次只读计算原文件和副本的哈希，实际输出：

```text
X7 source unchanged=true; read-only copy unchanged=true; copy mode=0o400; sha256=4e067efcf9b97902424a6ef70cfe22f82017169677fc488063afd10ab39b4111
```

**实验中的意外与失败：** 第一次修复后逐条比较报 `Expected: <2140>, Actual: <2000>`。
原因是 Next 的缓存读取按时间排序，而源 XML 的顺序不同。实验改为对比数据库
中保持原顺序的缓存载荷，另检查读取、挂载与恢复条数；没有修改存储排序。

该实验验证真实文件经实际导入 Action 到临时数据库和播放端口的完整路径。
运行中的用户应用没有加载本次修改，也没有进行 GUI 或原生渲染内核的真机验收。

### 数据约束与 Classic 回归

仓库内仅有合成数据：140 条 XML 中 135 条为 ARGB，使用合成文本、发送者、视频 ID，
检查全部条目、原模式、字号与发送时间保留，并在删除输入后恢复轨道。
另外覆盖 UTF-8 BOM、UTF-16 两种字节序、GBK、Classic 两类字段格式、
字符串化 `data` 和 `p`/`m`；检查显式空刷新不改变 Classic 的默认空池行为。
损坏 XML、无有效弹幕、非有限时间、错误 JSON 字段类型及事务失败继续保留旧池。

检查命令与真实输出：

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub --reporter expanded \
  test/next test/danmaku_xml_utils_test.dart
```

```text
00:26 +334: All tests passed!
```

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
  lib/next lib/utils/local_danmaku_file.dart \
  test/next/danmaku_import_test.dart test/next/danmaku_import_experiment.dart
```

```text
No issues found! (ran in 1.8s)
```

最后调整为优先采用 Classic 可解析条目后，补充了“可加载弹幕与其他合成元数据
混在同一数组”的回归样本，并再次运行相关检查与真实副本实验：

```sh
NIPAPLAY_X7_XML_COPY=/absolute/path/to/read-only-copy.xml \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub --reporter expanded \
  test/next/danmaku_import_test.dart test/next/danmaku_import_experiment.dart \
  test/next/danmaku_unification_test.dart test/danmaku_xml_utils_test.dart
```

```text
00:01 +20: All tests passed!
```

首次 analyze 提示新增样本常量应使用 `const`，修正后上述检查通过。
Classic XML 转换测试在测试进程里打印 C++ 不可用并回退 Dart 的现有日志，两项均通过；
真实文件对照使用的本地加载路径本来就是 Dart。`git diff --check` 通过，无输出。
实验结束清理了本任务创建的临时副本和临时源路径记录。

## 4. 问题

需要主控决定的问题：没有。
