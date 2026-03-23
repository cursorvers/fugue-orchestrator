#!/bin/bash
# x-auto watchdog — checks scheduler heartbeat + queue depth
# Sends macOS notification on anomaly. Runs every 10 min via launchd.
set -euo pipefail

HEARTBEAT="$HOME/.local/share/x-auto/logs/heartbeat.json"
STALE_THRESHOLD_SEC=600   # 10 minutes
LOW_APPROVED_THRESHOLD=3  # alert when fewer than 3 approved posts remain

notify() {
  local title="$1" msg="$2"
  osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null || true
}

# --- Heartbeat freshness ---
if [[ ! -f "$HEARTBEAT" ]]; then
  notify "x-auto ALERT" "heartbeat.json not found — scheduler may be dead"
  exit 1
fi

hb_ts="$(python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta
JST = timezone(timedelta(hours=9))
d = json.load(open('$HEARTBEAT'))
ts = datetime.fromisoformat(d['timestamp']).replace(tzinfo=JST)
now = datetime.now(JST)
print(int((now - ts).total_seconds()))
" 2>/dev/null)" || hb_ts=9999

if (( hb_ts > STALE_THRESHOLD_SEC )); then
  notify "x-auto ALERT" "Scheduler heartbeat stale (${hb_ts}s ago)"
fi

# --- Queue depth ---
approved="$(python3 -c "
import json; d = json.load(open('$HEARTBEAT'))
print(d.get('approved_count', 0))
" 2>/dev/null)" || approved=0

if (( approved < LOW_APPROVED_THRESHOLD )); then
  notify "x-auto WARN" "Queue low: only ${approved} approved posts remaining"
fi
