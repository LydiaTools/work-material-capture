#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"

if ! pid_is_running "$LOOP_PID_FILE"; then
  /bin/rm -f "$LOOP_PID_FILE" "$ACTIVE_PID_FILE"
  /bin/launchctl remove "$LAUNCH_LABEL" 2>/dev/null || true
  print -r -- "工作轨迹记录未运行。"
  exit 0
fi

loop_pid="$(<"$LOOP_PID_FILE")"
/bin/launchctl remove "$LAUNCH_LABEL" 2>/dev/null || true
/bin/kill -TERM "$loop_pid" 2>/dev/null || true
for _ in {1..20}; do
  /bin/sleep 0.25
  /bin/kill -0 "$loop_pid" 2>/dev/null || { /bin/rm -f "$LOOP_PID_FILE" "$ACTIVE_PID_FILE"; print -r -- "已停止：没有遗留工作轨迹进程。"; exit 0; }
done
die "停止请求已发出，但工作轨迹进程仍在：PID $loop_pid；请运行 status.sh 检查。"
