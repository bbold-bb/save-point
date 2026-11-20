#!/bin/bash
# Save Point: one health check of the whole setup.
#
#   doctor.sh [--dir <backup folder>] [--json]
#
# One line per check, each ok, warn or fail, with a one-line fix for anything not ok: the kit's version; each
# dependency; each backed-up org's login; the schedule; Full Disk Access (from the last scheduled run); the
# Drive folder; and each org's last run in run-history.csv (warn when it's more than 26 hours old).
# Exits 0 when nothing is fail.

set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
backup_dir_from_args "$@"
set -- ${REST_ARGS[@]+"${REST_ARGS[@]}"}
json=0
[ "${1:-}" = "--json" ] && json=1
load_settings
set_launchd_path

if ! command -v python3 > /dev/null 2>&1; then
  echo "fail  Dependency xcode-clt: python3 is missing"
  echo "      fix: xcode-select --install"
  exit 1
fi

setup_json="$("$KIT_DIR/bin/setup.sh" --check --json 2>/dev/null)"
orgs_json="$("$KIT_DIR/bin/list-orgs.sh" --dir "$BACKUP_DIR" --json 2>/dev/null)"
schedule_json="$("$KIT_DIR/bin/schedule.sh" --dir "$BACKUP_DIR" show --json 2>/dev/null)"
rows="$(org_rows)"
drive_off_projects=""
while IFS='|' read -r p _ _; do
  [ -n "$p" ] || continue
  project_drive_on "$p" || drive_off_projects="$drive_off_projects$p
"
done <<< "$rows"

# A .lock folder: a run going now, or one left behind by a run that didn't finish.
lock_state="none"
if [ -d "$BACKUP_DIR/.lock" ]; then
  lock_pid="$(cat "$BACKUP_DIR/.lock/pid" 2>/dev/null || true)"
  if [ -n "$lock_pid" ] && ps -p "$lock_pid" -o command= 2>/dev/null | grep -q backup-orgs; then lock_state="running"
  else lock_state="stale"; fi
fi

drive_problem=""
[ -n "$DRIVE_DIR" ] && drive_problem="$(drive_dir_problem "$DRIVE_DIR")"

python3 -I - "$drive_problem" "$lock_state" "$json" "$(kit_version)" "$setup_json" "$orgs_json" "$schedule_json" "$rows" \
  "$BACKUP_DIR/run-history.csv" "$DRIVE_DIR" "$DRIVE_CHOICE" "$drive_off_projects" <<'PY'
import csv, datetime, json, os, sys

drive_problem = sys.argv.pop(1)
lock_state = sys.argv.pop(1)
(mode, version, setup_raw, orgs_raw, schedule_raw, rows_raw, history_path,
 drive_dir, drive_choice, drive_off_raw) = sys.argv[1:11]
checks = []

def add(status, check, detail, fix=""):
    checks.append({"check": check, "status": status, "detail": detail, "fix": fix})

def load(raw):
    try:
        return json.loads(raw)
    except Exception:
        return None

add("ok", "Save Point", version)

setup = load(setup_raw)
if setup is None:
    add("fail", "Dependencies", "setup.sh --check could not run", "Run setup.sh --check to see why")
else:
    for item in setup["items"]:
        if item["status"] in ("ok", "not needed"):
            add("ok", "Dependency " + item["name"], item["version"] or item["status"])
        else:
            add("fail", "Dependency " + item["name"], item["status"], item["fix"])

rows = [r.split("|") for r in rows_raw.splitlines() if r.count("|") == 2]
orgs = load(orgs_raw)
if not rows:
    add("warn", "Orgs", "no org is backed up yet", "add-org.sh <project> <org> <alias>")
elif orgs is None:
    add("fail", "Logins", "could not list the Salesforce CLI logins", "Run list-orgs.sh to see why")
else:
    by = {}
    for o in orgs["orgs"]:
        by.setdefault(o["alias"], o)
        by.setdefault(o["username"], o)
    for project, org, alias in rows:
        o = by.get(alias)
        login_fix = "sf org login web --alias " + alias
        if o is None:
            add("fail", "Login " + alias, "not a login on this Mac (%s / %s)" % (project, org), login_fix)
        elif o["connected"] == "yes":
            add("ok", "Login " + alias, "connected")
        elif o["connected"] == "expired":
            add("fail", "Login " + alias, "expired: log in again", login_fix)
        else:
            add("fail", "Login " + alias, "the org didn't answer (deleted or refreshed sandbox?)",
                login_fix + "  (or remove-org.sh if the org is gone)")

sched = load(schedule_raw)
if sched is None:
    add("fail", "Schedule", "schedule.sh show could not run", "Run schedule.sh show to see why")
else:
    if not sched["installed"]:
        add("fail", "Schedule", "not installed", "schedule.sh install")
    elif not sched["loaded"]:
        add("fail", "Schedule", "installed but not loaded", "schedule.sh install")
    else:
        add("ok", "Schedule", "loaded, " + ", ".join(sched["times"]))
    fda = sched["full_disk_access"]
    fda_fix = ("System Settings > Privacy & Security > Full Disk Access: click +, press Cmd+Shift+G, "
               "type /bin/bash, click Open, and turn it on")
    if fda == "ok":
        add("ok", "Full Disk Access", sched["detail"])
    elif fda == "missing":
        add("fail", "Full Disk Access", sched["detail"], fda_fix)
    elif sched["installed"]:
        add("warn", "Full Disk Access", "not known yet: " + sched["detail"],
            "Wait for the next scheduled run, or run: launchctl kickstart gui/%d/%s" % (os.getuid(), sched["label"]))

if lock_state == "running":
    add("ok", "Run in progress", "a backup is running now")
elif lock_state == "stale":
    add("warn", "Leftover lock", "a run didn't finish and left its .lock folder; the next run clears it",
        "Nothing to do, or start a run now: backup-orgs.sh")

drive_off = [p for p in drive_off_raw.splitlines() if p]
off_note = (" (off for %s)" % ", ".join(drive_off)) if drive_off else ""
if drive_choice == "off":
    add("ok", "Drive", "off by choice: backups stay on this Mac only")
elif drive_problem:
    add("fail", "Drive", "folder not allowed: " + drive_problem, "set-drive.sh \"<a folder in your Kicksaw My Drive>\"")
elif not drive_dir:
    add("warn", "Drive", "no Drive folder set, so backups stay on this Mac only",
        "set-drive.sh \"$HOME/Library/CloudStorage/GoogleDrive-<you>@kicksaw.com/My Drive/Org Backups\"")
else:
    def state(path):
        try:
            os.stat(path)
            return "present" if os.path.isdir(path) else "not a folder"
        except PermissionError:
            return "blocked"
        except FileNotFoundError:
            return "missing"
    s = state(drive_dir)
    if s == "present":
        add("ok", "Drive", drive_dir + off_note)
    elif s == "blocked" or state(os.path.dirname(drive_dir)) == "blocked":
        add("warn", "Drive", "this shell isn't allowed to look in the Drive folder (macOS privacy protection)",
            "Check run-history.csv: a drive value of written or up to date means the scheduled runs reach it")
    elif s == "missing" and state(os.path.dirname(drive_dir)) == "present":
        add("ok", "Drive", drive_dir + " (created on the next run)" + off_note)
    else:
        add("fail", "Drive", "folder not found: " + drive_dir, "Is Google Drive for desktop running?")

last = {}
if os.path.isfile(history_path):
    with open(history_path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            last[(r.get("project", ""), r.get("org", ""))] = r
now = datetime.datetime.now()
for project, org, alias in rows:
    name = "Last run %s / %s" % (project, org)
    r = last.get((project, org))
    if r is None:
        add("warn", name, "never backed up", 'backup-orgs.sh "%s" "%s"' % (project, org))
        continue
    when = r.get("finished") or r.get("started") or ""
    try:
        age = (now - datetime.datetime.strptime(when, "%Y-%m-%d %H:%M")).total_seconds() / 3600
    except ValueError:
        age = None
    detail = "%s, %s, %s, drive %s" % (when, r.get("result", ""), r.get("change", ""), r.get("drive", ""))
    if r.get("result") == "FAILED":
        add("fail", name, detail, "See the log in logs/, then: backup-orgs.sh \"%s\" \"%s\"" % (project, org))
    elif age is not None and age > 26:
        add("warn", name, detail + " (%d hours ago)" % age, "Is the schedule loaded? Was the Mac off? doctor.sh shows the schedule above")
    elif r.get("result") == "partial":
        add("warn", name, detail, "A step after the backup failed (object settings or Drive); see logs/")
    else:
        add("ok", name, detail)

failed = any(c["status"] == "fail" for c in checks)
if mode == "1":
    print(json.dumps({"ok": not failed, "checks": checks}))
else:
    for c in checks:
        print("%-4s  %s: %s" % (c["status"], c["check"], c["detail"]))
        if c["fix"] and c["status"] != "ok":
            print("      fix: " + c["fix"])
sys.exit(1 if failed else 0)
PY
