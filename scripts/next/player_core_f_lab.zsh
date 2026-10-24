#!/bin/zsh
# Run the entire lifecycle under: lockf -k $HOME/.nipa-next/mac-lab.lock zsh <this script>
set -eu
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy
TASK_ROOT=${0:A:h:h:h}
F_RUN_DIR=${1:-$HOME/.nipa-next/player-core-f-runs/$(date +%Y%m%d-%H%M%S)}
# F_PROFILE_NAME and F_APP_DIR let another line run this script on its own
# experiment profile and build copy; F_KERNEL names the kernel it plays on.
F_PROFILE_NAME=${F_PROFILE_NAME:-core-lab-f}
F_PROFILE="$HOME/Library/Application Support/NipaPlay/LabProfiles/$F_PROFILE_NAME"
F_APP="${F_APP_DIR:-$TASK_ROOT/build/macos/Build/Products/Debug/NipaPlay.app}/Contents/MacOS/NipaPlay"
mkdir -p "$F_RUN_DIR"
lsappinfo front > "$F_RUN_DIR/front-before.txt"
cd "$F_PROFILE"
NIPAPLAY_LAB_DHT=0 NIPAPLAY_PROFILE=$F_PROFILE_NAME CODEX_CA_CERTIFICATE="$F_PROFILE/system-ca.pem" SSL_CERT_FILE="$F_PROFILE/system-ca.pem" "$F_APP" > "$F_RUN_DIR/run.log" 2>&1 &
F_PID=$!
print "$F_PID" > "$F_RUN_DIR/pid"
cleanup() {
  kill -TERM "$F_PID" 2>/dev/null || true
  for attempt in {1..30}; do
    kill -0 "$F_PID" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$F_PID" 2>/dev/null; then
    print '实验实例尚未退出' > "$F_RUN_DIR/exit.txt"
  else
    print '实验实例已退出' > "$F_RUN_DIR/exit.txt"
  fi
  lsappinfo front > "$F_RUN_DIR/front-after.txt"
  rg 'main isolate blocked' "$F_RUN_DIR/run.log" > "$F_RUN_DIR/main-isolate-blocked.txt" || true
}
trap cleanup EXIT INT TERM
for attempt in {1..45}; do
  rg -q 'Dart VM service is listening on' "$F_RUN_DIR/run.log" && break
  sleep 1
done
F_MUTED=0
for attempt in {1..30}; do
  if python3 "$HOME/.nipa-next/labmute.py" "$F_RUN_DIR/run.log" > "$F_RUN_DIR/mute.log" 2>&1; then
    F_MUTED=1
    break
  fi
  sleep 1
done
if [[ "$F_MUTED" != 1 ]]; then
  cat "$F_RUN_DIR/mute.log"
  exit 1
fi
lsappinfo front > "$F_RUN_DIR/front-running.txt"
python3 "$TASK_ROOT/scripts/next/player_core_f_lab.py" "$F_RUN_DIR" > "$F_RUN_DIR/experiment.log" 2>&1
print "$F_RUN_DIR"
