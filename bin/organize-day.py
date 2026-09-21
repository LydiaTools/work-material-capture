#!/usr/bin/env python3
import argparse, json
from datetime import date
from pathlib import Path

parser = argparse.ArgumentParser(description="把一天的工作轨迹合并成可搜索的工作段，不调用 AI。")
parser.add_argument("--date", default=date.today().isoformat())
parser.add_argument("--root", required=True)
args = parser.parse_args()
root = Path(args.root)
timeline = root / "context-timeline.jsonl"
out_dir = root / "daily-index"
out_dir.mkdir(parents=True, exist_ok=True)
starts, sessions, shots = [], [], []
if timeline.exists():
    for raw in timeline.read_text(encoding="utf-8").splitlines():
        try: item = json.loads(raw)
        except json.JSONDecodeError: continue
        if not str(item.get("at", "")).startswith(args.date): continue
        if item.get("event") == "session_start": starts.append(item)
        elif item.get("event") == "session_end": sessions.append(item)
        elif item.get("event") == "screenshot": shots.append(item)
result = {
    "date": args.date,
    "source": str(timeline),
    "session_starts": len(starts),
    "completed_sessions": len(sessions),
    "screenshots": len(shots),
    "sessions": sessions,
    "screenshot_index": shots,
    "note": "规则合并结果；未调用 OCR 或 AI，内容含义需后续人工或离线分析确认。",
}
target = out_dir / f"{args.date}.json"
target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(target)
