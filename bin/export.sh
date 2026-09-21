#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"
asset_id="${1:-}"; destination="${2:-}"
[[ -n "$asset_id" && -n "$destination" ]] || die "用法：export.sh ASSET_ID /绝对/视频素材目录 [--copy]"
mode="link"; [[ "${3:-}" == "--copy" ]] && mode="copy"
[[ "$destination" == /* ]] || die "导出目录必须是绝对路径"
assert_external_volume
ensure_runtime_dirs
line="$(/usr/bin/rg -F "\"asset_id\":\"$asset_id\"" "$CATALOG" | /usr/bin/tail -n 1 || true)"
[[ -n "$line" ]] || die "未找到素材 ID：$asset_id"
asset_path="$(print -r -- "$line" | /usr/bin/sed -n 's/.*"asset_path":"\([^"]*\)".*/\1/p')"
[[ -d "$asset_path/segments" ]] || die "素材包不完整：$asset_path"
/bin/mkdir -p "$destination"
target="$destination/$asset_id"
[[ ! -e "$target" && ! -L "$target" ]] || die "导出目标已存在：$target"
if [[ "$mode" == copy ]]; then
  /bin/cp -R "$asset_path" "$target"
else
  /bin/ln -s "$asset_path" "$target"
fi
print -r -- "$target"
