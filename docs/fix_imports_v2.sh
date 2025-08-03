#!/bin/bash

# --- Step 1: Broadly replace all widget import paths ---
# This will move all imports, including the ones we want to keep in the parent 'widgets' directory.
echo "Step 1: Replacing all 'widgets/' paths with 'widgets/nipaplay_theme/'..."
find lib -name "*.dart" -print0 | while IFS= read -r -d $'\0' file; do
  # Handle 'package:nipaplay/widgets/...'
  sed -i '' "s|'package:nipaplay/widgets/|'package:nipaplay/widgets/nipaplay_theme/|g" "$file"
  # Handle 'package:nipaplay/widgets/...'
  sed -i '' "s|'package:nipaplay/widgets/|'package:nipaplay/widgets/nipaplay_theme/|g" "$file"
  # Handle 'widgets/...'
  sed -i '' "s|'widgets/|'widgets/nipaplay_theme/|g" "$file"
done
echo "Step 1 finished."
echo ""

# --- Step 2: Revert the paths for the specific danmaku widgets ---
# Now, we correct the paths for the few widgets that should NOT have been moved.
echo "Step 2: Correcting paths for danmaku widgets..."
DANMAKU_WIDGETS=(
  "danmaku_container.dart"
  "danmaku_group_widget.dart"
  "danmaku_overlay.dart"
  "single_danmaku.dart"
)

find lib -name "*.dart" -print0 | while IFS= read -r -d $'\0' file; do
  for widget in "${DANMAKU_WIDGETS[@]}"; do
    # Revert package imports
    sed -i '' "s|'package:nipaplay/widgets/nipaplay_theme/${widget}|'package:nipaplay/widgets/${widget}|g" "$file"
    # Revert relative imports
    sed -i '' "s|'package:nipaplay/widgets/nipaplay_theme/${widget}|'package:nipaplay/widgets/${widget}|g" "$file"
    # Revert relative imports
    sed -i '' "s|'widgets/nipaplay_theme/${widget}|'widgets/${widget}|g" "$file"
  done
done
echo "Step 2 finished."
echo ""
echo "所有 import 路径已修复完毕。"
