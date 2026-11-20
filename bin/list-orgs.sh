#!/bin/bash
# Save Point: lists the Salesforce CLI logins on this Mac and which ones are backed up.
#
#   list-orgs.sh [--dir <backup folder>] [--json]
#
# One row per login (scratch orgs left out): alias, username, instance_url, kind (production, sandbox or
# unknown), connected (yes; expired, meaning log in again; error, meaning the org didn't answer, often a
# sandbox that was deleted or refreshed away), and backed_up (project/org when orgs.csv lists it).
# Only those six fields are shown. The CLI's own output, which holds access tokens, is never printed or saved.

set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
set_launchd_path

json=0; dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json) json=1; shift ;;
    --dir) [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "--dir needs a folder path." >&2; exit 2; }
      dir="$(abs_path "$2")"; shift 2 ;;
    *) echo "Usage: list-orgs.sh [--dir <backup folder>] [--json]" >&2; exit 2 ;;
  esac
done
# The backup folder is optional here: before init.sh there is nothing backed up yet.
if [ -z "$dir" ] && [ -s "$POINTER_FILE" ]; then dir="$(head -1 "$POINTER_FILE")"; fi
BACKUP_DIR="$dir"
backed=""
if [ -n "$BACKUP_DIR" ]; then backed="$(org_rows)"; fi

sf org list --json 2>/dev/null | python3 -I -c '
import json, sys
mode, backed = sys.argv[1], sys.argv[2]
try:
    result = json.load(sys.stdin)["result"]
except Exception:
    print("Could not read the Salesforce CLI logins (sf org list --json). Is the Salesforce CLI installed?", file=sys.stderr)
    sys.exit(1)
by_login = {}
for line in backed.splitlines():
    parts = line.split("|")
    if len(parts) == 3:
        by_login.setdefault(parts[2], parts[0] + "/" + parts[1])
logins = result.get("nonScratchOrgs")
if logins is None:
    logins = result.get("other", []) + result.get("sandboxes", []) + result.get("devHubs", [])
rows, seen = [], set()
for o in logins:
    if o.get("isScratch") or o.get("username") in seen:
        continue
    seen.add(o.get("username"))
    status = o.get("connectedStatus") or ""
    if status == "Connected":
        connected = "yes"
    elif "expired" in status.lower() or "refresh token" in status.lower():
        connected = "expired"
    else:
        connected = "error"
    sandbox = o.get("isSandbox")
    kind = "sandbox" if sandbox is True else "production" if sandbox is False else "unknown"
    alias, username = o.get("alias") or "", o.get("username") or ""
    rows.append({"alias": alias, "username": username, "instance_url": o.get("instanceUrl") or "",
                 "kind": kind, "connected": connected,
                 "backed_up": by_login.get(alias) or by_login.get(username) or ""})
rows.sort(key=lambda r: (r["alias"] or r["username"]).lower())
if mode == "1":
    print(json.dumps({"orgs": rows}))
else:
    fmt = "%-28s %-42s %-10s %-9s %s"
    print(fmt % ("ALIAS", "USERNAME", "KIND", "CONNECTED", "BACKED UP"))
    for r in rows:
        print(fmt % (r["alias"] or "-", r["username"], r["kind"], r["connected"], r["backed_up"] or "-"))
' "$json" "$backed"
