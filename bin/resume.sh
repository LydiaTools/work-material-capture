#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"
assert_external_volume
/bin/rm -f "$PAUSE_FILE" "$RESOURCE_PAUSE_FILE"
exec "$PROJECT_ROOT/bin/start.sh"
