#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
flutter_tvos_root="${FLUTTER_TVOS_ROOT:-$(dirname "$project_root")/flutter-tvos}"
flutter_tvos_bin="$flutter_tvos_root/bin/flutter-tvos"

if [[ ! -x "$flutter_tvos_bin" ]]; then
  echo "Pinned flutter-tvos SDK not found at $flutter_tvos_root." >&2
  echo "Run $project_root/tool/setup_tvos.sh first." >&2
  exit 1
fi

"$flutter_tvos_root/flutter/bin/dart" \
  run "$project_root/tool/configure_flutter_dependencies.dart" tvos \
  >/dev/null

exec "$flutter_tvos_bin" "$@"
