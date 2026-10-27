#!/bin/sh
# 让打进 app 的 mdk 只用自己带的 libass。
#
# mdk 二进制弱链接 @rpath/libass.<N>.dylib，rpath 里除了 app 自己的目录，还有
# /opt/homebrew/lib 和 /usr/local/lib。mdk.framework 里自带的文件叫 libass.dylib
# （安装名却是 @rpath/libass.<N>.dylib），所以按名字在 framework 里找不到，
# 实际加载的是装了 Homebrew libass 的机器上的那一份。这里：
#   1. 在 framework 里补一个 libass.<N>.dylib 指向自带的 libass.dylib；
#   2. 删掉那两条 rpath，不再去机器上的目录里找；
#   3. 重新签名（改过的二进制签名已失效）。
# 重复运行不会再改动任何东西。
#
# 用法：作为 Runner 的构建阶段运行（读取 Xcode 的环境变量），或者
#   use_bundled_mdk_libass.sh <路径>/mdk.framework
set -eu

FW="${1:-${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}/mdk.framework}"
if [ ! -d "$FW" ]; then
  echo "note: 没有 mdk.framework（${FW}），跳过 libass 处理"
  exit 0
fi

DIR=$(cd "$FW/Versions/Current" 2>/dev/null && pwd -P) || DIR=$(cd "$FW" && pwd -P)
BIN="$DIR/mdk"
if [ ! -f "$BIN" ]; then
  echo "error: 找不到 mdk 二进制：${BIN}" >&2
  exit 1
fi

changed=0

# mdk 要找的 libass 文件名。
WANT=$(otool -L "$BIN" | awk '/@rpath\/libass\.[0-9]+\.dylib/ { sub(/^[ \t]*@rpath\//, ""); print $1; exit }')
if [ -n "$WANT" ] && [ ! -e "$DIR/$WANT" ]; then
  if [ ! -f "$DIR/libass.dylib" ]; then
    echo "error: mdk.framework 里没有自带的 libass.dylib，不能去掉系统目录的 rpath" >&2
    exit 1
  fi
  ln -s libass.dylib "$DIR/$WANT"
  echo "mdk: $WANT -> libass.dylib"
  changed=1
fi

for rpath in /opt/homebrew/lib /usr/local/lib; do
  if otool -l "$BIN" | awk '/cmd LC_RPATH/ { f = 1 } f && /path / { print $2; f = 0 }' | grep -qx "$rpath"; then
    install_name_tool -delete_rpath "$rpath" "$BIN" 2>/dev/null
    echo "mdk: 删除 rpath $rpath"
    changed=1
  fi
done

if [ "$changed" = 1 ]; then
  IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
  if [ "${CODE_SIGNING_ALLOWED:-YES}" = NO ] || [ -z "$IDENTITY" ]; then
    IDENTITY=-
  fi
  # shellcheck disable=SC2086
  /usr/bin/codesign --force --sign "$IDENTITY" ${OTHER_CODE_SIGN_FLAGS:-} \
    --preserve-metadata=identifier,entitlements "$FW"
fi

# 结果：没有那两条 rpath，libass 能在 framework 里找到。
if otool -l "$BIN" | awk '/cmd LC_RPATH/ { f = 1 } f && /path / { print $2; f = 0 }' \
  | grep -qxE '/opt/homebrew/lib|/usr/local/lib'; then
  echo "error: mdk 仍带有系统目录的 rpath" >&2
  exit 1
fi
[ -z "$WANT" ] || [ -e "$DIR/$WANT" ] || { echo "error: $WANT 不在 mdk.framework 里" >&2; exit 1; }
