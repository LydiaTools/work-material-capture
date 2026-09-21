#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
EXTERNAL_VOLUME="/Volumes/Obsidian知识库"
MATERIAL_ROOT="$EXTERNAL_VOLUME/Codex工作运行/30_工作过程素材/工作过程素材库"
CONTEXT_ROOT="$MATERIAL_ROOT/context"
ROLLING_ROOT="$MATERIAL_ROOT/rolling"
ASSET_ROOT="$MATERIAL_ROOT/assets"
CATALOG="$MATERIAL_ROOT/catalog.jsonl"
INBOX_CATALOG="$MATERIAL_ROOT/inbox.jsonl"
CONFIG_ROOT="$PROJECT_ROOT/config"
SENSITIVE_APPS_FILE="$CONFIG_ROOT/sensitive-apps.txt"
STATE_ROOT="$PROJECT_ROOT/runtime"
LOG_FILE="$STATE_ROOT/capture.log"
LOOP_PID_FILE="$STATE_ROOT/capture-loop.pid"
ACTIVE_PID_FILE="$STATE_ROOT/active-capture.pid"
PAUSE_FILE="$STATE_ROOT/PAUSED"
RESOURCE_PAUSE_FILE="$STATE_ROOT/RESOURCE_PAUSED"
RESOURCE_STATUS_FILE="$STATE_ROOT/resource-status.json"
LAUNCH_LABEL="com.codex.work-material-capture"
CAPTURE_BIN="$PROJECT_ROOT/bin/capture-segment"
FFPROBE="/Users/macmini/bin/ffprobe"
FFMPEG="/Users/macmini/bin/ffmpeg"

die() { print -u2 -r -- "ERROR: $*"; exit 1; }

assert_external_volume() {
  [[ -d "$EXTERNAL_VOLUME" ]] || die "外盘未挂载：$EXTERNAL_VOLUME；未写入任何 /Volumes 假目录。"
  /sbin/mount | /usr/bin/grep -F " on $EXTERNAL_VOLUME " >/dev/null || die "外盘不是已挂载卷：$EXTERNAL_VOLUME；未写入任何文件。"
  [[ -w "$EXTERNAL_VOLUME" ]] || die "外盘不可写：$EXTERNAL_VOLUME"
}

ensure_runtime_dirs() {
  /bin/mkdir -p "$STATE_ROOT" "$CONTEXT_ROOT" "$CONTEXT_ROOT/context-screenshots" "$ROLLING_ROOT" "$ASSET_ROOT" "$CONFIG_ROOT"
  [[ -f "$CATALOG" ]] || : > "$CATALOG"
  [[ -f "$INBOX_CATALOG" ]] || : > "$INBOX_CATALOG"
  [[ -f "$SENSITIVE_APPS_FILE" ]] || print -r -- "# One application name or bundle ID per line. Matching stops capture before a new segment starts." > "$SENSITIVE_APPS_FILE"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  print -rn -- "$value"
}

pid_is_running() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 1
  local pid
  pid="$(<"$pid_file")"
  [[ "$pid" == <-> ]] && /bin/kill -0 "$pid" 2>/dev/null
}

frontmost_application() {
  local raw name bundle
  raw="$(/usr/bin/lsappinfo info -only name,bundleid "$(/usr/bin/lsappinfo front 2>/dev/null)" 2>/dev/null || true)"
  name="$(print -r -- "$raw" | /usr/bin/sed -n 's/.*"LSDisplayName"="\([^"]*\)".*/\1/p')"
  bundle="$(print -r -- "$raw" | /usr/bin/sed -n 's/.*"CFBundleIdentifier"="\([^"]*\)".*/\1/p')"
  [[ -n "$name" ]] || name="unknown"
  [[ -n "$bundle" ]] || bundle="unknown"
  print -r -- "${name}|${bundle}"
}

is_sensitive_application() {
  local app_name="$1" bundle_id="$2" entry
  [[ -f "$SENSITIVE_APPS_FILE" ]] || return 1
  while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    [[ "$entry" == "$app_name" || "$entry" == "$bundle_id" ]] && return 0
  done < "$SENSITIVE_APPS_FILE"
  return 1
}

memory_pressure_level() {
  local result
  result="$(/usr/bin/memory_pressure -Q 2>/dev/null || true)"
  if print -r -- "$result" | /usr/bin/grep -Eqi 'critical'; then
    print -r -- "critical"
  elif print -r -- "$result" | /usr/bin/grep -Eqi 'warn|warning'; then
    print -r -- "warning"
  else
    print -r -- "normal"
  fi
}
