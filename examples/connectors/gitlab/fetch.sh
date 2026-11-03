#!/bin/sh
# Needs a GitLab personal access token with the read_api scope (saved in Settings > Connectors).
# Set a self-hosted address by putting it in a file named gitlab.url next to this script.
base=$(cat "$(dirname "$0")/gitlab.url" 2>/dev/null || echo "https://gitlab.com")
auth="PRIVATE-TOKEN: $GITLAB_TOKEN"
me=$(curl -sf -m 10 -H "$auth" "$base/api/v4/user") || exit 1
reviewing=$(curl -sf -m 10 -H "$auth" "$base/api/v4/merge_requests?state=opened&scope=all&reviewer_username=$(printf '%s' "$me" | python3 -c 'import sys,json;print(json.load(sys.stdin)["username"])')&per_page=20") || exit 1
mine=$(curl -sf -m 10 -H "$auth" "$base/api/v4/merge_requests?state=opened&scope=created_by_me&per_page=20") || exit 1
python3 - "$reviewing" "$mine" <<'PY'
import json, sys
items = []
for mr in json.loads(sys.argv[1]):
    items.append({"id": "review-%s" % mr["id"], "title": mr["title"], "subtitle": "Review: " + mr["references"]["full"],
                  "status": "pending", "url": mr["web_url"]})
for mr in json.loads(sys.argv[2]):
    pipeline = (mr.get("head_pipeline") or {}).get("status", "")
    status = "failing" if pipeline == "failed" else "running" if pipeline in ("running", "pending") else "ok"
    items.append({"id": "mine-%s" % mr["id"], "title": mr["title"], "subtitle": "Yours: " + mr["references"]["full"],
                  "status": status, "url": mr["web_url"]})
print(json.dumps({"items": items}))
PY
