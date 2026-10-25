#!/bin/bash
# Step 5: add `location ^~ /mesh/` to the site, test, reload. The site file is
# only replaced after `nginx -t` accepts the new text; if the test or the
# reload fails the previous text is put back.
# usage: 05-nginx-add-location.sh [--dry-run]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/00-env.sh"
need_root
new=$(mktemp "$NGINX_VHOST.new.XXXXXX")        # does not end in .conf: never included
trap 'rm -f "$new"' EXIT
python3 "$DEPLOY_DIR/nginx_location.py" add "$NGINX_VHOST" "$DEPLOY_DIR/nginx-location.conf" > "$new"
say "The change"
diff -u "$NGINX_VHOST" "$new" || true
[ "${1:-}" = "--dry-run" ] && { echo "(dry run: nothing written)"; exit 0; }

cp -a "$NGINX_VHOST" "$STATE_DIR/vhost.before-step5"
cat "$new" > "$NGINX_VHOST"          # same inode, same owner and mode as before
if ! "$NGINX_BIN" -t; then
  cat "$STATE_DIR/vhost.before-step5" > "$NGINX_VHOST"
  die "nginx -t rejected the new text; the site file is back as it was"
fi
if ! "$NGINX_BIN" -s reload; then
  cat "$STATE_DIR/vhost.before-step5" > "$NGINX_VHOST"; "$NGINX_BIN" -t && "$NGINX_BIN" -s reload || true
  die "reload failed; the site file is back as it was"
fi
sleep 1
say "Step 5 done (nginx reloaded). Undo with: rollback.sh nginx"
