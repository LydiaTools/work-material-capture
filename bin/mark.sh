#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"

project="${1:-}"
topic="${2:-}"
description="${3:-}"
stage="${4:-unknown}"
[[ -n "$project" && -n "$topic" && -n "$description" ]] || die "用法：mark.sh \"项目/业务\" \"话题\" \"这一步解决了什么\" [stage]"
case "$stage" in discovery|research|design|implementation|fix|result|review|unknown) ;; *) die "stage 只能是 discovery/research/design/implementation/fix/result/review/unknown" ;; esac

assert_external_volume
ensure_runtime_dirs
mark_epoch="$(/bin/date +%s)"
asset_id="asset-${mark_epoch}-$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]' | /usr/bin/cut -c1-8)"
job_log="$MATERIAL_ROOT/jobs/${asset_id}.log"
/bin/mkdir -p "$MATERIAL_ROOT/jobs"
"$PROJECT_ROOT/bin/mark_worker.sh" "$asset_id" "$mark_epoch" "$project" "$topic" "$description" "$stage" > "$job_log" 2>&1 &
worker_pid="$!"
print -r -- "{\"asset_id\":\"${asset_id}\",\"state\":\"waiting_for_post_roll\",\"worker_pid\":${worker_pid},\"mark_epoch\":${mark_epoch},\"log\":\"${job_log}\"}"
