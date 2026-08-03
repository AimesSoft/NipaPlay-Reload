#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
version_file="$project_root/.flutter-version-tvos"
flutter_tvos_repository="https://github.com/fluttertv/flutter-tvos.git"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "flutter-tvos requires macOS." >&2
  exit 1
fi

if [[ ! -f "$version_file" ]]; then
  echo "Missing $version_file" >&2
  exit 1
fi

flutter_tvos_version="$(tr -d '[:space:]' < "$version_file")"
flutter_tvos_root="${FLUTTER_TVOS_ROOT:-$(dirname "$project_root")/flutter-tvos}"

if [[ -e "$flutter_tvos_root" && ! -d "$flutter_tvos_root/.git" ]]; then
  echo "$flutter_tvos_root exists but is not a flutter-tvos checkout." >&2
  exit 1
fi

if [[ ! -d "$flutter_tvos_root/.git" ]]; then
  git clone \
    --depth 1 \
    --branch "$flutter_tvos_version" \
    "$flutter_tvos_repository" \
    "$flutter_tvos_root"
else
  git -C "$flutter_tvos_root" remote set-url origin "$flutter_tvos_repository"
  git -C "$flutter_tvos_root" fetch \
    --depth 1 \
    origin \
    "refs/tags/$flutter_tvos_version:refs/tags/$flutter_tvos_version"

  required_commit="$(git -C "$flutter_tvos_root" rev-list -n 1 "$flutter_tvos_version")"
  current_commit="$(git -C "$flutter_tvos_root" rev-parse HEAD)"
  if [[ "$current_commit" != "$required_commit" ]]; then
    if [[ -n "$(git -C "$flutter_tvos_root" status --porcelain)" ]]; then
      echo "Refusing to replace a modified flutter-tvos checkout:" >&2
      echo "  $flutter_tvos_root" >&2
      exit 1
    fi
    git -C "$flutter_tvos_root" checkout --detach "$flutter_tvos_version"
  fi
fi

"$flutter_tvos_root/bin/flutter-tvos" precache
"$flutter_tvos_root/bin/flutter-tvos" --version
"$flutter_tvos_root/bin/flutter-tvos" doctor -v

echo
echo "flutter-tvos is ready at: $flutter_tvos_root"
echo "Use $project_root/tool/flutter_tvos.sh to run the pinned SDK."
