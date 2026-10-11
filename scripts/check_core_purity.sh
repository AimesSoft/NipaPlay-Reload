#!/usr/bin/env bash
# check_core_purity.sh — nipaplay_core 红线静态检查
# 用法: bash scripts/check_core_purity.sh   (在仓库根目录执行)
# 退出码 0 = 通过; 1 = 违规 (列出文件与行)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/packages/nipaplay_core"
fail=0

if [ ! -d "$CORE/lib" ]; then
  echo "[FAIL] 未找到 $CORE/lib"
  exit 1
fi

# 1) pubspec 禁止 UI 依赖
for dep in flutter_material flutter_localizations fluent_ui macos_ui cupertino_icons adaptive_platform_ui liquid_glass_widgets; do
  if grep -qE "^\s*$dep\s*:" "$CORE/pubspec.yaml"; then
    echo "[FAIL] pubspec 含 UI 依赖: $dep"
    fail=1
  fi
done

# 2) 源码禁止 import UI 包 (material/cupertino/widgets/rendering/painting/animation 与 UI 第三方)
#    白名单: flutter/foundation, flutter/services (非 UI 运行时)
pattern='package:flutter/(material|cupertino|widgets|rendering|painting|animation)\.dart'
violations=$(grep -rnE "$pattern" "$CORE/lib" 2>/dev/null)
if [ -n "$violations" ]; then
  echo "[FAIL] core 源码出现 UI import:"
  echo "$violations"
  fail=1
fi

ui_pkgs='package:(fluent_ui|macos_ui|adaptive_platform_ui|liquid_glass_widgets|cached_network_image|flutter_svg|qr_flutter|mobile_scanner)/'
violations=$(grep -rnE "$ui_pkgs" "$CORE/lib" 2>/dev/null)
if [ -n "$violations" ]; then
  echo "[FAIL] core 源码出现 UI 第三方包 import:"
  echo "$violations"
  fail=1
fi

# 3) dart:ui 仅允许几何/颜色值类型 (Rect/Size/Offset/Color/TextAlign 等值类), 禁渲染类
render_symbols='(Canvas|TextPainter|PictureRecorder|RenderBox|Window|SingletonFlutterWindow|ParagraphBuilder)'
grep -rl "dart:ui" "$CORE/lib" 2>/dev/null | while IFS= read -r f; do
  if grep -qE "$render_symbols" "$f"; then
    echo "[FAIL] $f 使用 dart:ui 渲染类符号"
    fail=1
  fi
done

# 4) 禁止 Widget/BuildContext/State 类型出现在 core
widget_symbols=$(grep -rnE "(Widget|BuildContext|StatefulWidget|StatelessWidget)\b" "$CORE/lib" 2>/dev/null | grep -v "^\s*//" | grep -vE ":\s*//")
if [ -n "$widget_symbols" ]; then
  echo "[FAIL] core 源码出现 Widget 层类型:"
  echo "$widget_symbols"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[OK] nipaplay_core 纯净度检查通过 ($(find "$CORE/lib" -name '*.dart' | wc -l) 个 dart 文件)"
fi
exit $fail
