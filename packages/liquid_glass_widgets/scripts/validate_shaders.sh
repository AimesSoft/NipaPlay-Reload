#!/usr/bin/env bash
# validate_shaders.sh
#
# Validates liquid_glass_widgets GLSL shaders for Windows/SkSL compatibility
# using glslangValidator (the same compiler core used by Flutter on Windows).
#
# Usage:
#   bash scripts/validate_shaders.sh
#
# Install (once):
#   macOS:   brew install glslang
#   Ubuntu:  sudo apt-get install glslang-tools
#   Windows: choco install glslang
#            (or download from https://github.com/KhronosGroup/glslang/releases)
#
# What this catches:
#   - Dynamic array indices  ("index expression must be constant")
#   - Non-constant loop bounds
#   - Forbidden builtins (min(int,int), dFdx on scalar outside #ifdef, etc.)
#   - General GLSL syntax / type errors
#
# What this does NOT catch:
#   - Impeller-specific builtins (FlutterFragCoord, layout locations) — these
#     will warn but not error. They are valid at Impeller runtime.
#   - Semantic / visual bugs — only visual testing catches those.

set -euo pipefail

# ── Path resolution ───────────────────────────────────────────────────────────
# Works whether the script is called from the project root or the scripts/ dir,
# and on Windows (Git for Windows bash) where the path separator may differ.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHADER_DIR="$REPO_ROOT/shaders"

# ── glslangValidator resolution ───────────────────────────────────────────────
# On Windows the chocolatey package installs as "glslangValidator.exe".
# Prefer a direct path lookup; fall back to bare name for PATH-based installs.
if command -v glslangValidator &>/dev/null; then
  VALIDATOR="glslangValidator"
elif command -v glslangValidator.exe &>/dev/null; then
  VALIDATOR="glslangValidator.exe"
else
  echo "❌  glslangValidator not found."
  echo ""
  echo "    Install instructions:"
  echo "      macOS:   brew install glslang"
  echo "      Ubuntu:  sudo apt-get install glslang-tools"
  echo "      Windows: choco install glslang"
  echo "               (or: winget install KhronosGroup.glslang)"
  exit 1
fi

PASS=0
FAIL=0
WARN=0

VALIDATOR_VERSION=$("$VALIDATOR" --version 2>&1 | head -1 || echo "version unknown")
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Liquid Glass — Windows/SkSL Shader Validation"
echo "  Validator:  $VALIDATOR ($VALIDATOR_VERSION)"
echo "  Shader dir: $SHADER_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# We only validate .frag files (entry-point shaders).
# .glsl include files are pulled in by the including shader, so validating
# each .frag automatically validates all included .glsl files too.
for frag in "$SHADER_DIR"/*.frag; do
  name="$(basename "$frag")"

  # Run validator. Redirect stderr→stdout so we capture all output.
  # --target-env vulkan1.0  → SPIR-V target (same as Windows Flutter).
  # -S frag                 → treat as fragment shader stage.
  # -I "$SHADER_DIR"        → resolve #include relative to shader dir.
  output=$("$VALIDATOR" \
    --target-env vulkan1.0 \
    -S frag \
    -I "$SHADER_DIR" \
    "$frag" 2>&1) || true

  # ── Classify output lines ─────────────────────────────────────────────────
  has_error=false
  has_impeller_warn=false
  clean_output=""

  while IFS= read -r line; do
    # Impeller-specific extensions that glslang warns about but are valid at
    # Impeller runtime. These are intentional; suppress them from output.
    if [[ "$line" == *"FlutterFragCoord"* ]] ||
       [[ "$line" == *"GL_GOOGLE_include_directive"* ]] ||
       [[ "$line" == *"layout"*"location"* && "$line" == *"warning"* ]]; then
      has_impeller_warn=true
      continue
    fi

    # Real errors the Windows SkSL compiler will also reject.
    if [[ "$line" == *"error"* ]]; then
      has_error=true
      clean_output+="  ❌  $line"$'\n'
    elif [[ "$line" == *"warning"* ]]; then
      clean_output+="  ⚠️   $line"$'\n'
    fi
  done <<< "$output"

  if $has_error; then
    echo "FAIL  $name"
    echo "$clean_output"
    FAIL=$((FAIL + 1))
  elif [[ -n "$clean_output" ]]; then
    echo "WARN  $name"
    echo "$clean_output"
    WARN=$((WARN + 1))
  else
    if $has_impeller_warn; then
      echo "PASS  $name  (Impeller extensions suppressed)"
    else
      echo "PASS  $name"
    fi
    PASS=$((PASS + 1))
  fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: ${PASS} passed  ${WARN} warnings  ${FAIL} failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "  ⛔  Windows build will fail. Fix the errors above before releasing."
  echo "  Ref: https://github.com/sdegenaar/liquid_glass_widgets/blob/main/knowledge/liquid_glass_shader_windows/artifacts/compatibility_rules.md"
  exit 1
else
  echo ""
  echo "  ✅  All shaders pass Windows/SkSL validation."
  exit 0
fi
