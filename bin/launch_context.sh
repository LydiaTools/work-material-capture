#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"
exec "$PROJECT_ROOT/bin/context_loop.sh" >> "$STATE_ROOT/context.log" 2>&1
