#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"
assert_external_volume
ensure_runtime_dirs
: > "$PAUSE_FILE"
if pid_is_running "$LOOP_PID_FILE"; then
  pid="$(<"$LOOP_PID_FILE")"
  /bin/kill -TERM "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    /bin/sleep 0.25
    /bin/kill -0 "$pid" 2>/dev/null || break
  done
fi
/bin/rm -f "$LOOP_PID_FILE" "$ACTIVE_PID_FILE"
print -r -- "已暂停工作轨迹记录；不会继续取图。"
