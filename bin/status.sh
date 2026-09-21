#!/bin/zsh
set -euo pipefail

source "${0:A:h}/common.sh"
assert_external_volume
ensure_runtime_dirs

if pid_is_running "$LOOP_PID_FILE"; then
  state="running"
  pid="$(<"$LOOP_PID_FILE")"
  stats="$(/bin/ps -o rss= -o %cpu= -p "$pid" 2>/dev/null | /usr/bin/awk '{printf "rss_mb=%.1f cpu_percent=%s", $1/1024, $2}')"
else
  state="stopped"
  pid="-"
  stats="rss_mb=0 cpu_percent=0"
  /bin/rm -f "$ACTIVE_PID_FILE" "$LOOP_PID_FILE"
fi
pause="no"; [[ -f "$PAUSE_FILE" ]] && pause="manual"; [[ -f "$RESOURCE_PAUSE_FILE" ]] && pause="resource"
timeline="$CONTEXT_ROOT/context-timeline.jsonl"
events=0; [[ -f "$timeline" ]] && events="$(/usr/bin/wc -l < "$timeline" | /usr/bin/tr -d ' ')"
screenshots="$(/usr/bin/find "$CONTEXT_ROOT/context-screenshots" -maxdepth 1 -type f -name '*.jpg' 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
size="$(/usr/bin/du -sh "$CONTEXT_ROOT" 2>/dev/null | /usr/bin/awk '{print $1}')"
print -r -- "state=$state pid=$pid paused=$pause $stats"
print -r -- "events=$events screenshots=$screenshots disk=${size:-0} timeline=$timeline"
