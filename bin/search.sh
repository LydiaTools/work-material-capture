#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"
assert_external_volume
ensure_runtime_dirs

field=""; value=""; public_only=0
while (( $# )); do
  case "$1" in
    --project|--topic|--stage|--keyword) field="${1#--}"; shift; value="${1:-}"; [[ -n "$value" ]] || die "$field 需要一个值" ;;
    --public-only) public_only=1 ;;
    *) die "用法：search.sh [--project 名称] [--topic 话题] [--stage 阶段] [--keyword 关键词] [--public-only]" ;;
  esac
  shift
done
[[ -s "$CATALOG" ]] || { print -r -- "没有长期素材包。短期收件箱在：$INBOX_CATALOG"; exit 0; }
while IFS= read -r line; do
  [[ -n "$field" ]] && ! print -r -- "$line" | /usr/bin/grep -Fqi -- "$value" && continue
  (( public_only == 1 )) && ! print -r -- "$line" | /usr/bin/grep -F '"public_eligible":true' >/dev/null && continue
  print -r -- "$line"
done < "$CATALOG"
