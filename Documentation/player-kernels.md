# 播放器内核

NipaPlay 通过 `lib/player_abstraction/` 统一播放器接口，再由工厂根据平台和用户设置创建具体实现。当前内核是 Erika、MDK/FVP、Media Kit（libmpv）和 Video Player。Media Kit 是 Flutter 接入层，实际播放后端是 libmpv；文档中的“Media Kit”和“Libmpv”指同一个内核选项，不应作为两套内核比较。

## 选择建议

| 内核 | 适合场景 | 优点 | 注意事项 |
|---|---|---|---|
| Erika | 除 Linux 外的所有当前原生客户端平台；tvOS 唯一可用内核 | 自研 Rust 内核、原生 surface、硬件路径、ArtCNN、GPU 弹幕 | Linux 尚未支持；HDR 和硬解细节仍受设备、显示器和驱动影响 |
| Media Kit（libmpv） | 兼容性优先、复杂格式、桌面长期使用 | Flutter 接入 Media Kit、实际后端为 libmpv；格式覆盖广，Windows Release 通常带完整 libmpv | 自建包要确认 `libmpv-2.dll` 或对应动态库完整 |
| MDK/FVP | 需要跨平台硬解或已有 MDK 兼容行为 | 依赖成熟、回退路径清晰 | 不同系统驱动差异可能影响硬解 |
| Video Player | 最小依赖、基础播放和回归对比 | Flutter 官方 API，便于诊断 | 能力较基础，不适合作为复杂媒体的唯一内核 |

## 排障顺序

1. 记录平台、版本、媒体 URL/容器、视频编码、音频编码、字幕格式和是否 HDR。
2. 使用当前默认内核复现，再切换到 Media Kit（libmpv）或 MDK 做对照；tvOS 不能切换离开 Erika。
3. 如果只有 Erika 失败，保留 Erika 诊断信息、surface 类型、渲染器和回退原因。
4. 如果所有内核都失败，优先检查 URL、权限、网络、容器索引和媒体文件本身。
5. 报告问题时附上最小复现文件或脱敏后的媒体信息，不要公开带凭据的 URL。

## 开发者注意事项

- 新内核必须实现 `AbstractPlayer` 的完整生命周期：创建、打开、播放、暂停、seek、轨道切换、事件、渲染资源和释放。
- 平台专属 surface 不应泄漏到共享 UI；通过适配器或条件导入隔离原生依赖。
- 任何“实验室”内核都要在设置页、平台矩阵和 Release Notes 中说明回退行为。
- Erika 的 NipaPlay 集成版本由 `pubspec.yaml` 和 lockfile 固定；跨仓库开发请阅读 [Erika 跨仓库开发](../CONTRIBUTING_GUIDE/13-Erika-Cross-Repository-Development.md)。
