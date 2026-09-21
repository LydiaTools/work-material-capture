#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"

target_pid="$1"
rss_limit_kb="$2"
cpu_limit="$3"
segment_seconds="$4"
over_limit_seconds=0

while /bin/kill -0 "$target_pid" 2>/dev/null; do
  pressure="$(memory_pressure_level)"
  stats="$(/bin/ps -o rss= -o %cpu= -p "$target_pid" 2>/dev/null || true)"
  rss="$(print -r -- "$stats" | /usr/bin/awk '{print $1}')"
  cpu="$(print -r -- "$stats" | /usr/bin/awk '{print $2}')"
  rss="${rss:-0}"; cpu="${cpu:-0}"
  if [[ "$pressure" != normal ]] || (( rss > rss_limit_kb )) || (( ${cpu%.*} > ${cpu_limit%.*} )); then
    over_limit_seconds=$((over_limit_seconds + 10))
  else
    over_limit_seconds=0
  fi
  print -r -- "{\"state\":\"monitoring\",\"pid\":${target_pid},\"rss_kb\":${rss},\"cpu_percent\":${cpu},\"memory_pressure\":\"${pressure}\",\"over_limit_seconds\":${over_limit_seconds},\"at\":$(/bin/date +%s)}" > "$RESOURCE_STATUS_FILE"
  if (( over_limit_seconds >= 60 )); then
    print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') guard stopped pid=$target_pid rss_kb=$rss cpu=$cpu pressure=$pressure" >> "$LOG_FILE"
    print -r -- "{\"state\":\"paused\",\"reason\":\"resource_limit\",\"pid\":${target_pid},\"rss_kb\":${rss},\"cpu_percent\":${cpu},\"memory_pressure\":\"${pressure}\",\"at\":$(/bin/date +%s)}" > "$RESOURCE_STATUS_FILE"
    print -r -- "resource limit; manual resume required" > "$RESOURCE_PAUSE_FILE"
    # The recorder maps TERM to stopCapture + AVAssetWriter.finishWriting before exit.
    # Never use KILL here: it would leave an unplayable MP4 with no moov atom.
    /bin/kill -TERM "$target_pid" 2>/dev/null || true
    exit 0
  fi
  /bin/sleep 10
done
