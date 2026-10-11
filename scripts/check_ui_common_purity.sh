#!/usr/bin/env bash
# check_ui_common_purity.sh — nipaplay_ui_common 红线静态检查
# 用法: bash scripts/check_ui_common_purity.sh   (在仓库根目录执行)
# 规则: 禁止依赖 app 本体 (package:nipaplay/...) 及其 app 态模块;
#       允许 flutter / package:nipaplay_core / 第三方。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/packages/nipaplay_ui_common"
fail=0

if [ ! -d "$PKG/lib" ]; then
  echo "[FAIL] 未找到 $PKG/lib"
  exit 1
fi

# 1) 禁止 import app 本体任何内容 (只匹配真正的 import/export/part 指令行)
violations=$(grep -rnE "^(import|export|part)\s.*package:nipaplay/" "$PKG/lib" 2>/dev/null)
if [ -n "$violations" ]; then
  echo "[FAIL] ui_common 出现 app 本体 import (package:nipaplay/):"
  echo "$violations"
  fail=1
fi

# 2) 禁止 app 态/平台窗口插件
app_plugins='package:(window_manager|tray_manager|desktop_multi_window|provider|flutter_rust_bridge)/'
violations=$(grep -rnE "^(import|export|part)\s.*$app_plugins" "$PKG/lib" 2>/dev/null)
if [ -n "$violations" ]; then
  echo "[FAIL] ui_common 出现 app 态/窗口插件 import:"
  echo "$violations"
  fail=1
fi

# 3) pubspec 禁止 app 本体 path 依赖
if grep -qE "^\s+nipaplay:\s*$|path: \.\./\.\.$" "$PKG/pubspec.yaml"; then
  echo "[FAIL] pubspec 不应依赖 app 本体"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[OK] nipaplay_ui_common 纯净度检查通过 ($(find "$PKG/lib" -name '*.dart' | wc -l) 个 dart 文件)"
fi
exit $fail
