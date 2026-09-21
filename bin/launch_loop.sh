#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"
exec "$PROJECT_ROOT/bin/capture_loop.sh" >> "$LOG_FILE" 2>&1
