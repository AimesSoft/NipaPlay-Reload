# 13. Erika 跨仓库开发

NipaPlay 和 [Erika](https://github.com/AimesSoft/Erika) 是两个独立仓库。修改 Erika 后，NipaPlay 不会自动使用本地最新代码；集成版本由 `pubspec.yaml`、lockfile、平台 workflow 和预构建 tag 共同决定。

## 版本边界

开始工作前记录：

- NipaPlay 当前 Erika commit pin；
- Erika 本地分支和 HEAD；
- `ERIKA_PREBUILT_TAG`（如果使用预构建包）；
- 目标平台、架构和渲染路径。

本地 Erika HEAD 领先于 NipaPlay pin 时，只能称为“本地验证”，不能称为“NipaPlay 已集成”。

## 推荐工作流

1. 在 Erika 仓库完成最小修改，并运行 `cargo fmt --all -- --check`。
2. 运行受影响 crate 的测试；若改动 C ABI、渲染器、FFmpeg 或平台 glue，再运行对应示例/目标构建。
3. 更新 Erika 文档、CHANGELOG 和必要的 C header/API 说明。
4. 在 NipaPlay 中使用明确的本地 override 或预构建 tag 做集成验证；不要把临时 override 提交到主分支。
5. 记录 NipaPlay 侧的播放、字幕、弹幕、HDR、resize、后台音频和 dispose 结果。
6. 发布时同步 commit pin、预构建 tag、平台产物和 Release Notes。

## 常见陷阱

- Erika C header 已变更，但 Dart FFI 或文档仍使用旧字段/函数。
- 示例代码仍引用已删除的 uniform 字段，导致 `cargo test --workspace` 失败。
- 本地使用源码构建，CI/用户使用旧预构建包，造成“本地正常、发布异常”。
- tvOS/OHOS 的平台 surface 能编译，但没有真机验收；报告中必须标明这一点。
