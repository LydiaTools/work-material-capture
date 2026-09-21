#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"
assert_external_volume
ensure_runtime_dirs
day="${1:-$(/bin/date +%F)}"
exec /usr/bin/python3 "$PROJECT_ROOT/bin/organize-day.py" --date "$day" --root "$CONTEXT_ROOT"
