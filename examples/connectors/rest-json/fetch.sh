#!/bin/sh
# Fetches config.json's url (with API_TOKEN as a bearer token, if one is saved) and maps its fields to rows.
dir=$(dirname "$0")
url=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["url"])' "$dir/config.json") || exit 1
if [ -n "$API_TOKEN" ]; then body=$(curl -sf -m 10 -H "Authorization: Bearer $API_TOKEN" "$url"); else body=$(curl -sf -m 10 "$url"); fi || exit 1
python3 - "$dir/config.json" "$body" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
data = json.loads(sys.argv[2])
rows = data.get(cfg.get("list", "items"), []) if isinstance(data, dict) else data
def pick(row, key):
    return row.get(key) if key else None
items = []
for row in rows:
    raw = str(pick(row, cfg.get("status")) or "").lower()
    status = "failing" if raw in cfg.get("failing", []) else "pending" if raw in cfg.get("pending", []) else "running" if raw in cfg.get("running", []) else "ok"
    items.append({"title": str(pick(row, cfg["title"]) or ""), "subtitle": pick(row, cfg.get("subtitle")), "status": status, "url": pick(row, cfg.get("link"))})
print(json.dumps({"items": items}))
PY
