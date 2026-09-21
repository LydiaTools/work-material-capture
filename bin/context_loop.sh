#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"
assert_external_volume
ensure_runtime_dirs
print -r -- "$$" > "$LOOP_PID_FILE"
exec "$PROJECT_ROOT/bin/context-watcher" "$CONTEXT_ROOT" >> "$STATE_ROOT/context.log" 2>&1
