---
name: nipaplay-build-release
description: Use when building/pushing the sideload IPA, dispatching GitHub Actions workflows, verifying CI results, or bumping the release version. Documents the manual-dispatch-only pipeline, the credential/dispatch/poll pattern via git credential fill, and the local analyze/test loop with its known lint-noise baseline.
---

# NipaPlay 构建与发布链路（个人 fork，无 PR）

定位：origin = `TsangAsuna/features`（nipaplay 分支），上游 =
`AimesSoft/NipaPlay-Reload`。**流程是"拉上游 → 构建 IPA 自用"，不向上游提
PR**。所有构建工作流都是 `workflow_dispatch` 手动触发，**tag 不触发任何
workflow**（`grep -l "tags:" .github/workflows/*.yml` 为空）。

## IPA 构建（标准路径）

- 工作流：`Build iOS sideload (unsigned)`（`.github/workflows/build-ios-sideload.yml`，
  复用 build-ios.yml，`upload-to-app-store: false`）。产物 `release-iOS`
  （未签名 sideload IPA，~80MB）+ `dart-symbols-iOS`。耗时 13-18 分钟。
- `main.yml`（Build & Release Modular）需要 `release_title`（YYYY.MMDD 格式
  Gatekeeper 校验）且会构建全平台——日常 IPA 不要用它。
- App Store Connect 上传在本仓库已禁用（build-ios 的 with 注释）。

## dispatch / 轮询模式（gh CLI 未安装，用 git 凭据 + REST）

```bash
TOKEN=$(printf "protocol=https\nhost=github.com\n" | git credential fill 2>/dev/null | grep "^password=" | cut -d= -f2)
# 派发（204=成功受理）
curl -sk -X POST -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/TsangAsuna/features/actions/workflows/build-ios-sideload.yml/dispatches" \
  -d '{"ref":"nipaplay"}'
# 确认 run 起来了（head_sha 必须与提交全量 SHA 匹配，别用短 SHA 拼接）
curl -sk -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/TsangAsuna/features/actions/workflows/build-ios-sideload.yml/runs?per_page=3"
# 轮询到 completed，再列 artifacts
curl -sk -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/TsangAsuna/features/actions/runs/<run_id>/artifacts"
```

参考历史：1.11.11 合并 run `40240873026`（success，13min）；TMDB 镜像
`dffd4ec7` run `40207872546`（success，17min）。

## 版本号

- 唯一来源 `pubspec.yaml` 的 `version:`（驱动 iOS CFBundleShortVersionString）。
  2026-10-26 起 = **1.11.10**（用户裁定，与上游 tag 对齐叙事；上游 main 代码
  基线是 1.11.11——版本号与代码基线不必严格一致，这是有意选择）。
- `apps/nipaplay_tv/pubspec.yaml`（1.0.0+1）独立版本，不要联动。
- 改版本号必须重跑 IPA 构建才进产物；构建中途改无效。

## 本地验证环（构建前的必做项）

- Flutter 全路径（不在 PATH）：`"F:/Hermes Agent CN Desktop
  Portable/data/hermes-home/workspace/flutter/bin/flutter.bat"`。
- `flutter analyze lib test` 基线：**0 error**；~1900 条 info/warning 是既有
  风格 lint（avoid_print/use_build_context_synchronously 等），合并前就存在，
  不阻塞。vendored 包（adaptive_platform_ui/example、file_selector_ohos、
  desktop_multi_window_linux_347）的 error 永远存在，忽略。
- 冒烟测试选合并敏感区各 1-2 个契约文件（webdav_connection_rebind /
  media_server_image_loader / bangumi_lazy_cache），全绿再推。
- analyze 的 exit code 陷阱：`grep -cE "error -"` 无匹配时 grep 退出码 1，
  会让 `&&` 链假死——用 `; echo done` 或单独跑。

## 工作区卫生

工作区常驻未提交杂项（`generated_plugin*` 三个平台文件、`tools/` 旧性能
脚本删除、`_collapse_fix.py`/`_probe.py`/`.zcodeignore`）——**不属于任何
功能提交**，提交前用白名单 `git add <paths>` 而非 `git add -A`；合并提交前
先 `git stash push -m "pre-merge leftovers"`，提交后 pop 回来。

相关：[[upstream-111-merge-2026-10]]、[[tmdb-image-proxy-fix-2026-10]]
