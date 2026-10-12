# 技能：`.git` 目录被外部删除后的恢复

## 背景
2026-10-12 19:50，仓库 `NipaPlay-Reload-features` 的 `.git` 目录（565MB，含阶段一~四全部重构历史）
被某个外部进程删除，`git status` 报 `not a git repository`。工作区文件完好，但历史不可见。

## 定位
1. 先排除自己：确认没有执行过 `rm .git`（本项目约束只允许 `git mv/add/commit`）。
2. 全盘搜同类目录：`find /d /c/Users/... -maxdepth 3 -name .git -newermt <日期>`。
3. **查回收站**：`find "/f/\$RECYCLE.BIN" -maxdepth 2 -iname "*git*"` →
   找到 `$I545FBA.git`（元数据）+ `$R545FBA.git`（565MB 实体）。

## 恢复
```bash
RB='/f/$RECYCLE.BIN/S-1-5-21-.../1001'
DEST='/f/.../NipaPlay-Reload-features/.git'
mkdir -p "$DEST" && cp -r "$RB/$R545FBA.git"/. "$DEST/"
cd <repo> && git branch --show-current && git log --oneline -5
# 验证：分支 nipaplay、提交链 be8b2c53→...→11c2786b 全部完整
```
**不要**用 shell 的 `rm` 清理回收站原文件——保留原件直到验证通过。

## 验证
`git status` 能列出修改文件、`git log` 能显示完整提交链、`git fsck` 无 fatal。

## 适用场景
Windows 下任何 git 仓库历史丢失（误删/清理工具/杀软隔离）；
**预防**：重要里程碑 `git push origin nipaplay`（本地曾领先 origin 多个提交未推送，
若回收站也被清空则无法挽回）。
