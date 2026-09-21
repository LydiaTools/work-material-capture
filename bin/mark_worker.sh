#!/bin/zsh
set -euo pipefail
source "${0:A:h}/common.sh"

asset_id="$1"; mark_epoch="$2"; project="$3"; topic="$4"; description="$5"; stage="$6"
before_seconds=180
after_seconds=120
asset_dir="$ASSET_ROOT/$asset_id"

assert_external_volume
ensure_runtime_dirs
print -r -- "waiting ${after_seconds}s after mark so the post-roll is closed"
/bin/sleep "$after_seconds"
assert_external_volume

typeset -a matches
matches=()
for media in "$ROLLING_ROOT"/segment-*.mp4(N); do
  filename="${media:t}"
  remainder="${filename#segment-}"
  start="${remainder%%-*}"
  end="${remainder#*-}"; end="${end%.mp4}"
  [[ "$start" == <-> && "$end" == <-> ]] || continue
  if (( start <= mark_epoch + after_seconds && end >= mark_epoch - before_seconds )); then
    segment_id="segment-${start}-${end}"
    if /usr/bin/rg -F "\"${segment_id}\"" "$CATALOG" >/dev/null 2>&1; then
      print -u2 -r -- "refusing duplicate: source segment already belongs to a permanent asset: $segment_id"
      exit 4
    fi
    matches+=("$media")
  fi
done
(( ${#matches} > 0 )) || die "没有找到可提升的分段；短期收件箱可能未运行或尚未产生有效片段。"

/bin/mkdir -p "$asset_dir/segments"
typeset -a clip_json segment_id_json fact_json
clip_json=(); segment_id_json=(); fact_json=()
total_duration="0"
for media in "${matches[@]}"; do
  filename="${media:t}"
  remainder="${filename#segment-}"
  start="${remainder%%-*}"; end="${remainder#*-}"; end="${end%.mp4}"
  segment_id="segment-${start}-${end}"
  dest="$asset_dir/segments/$filename"
  /bin/cp -p "$media" "$dest"
  sidecar="${media%.mp4}.json"
  [[ -f "$sidecar" ]] && /bin/cp -p "$sidecar" "$asset_dir/segments/${sidecar:t}"
  info="$($FFPROBE -v error -select_streams v:0 -show_entries stream=codec_name,width,height,avg_frame_rate -show_entries format=duration -of default=noprint_wrappers=1 "$dest")"
  codec="$(print -r -- "$info" | /usr/bin/awk -F= '/^codec_name=/{print $2;exit}')"
  width="$(print -r -- "$info" | /usr/bin/awk -F= '/^width=/{print $2;exit}')"
  height="$(print -r -- "$info" | /usr/bin/awk -F= '/^height=/{print $2;exit}')"
  fps="$(print -r -- "$info" | /usr/bin/awk -F= '/^avg_frame_rate=/{print $2;exit}')"
  duration="$(print -r -- "$info" | /usr/bin/awk -F= '/^duration=/{print $2;exit}')"
  [[ "$codec" == h264 && -n "$duration" ]] || die "复制后的媒体未通过 H.264/duration 验证：$dest"
  total_duration="$(/usr/bin/awk -v a="$total_duration" -v b="$duration" 'BEGIN{printf "%.3f",a+b}')"
  clip_json+=("\"$dest\"")
  segment_id_json+=("\"$segment_id\"")
  fact_json+=("{\"segment_id\":\"$segment_id\",\"codec\":\"$codec\",\"width\":$width,\"height\":$height,\"fps\":\"$fps\",\"duration_seconds\":$duration}")
done

thumbnail="$asset_dir/thumbnail.jpg"
"$FFMPEG" -y -v error -ss 1 -i "${matches[1]}" -frames:v 1 -q:v 4 "$thumbnail" || /bin/rm -f "$thumbnail"
created_at="$(/bin/date -r "$mark_epoch" '+%Y-%m-%dT%H:%M:%S%z')"
clips="${(j:,:)clip_json}"; ids="${(j:,:)segment_id_json}"; facts="${(j:,:)fact_json}"
metadata="{\"asset_id\":\"$asset_id\",\"created_at\":\"$created_at\",\"mark_epoch\":$mark_epoch,\"device\":\"Mac mini (local display capture)\",\"project_business\":\"$(json_escape "$project")\",\"topic\":\"$(json_escape "$topic")\",\"stage\":\"$stage\",\"process_stage\":\"$stage\",\"verifiable_facts\":[$facts],\"application\":\"unknown\",\"window_title\":\"unknown\",\"clip_paths\":[$clips],\"source_segment_ids\":[$ids],\"duration_seconds\":$total_duration,\"resolution\":\"up to 720p\",\"privacy\":\"unreviewed\",\"public_eligible\":false,\"manual_review_required\":true,\"source_marker_description\":\"$(json_escape "$description")\",\"asset_path\":\"$asset_dir\"}"
print -r -- "$metadata" > "$asset_dir/metadata.json"
{
  print -r -- "# 工作过程素材包"
  print -r -- ""
  print -r -- "- 素材 ID：$asset_id"
  print -r -- "- 项目/业务：$project"
  print -r -- "- 话题：$topic"
  print -r -- "- 阶段：$stage"
  print -r -- "- 标记说明：$description"
  print -r -- "- 时长：${total_duration} 秒"
  print -r -- "- 隐私状态：未审阅；不可直接公开。"
  print -r -- ""
  print -r -- "本包只记录系统可验证的编码、分辨率、时长，以及标记者提供的说明；没有从画面推断项目、结果或窗口内容。公开视频前必须人工审阅账号、私聊、客户资料、密码、支付、验证码及第三方版权内容。"
} > "$asset_dir/README.md"
print -r -- "$metadata" >> "$CATALOG"
print -r -- "PROMOTED $asset_id clips=${#matches} duration=$total_duration asset=$asset_dir"
