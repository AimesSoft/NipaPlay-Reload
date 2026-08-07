#!/bin/bash
SOURCE="$0"
while [ -L "${SOURCE}" ]; do
  DIR="$(cd -P "$(dirname "${SOURCE}")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "${SOURCE}")"
  case "${SOURCE}" in
    /*) ;;
    *) SOURCE="${DIR}/${SOURCE}" ;;
  esac
done
HERE="$(cd -P "$(dirname "${SOURCE}")" >/dev/null 2>&1 && pwd)"

if [ ! -x "${HERE}/NipaPlay" ]; then
  echo "错误：未找到可执行文件 ${HERE}/NipaPlay" >&2
  echo "请确认 NipaPlay 安装完整。" >&2
  exit 1
fi

export LD_LIBRARY_PATH="${HERE}/lib/:${LD_LIBRARY_PATH}"
exec "${HERE}/NipaPlay" "$@"
