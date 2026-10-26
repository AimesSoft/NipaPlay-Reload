# NipaPlay 技能树

`skills/` 下每个目录是一个可独立复用的主题包（SKILL.md，带 frontmatter 的
触发条件与不变量）。改代码前先按"Use when"匹配；修完事故后按同样的格式
把新不变量写回对应包。提交惯例：`docs(skills): <主题>`。

```
skills/
├── SKILL_TREE.md                     ← 本文件：总索引
├── nipaplay-upstream-merge/          ← 合并上游 / 解冲突 / 包路径重指向
├── nipaplay-build-release/           ← IPA 构建、dispatch/轮询、版本号、工作区卫生
├── nipaplay-image-mirror/            ← 封面裂图 / 镜像优先 / 受限网络实测
├── nipaplay-bangumi-cache/           ← 番剧详情缓存契约（上游 #1004）
├── nipaplay-player-kernel/           ← 内核热切换 / teardown 架构 / 停滞恢复
├── nipaplay-media-research/          ← 弹幕来源与匹配 / 音频能力矩阵
├── nipaplay-performance/             ← 启动延后 / 图片预算 / 局部重建惯例
└── nipaplay-theme-ui/                ← 主题/UI 层约定
```

## 按场景找技能

| 场景 | 先看 |
|---|---|
| 要合并上游 / 合并后编译失败 | nipaplay-upstream-merge |
| 要出 IPA / 改版本号 / 派发 CI | nipaplay-build-release |
| 封面不加载 / 配镜像 / 受限网络 | nipaplay-image-mirror |
| 改简介加载 / 缓存行为 / 重启重取 | nipaplay-bangumi-cache |
| 切内核卡死 / 字幕轨停滞 / 适配器 | nipaplay-player-kernel |
| 没弹幕 / 弹幕错配 / DDP·MKA 音频问题 | nipaplay-media-research |
| 启动慢 / 掉帧 / 内存 | nipaplay-performance |
| 改主题 / UI 组件 | nipaplay-theme-ui |

## 维护规则

- 不变量必须对应真实事故或契约测试，不写"应该/建议"。
- 实现被上游取代时**改写为当前事实**并在文首保留裁定记录（哪个提交、
  为什么），过时内容不保留正文（git 历史即归档）。
- 仓库外还有一份同主题的记忆索引（会话记忆 MEMORY.md），两边以本目录为
  准：本目录随仓库走、可提交共享；记忆目录只服务单机会话。
