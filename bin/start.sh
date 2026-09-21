#!/bin/zsh
set -euo pipefail

source "${0:A:h}/common.sh"
assert_external_volume
ensure_runtime_dirs

if pid_is_running "$LOOP_PID_FILE"; then
  print -r -- "工作轨迹记录已运行：PID $(<"$LOOP_PID_FILE")"
  exit 0
fi

[[ -x "$PROJECT_ROOT/bin/context-watcher" ]] || "${0:A:h}/build-context.sh" >/dev/null
# Explicit process only: do not use launchctl, because its background context lacks this Mac's external-volume grant.
/bin/launchctl remove "$LAUNCH_LABEL" 2>/dev/null || true
/bin/rm -f "$PAUSE_FILE" "$RESOURCE_PAUSE_FILE" "$LOOP_PID_FILE" "$ACTIVE_PID_FILE"
nohup /bin/zsh "$PROJECT_ROOT/bin/context_loop.sh" </dev/null >> "$STATE_ROOT/context.log" 2>&1 &
/bin/sleep 1
if pid_is_running "$LOOP_PID_FILE"; then
  print -r -- "已启动工作轨迹记录：PID $(<$LOOP_PID_FILE)；只记上下文变化，关键时刻截图，无音频无视频。"
else
  die "工作轨迹记录未能启动；查看 $STATE_ROOT/context.log"
fi
