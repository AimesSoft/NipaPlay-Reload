#!/bin/bash
# Step 2: verify the uploaded binary against its sha256, create the system user
# and the directories, install the binary. Does not start anything.
# usage: 02-install-binary.sh <binary> <expected-sha256>
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/00-env.sh"
need_root
binary=${1:?usage: 02-install-binary.sh <binary> <expected-sha256>}
expected=${2:?usage: 02-install-binary.sh <binary> <expected-sha256>}
[ -f "$binary" ] || die "$binary not found"
actual=$(sha256sum "$binary" | awk '{print $1}')
[ "$actual" = "$expected" ] || die "sha256 mismatch: got $actual, expected $expected"
echo "sha256 ok: $actual"

say "System user and directories"
if ! id "$MESH_USER" >/dev/null 2>&1; then
  useradd --system --user-group --home-dir "$MESH_VAR" --no-create-home --shell /usr/sbin/nologin "$MESH_USER"
fi
install -d -o "$MESH_USER" -g "$MESH_USER" -m 750 "$MESH_VAR"
install -d -o root -g "$MESH_USER" -m 750 "$MESH_ETC"
install -d -o root -g root -m 755 "$MESH_OPT"

say "Binary"
target=$MESH_OPT/nipaplay-mesh-coordinator
if [ -e "$target" ]; then
  old=$(sha256sum "$target" | awk '{print $1}')
  [ "$old" = "$actual" ] && { echo "already installed"; exit 0; }
  mv "$target" "$target.prev"   # one level of rollback: rollback.sh binary
  echo "previous binary kept as $target.prev ($old)"
fi
install -o root -g root -m 755 "$binary" "$target"
{ "$target" --help | head -3; } || true
ls -l "$MESH_OPT" "$MESH_ETC" "$MESH_VAR" | sed 's/^/  /'
say "Step 2 done"
