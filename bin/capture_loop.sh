#!/bin/zsh
set -euo pipefail

source "${0:A:h}/common.sh"
SEGMENT_SECONDS="${SEGMENT_SECONDS:-60}"
FPS="${FPS:-5}"
MAX_HEIGHT="${MAX_HEIGHT:-720}"
DISPLAY_INDEX="${DISPLAY_INDEX:-0}"
RSS_LIMIT_KB="${RSS_LIMIT_KB:-256000}"
CPU_LIMIT_PERCENT="${CPU_LIMIT_PERCENT:-8}"
IDLE_LIMIT_SECONDS="${IDLE_LIMIT_SECONDS:-120}"
CHILD_PID=""
CLEANING=0
CURRENT_TEMP_PATH=""
CURRENT_START_EPOCH=""

finalize_interrupted_segment() {
  [[ -n "$CURRENT_TEMP_PATH" && -f "$CURRENT_TEMP_PATH" && -n "$CURRENT_START_EPOCH" ]] || return 0
  local end_epoch media_info codec duration final_path sidecar segment_id sidecar_json
  end_epoch="$(/bin/date +%s)"
  media_info="$($FFPROBE -v error -select_streams v:0 -show_entries stream=codec_name,width,height,avg_frame_rate -show_entries format=duration -of default=noprint_wrappers=1 "$CURRENT_TEMP_PATH" 2>&1 || true)"
  codec="$(print -r -- "$media_info" | /usr/bin/awk -F= '/^codec_name=/{print $2; exit}')"
  duration="$(print -r -- "$media_info" | /usr/bin/awk -F= '/^duration=/{print $2; exit}')"
  if [[ "$codec" == "h264" && -n "$duration" ]]; then
    final_path="$ROLLING_ROOT/segment-${CURRENT_START_EPOCH}-${end_epoch}.mp4"
    /bin/mv "$CURRENT_TEMP_PATH" "$final_path"
    sidecar="$ROLLING_ROOT/segment-${CURRENT_START_EPOCH}-${end_epoch}.json"
    segment_id="segment-${CURRENT_START_EPOCH}-${end_epoch}"
    sidecar_json="{\"segment_id\":\"${segment_id}\",\"started_epoch\":${CURRENT_START_EPOCH},\"ended_epoch\":${end_epoch},\"duration_seconds\":${duration},\"codec\":\"${codec}\",\"application\":\"unknown\",\"bundle_id\":\"unknown\",\"window_title\":\"unknown\",\"privacy\":\"unreviewed\",\"public_eligible\":false,\"manual_review_required\":true,\"source_note\":\"short-term display capture finalized during graceful stop; no audio\"}"
    print -r -- "$sidecar_json" > "$sidecar"
    print -r -- "$sidecar_json" >> "$INBOX_CATALOG"
    print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') interrupted segment finalized path=$final_path duration=$duration" >> "$LOG_FILE"
  else
    /bin/mv "$CURRENT_TEMP_PATH" "$ROLLING_ROOT/failed-${CURRENT_START_EPOCH}-${end_epoch}.partial.mp4"
    print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') interrupted segment unusable and retained as failed partial" >> "$LOG_FILE"
  fi
}

cleanup() {
  (( CLEANING == 1 )) && return
  CLEANING=1
  if [[ -n "$CHILD_PID" ]] && /bin/kill -0 "$CHILD_PID" 2>/dev/null; then
    /bin/kill -TERM "$CHILD_PID" 2>/dev/null || true
    wait "$CHILD_PID" 2>/dev/null || true
  fi
  # launchd may have already delivered TERM to the child before this trap runs;
  # finalize whenever a completed partial exists, not only while its PID is alive.
  finalize_interrupted_segment
  /bin/rm -f "$ACTIVE_PID_FILE" "$LOOP_PID_FILE"
  print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') capture loop stopped" >> "$LOG_FILE"
  exit 0
}
trap cleanup INT TERM HUP

assert_external_volume
ensure_runtime_dirs
print -r -- "$$" > "$LOOP_PID_FILE"
print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') capture loop started; display=$DISPLAY_INDEX ${MAX_HEIGHT}p ${FPS}fps" >> "$LOG_FILE"

while true; do
  if [[ -f "$PAUSE_FILE" || -f "$RESOURCE_PAUSE_FILE" ]]; then
    /bin/sleep 2
    continue
  fi
  assert_external_volume
  pressure="$(memory_pressure_level)"
  if [[ "$pressure" != "normal" ]]; then
    print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') paused memory_pressure=$pressure" >> "$LOG_FILE"
    print -r -- "{\"state\":\"paused\",\"reason\":\"memory_pressure_${pressure}\",\"at\":$(/bin/date +%s)}" > "$RESOURCE_STATUS_FILE"
    /bin/sleep 15
    continue
  fi
  # Do not use awk `exit` here: with pipefail it can SIGPIPE ioreg and terminate the loop.
  idle_seconds="$(/usr/sbin/ioreg -c IOHIDSystem 2>/dev/null | /usr/bin/awk '/HIDIdleTime/ && !seen {print int($NF / 1000000000); seen=1}')"
  idle_seconds="${idle_seconds:-0}"
  if (( idle_seconds >= IDLE_LIMIT_SECONDS )); then
    print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') paused idle_seconds=$idle_seconds" >> "$LOG_FILE"
    print -r -- "{\"state\":\"paused\",\"reason\":\"idle\",\"idle_seconds\":${idle_seconds},\"at\":$(/bin/date +%s)}" > "$RESOURCE_STATUS_FILE"
    /bin/sleep 15
    continue
  fi
  front_info="$(frontmost_application)"
  app_name="${front_info%%|*}"
  bundle_id="${front_info#*|}"
  if is_sensitive_application "$app_name" "$bundle_id"; then
    print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') paused sensitive_application=$app_name bundle=$bundle_id" >> "$LOG_FILE"
    print -r -- "{\"state\":\"paused\",\"reason\":\"sensitive_application\",\"application\":\"$(json_escape "$app_name")\",\"bundle_id\":\"$(json_escape "$bundle_id")\",\"at\":$(/bin/date +%s)}" > "$RESOURCE_STATUS_FILE"
    /bin/sleep 15
    continue
  fi
  start_epoch="$(/bin/date +%s)"
  temp_path="$ROLLING_ROOT/segment-${start_epoch}.partial.mp4"
  CURRENT_TEMP_PATH="$temp_path"
  CURRENT_START_EPOCH="$start_epoch"
  "$CAPTURE_BIN" --output "$temp_path" --seconds "$SEGMENT_SECONDS" --fps "$FPS" --display-index "$DISPLAY_INDEX" --max-height "$MAX_HEIGHT" >> "$LOG_FILE" 2>&1 &
  CHILD_PID="$!"
  print -r -- "$CHILD_PID" > "$ACTIVE_PID_FILE"
  "$PROJECT_ROOT/bin/resource_guard.sh" "$CHILD_PID" "$RSS_LIMIT_KB" "$CPU_LIMIT_PERCENT" "$SEGMENT_SECONDS" >> "$LOG_FILE" 2>&1 &
  GUARD_PID="$!"
  set +e
  wait "$CHILD_PID"
  capture_status="$?"
  set -e
  CHILD_PID=""
  wait "$GUARD_PID" 2>/dev/null || true
  /bin/rm -f "$ACTIVE_PID_FILE"
  CURRENT_TEMP_PATH=""
  CURRENT_START_EPOCH=""
  end_epoch="$(/bin/date +%s)"

  if (( capture_status != 0 )); then
    [[ -f "$temp_path" ]] && /bin/mv "$temp_path" "$ROLLING_ROOT/failed-${start_epoch}-${end_epoch}.partial.mp4"
    print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') segment failed status=$capture_status start=$start_epoch end=$end_epoch" >> "$LOG_FILE"
    if /usr/bin/tail -n 20 "$LOG_FILE" | /usr/bin/grep -Fqi 'TCC'; then
      print -r -- "screen recording TCC denied; do not retry until user reviews Screen Recording permission" > "$RESOURCE_PAUSE_FILE"
      print -r -- "{\"state\":\"paused\",\"reason\":\"screen_recording_tcc_denied\",\"at\":$(/bin/date +%s)}" > "$RESOURCE_STATUS_FILE"
      print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') paused after TCC denial; manual review required" >> "$LOG_FILE"
      continue
    fi
    /bin/sleep 2
    continue
  fi

  media_info="$($FFPROBE -v error -select_streams v:0 -show_entries stream=codec_name,width,height,avg_frame_rate -show_entries format=duration -of default=noprint_wrappers=1 "$temp_path" 2>&1)"
  codec="$(print -r -- "$media_info" | /usr/bin/awk -F= '/^codec_name=/{print $2; exit}')"
  duration="$(print -r -- "$media_info" | /usr/bin/awk -F= '/^duration=/{print $2; exit}')"
  if [[ "$codec" != "h264" || -z "$duration" ]]; then
    /bin/mv "$temp_path" "$ROLLING_ROOT/failed-${start_epoch}-${end_epoch}.partial.mp4"
    print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') segment rejected codec=$codec info=$media_info" >> "$LOG_FILE"
    continue
  fi

  final_path="$ROLLING_ROOT/segment-${start_epoch}-${end_epoch}.mp4"
  /bin/mv "$temp_path" "$final_path"
  sidecar="$ROLLING_ROOT/segment-${start_epoch}-${end_epoch}.json"
  segment_id="segment-${start_epoch}-${end_epoch}"
  sidecar_json="{\"segment_id\":\"${segment_id}\",\"started_epoch\":${start_epoch},\"ended_epoch\":${end_epoch},\"duration_seconds\":${duration},\"codec\":\"${codec}\",\"application\":\"$(json_escape "$app_name")\",\"bundle_id\":\"$(json_escape "$bundle_id")\",\"window_title\":\"unknown\",\"idle_seconds_at_start\":${idle_seconds},\"privacy\":\"unreviewed\",\"public_eligible\":false,\"manual_review_required\":true,\"source_note\":\"automatic short-term display capture; no audio; no OCR or AI classification\"}"
  print -r -- "$sidecar_json" > "$sidecar"
  print -r -- "$sidecar_json" >> "$INBOX_CATALOG"
  print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z') segment verified path=$final_path duration=$duration" >> "$LOG_FILE"

  # Retention is intentionally non-destructive in this first rollout: default policy is 7 days,
  # but no existing inbox file is automatically deleted. A future reviewed cleanup command may act only here.
done
