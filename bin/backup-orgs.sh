#!/bin/bash
# Save Point: backs up the metadata of every org listed in the backup folder's orgs.csv, one org after another.
#
#   backup-orgs.sh                          every org in orgs.csv
#   backup-orgs.sh "Client A"             every org of one project
#   backup-orgs.sh "Client A" Full      one org
#   backup-orgs.sh --status                 when each org last backed up, and whether it worked
#   Add --dir <backup folder> to any of these; without it, the folder set by init.sh is used.
#
# For each org, in <Project>/<Org>/ (its own local Git repo, created on the first run):
#   1. sfdx-hardis (sf hardis org monitor backup) lists everything in the org, leaves out managed packages,
#      retrieves the rest, rereads profiles whole, and deletes the files of components removed from the org.
#   2. Standard object settings: Hardis keeps a standard object's own settings file only when the object has a
#      custom field, and otherwise leaves an empty file. This step retrieves the full object for every empty one,
#      and for every object in <Project>/objects.txt, when the org has it.
#   3. Git commits whatever changed. No change, no commit.
#   4. Git packs the org's whole history into one file, <Org>.bundle, in the Drive folder set in settings.env,
#      unless the project's project.conf says drive=off. Google Drive for desktop uploads it.
#      Restore with: git clone "<Org>.bundle" <folder>
#
# Metadata only: records (users, assignments, business hours, holidays and so on) are not backed up.
# Read-only on every org. Nothing is pushed to GitHub or any Git remote.

set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

backup_dir_from_args "$@"
set -- ${REST_ARGS[@]+"${REST_ARGS[@]}"}
[ -d "$BACKUP_DIR" ] || die "Backup folder not found: $BACKUP_DIR"
load_settings
cd "$BACKUP_DIR" || die "Can't open the backup folder: $BACKUP_DIR"

set_launchd_path
export SF_AUTOUPDATE_DISABLE=true SF_DISABLE_AUTOUPDATE=true SF_HIDE_RELEASE_NOTES=true

STATUS_DIR="$BACKUP_DIR/.status"
LOG_DIR="$BACKUP_DIR/logs"
DRIVE="$DRIVE_DIR"
mkdir -p "$STATUS_DIR" "$LOG_DIR"
# The Drive folder is checked on every run, not only by set-drive.sh: settings.env can be edited by hand or
# copied from another Mac. A folder that isn't allowed gets no copy, and each org's run shows drive "refused".
DRIVE_REFUSED=""
if [ -n "$DRIVE" ]; then
  DRIVE_REFUSED="$(drive_dir_problem "$DRIVE")"
  [ -z "$DRIVE_REFUSED" ] || DRIVE=""
fi

# True when macOS privacy protection refuses to list the folder (or its nearest existing parent): the program
# running this script lacks Full Disk Access. On the schedule that program is /bin/bash.
drive_blocked() {
  local p="$1"
  while [ ! -e "$p" ] && [ "$p" != "/" ]; do p="$(dirname "$p")"; done
  ls "$p" 2>&1 > /dev/null | grep -q "Operation not permitted"
}
BLOCKED_MSG="macOS blocked this run from the Drive folder. Give Full Disk Access to /bin/bash (for the schedule), or to the app that started this run"

# run-history.csv: one line per org per run, kept forever (about 100 bytes a line), so a run with no change
# still leaves a record that it ran.
HISTORY="$BACKUP_DIR/run-history.csv"
[ -f "$HISTORY" ] || echo "started,finished,project,org,result,change,files,drive" > "$HISTORY"
record_run() { # started project org result change files drive
  echo "$1,$(date '+%Y-%m-%d %H:%M'),$2,$3,$4,$5,$6,$7" >> "$HISTORY"
}

status_file() { echo "$STATUS_DIR/$1__$2"; }

show_status() {
  printf '%-14s %-12s %-22s %-8s %-18s %s\n' PROJECT ORG ALIAS RESULT "LAST RUN" "LAST CHANGE"
  org_rows | while IFS='|' read -r project org alias; do
    s="$(status_file "$project" "$org")"
    result="never"; when="-"; change="-"
    if [ -f "$s" ]; then IFS='|' read -r when result < "$s"; fi
    if [ -d "$BACKUP_DIR/$project/$org/.git" ]; then
      change="$(git -C "$BACKUP_DIR/$project/$org" log -1 --format='%cd' --date=format:'%Y-%m-%d %H:%M' 2>/dev/null || echo -)"
    fi
    printf '%-14s %-12s %-22s %-8s %-18s %s\n' "$project" "$org" "$alias" "$result" "$when" "$change"
  done
  if [ -n "$DRIVE_REFUSED" ]; then echo "Drive copy refused: $DRIVE_REFUSED Fix it with set-drive.sh."
  elif [ -z "$DRIVE" ]; then echo "Drive copy is off: set the Drive folder with set-drive.sh"; fi
}

# A new org folder: a minimal Salesforce DX project with its own Git repo.
ensure_repo() {
  local dir="$1" name="$2"
  [ -d "$dir/.git" ] && return 0
  mkdir -p "$dir/force-app"
  cat > "$dir/sfdx-project.json" <<EOF
{
  "packageDirectories": [{ "path": "force-app", "default": true }],
  "name": "$name",
  "namespace": "",
  "sourceApiVersion": "67.0"
}
EOF
  git -C "$dir" init -q -b main
}

# Hardis's run report, local CLI state and per-user config stay out of the history.
ensure_gitignore() {
  local dir="$1"
  for line in hardis-report/ .sf/ .sfdx/ config/user/; do
    grep -qxF "$line" "$dir/.gitignore" 2>/dev/null || echo "$line" >> "$dir/.gitignore"
  done
  git -C "$dir" rm -r -q --cached --ignore-unmatch hardis-report config/user > /dev/null 2>&1 || true
}

# Step 2: full settings for standard objects that came back as empty files, plus the project's objects.txt.
object_settings() {
  local dir="$1" project="$2" alias="$3" orglog="$4"
  local wanted
  wanted="$(python3 -I "$KIT_DIR/lib/object_settings.py" "$dir" "$BACKUP_DIR/$project/objects.txt" 2>> "$orglog")" \
    || { log "  object settings: could not read the manifests"; return 1; }
  [ -n "$wanted" ] || { log "  object settings: none needed"; return 0; }
  local args=() o
  for o in $wanted; do args+=(--metadata "CustomObject:$o"); done
  log "  object settings: $wanted"
  if (cd "$dir" && sf project retrieve start "${args[@]}" --target-org "$alias" --ignore-conflicts --wait 30 --json) >> "$orglog" 2>&1; then
    return 0
  fi
  log "  object settings: retrieve failed (see $orglog)"
  return 1
}

change_summary() { python3 -I "$KIT_DIR/lib/change_summary.py"; }

backup_org() {
  local project="$1" org="$2" alias="$3"
  local dir="$BACKUP_DIR/$project/$org"
  local orglog="$LOG_DIR/$(date +%Y-%m-%d) $project $org.log"
  local result="ok" started
  started="$(date '+%Y-%m-%d %H:%M')"
  log "$project / $org ($alias): starting"
  ensure_repo "$dir" "$(echo "$project-$org-backup" | tr ' A-Z' '-a-z' | tr -cd 'a-z0-9-')"
  ensure_gitignore "$dir"

  if ! (cd "$dir" && sf hardis org monitor backup --target-org "$alias" --skip-doc --agent) >> "$orglog" 2>&1; then
    log "  Hardis backup failed (see $orglog). Is the org's login still valid? Try: sf org display -o \"$alias\""
    echo "$started|FAILED" > "$(status_file "$project" "$org")"
    record_run "$started" "$project" "$org" FAILED "not checked" 0 "not written"
    return 1
  fi
  object_settings "$dir" "$project" "$alias" "$orglog" || result="partial"

  git -C "$dir" add -A
  # Files that change on every retrieve with no change in the org: a site's .site file (a binary export that
  # differs by a few bytes; the site's real settings are in the experiences folder as text) and the clean rules
  # (Salesforce returns their mappings in a different order each time). On their own they aren't worth a
  # snapshot; they're saved whenever anything else changes.
  local real change="no change" n=0 drive="off"
  real="$(git -C "$dir" diff --cached --name-only \
    | grep -v -E '^force-app/main/default/(siteDotComSites/.*\.site|cleanDataServices/.*)$' || true)"
  if [ -z "$real" ]; then
    git -C "$dir" reset -q
    git -C "$dir" checkout -q -- . 2>/dev/null || true
    log "  no changes since the last backup"
  else
    local summary
    n="$(git -C "$dir" diff --cached --name-only | wc -l | xargs)"
    summary="$(git -C "$dir" diff --cached --name-status --no-renames | change_summary)"
    git -C "$dir" commit -q -m "$org metadata backup $(date '+%Y-%m-%d %H:%M')" -m "$summary" -m "$n files changed. Taken by backup-orgs.sh."
    log "  committed $n changed files"
    change="new snapshot"
  fi

  # The bundle is rewritten only when the history has a snapshot the Drive copy doesn't, so Drive keeps a new
  # version of the file only when the org changed. .status/<project>__<org>.bundled holds the last snapshot sent.
  if [ -n "$DRIVE_REFUSED" ] && project_drive_on "$project"; then
    log "  Drive copy refused: $DRIVE_REFUSED Fix it with set-drive.sh."; result="partial"; drive="refused"
  elif [ -n "$DRIVE" ] && project_drive_on "$project" && git -C "$dir" rev-parse -q --verify HEAD > /dev/null; then
    local head bundled_file bundle
    head="$(git -C "$dir" rev-parse HEAD)"
    bundled_file="$(status_file "$project" "$org").bundled"
    bundle="$DRIVE/$project/$org.bundle"
    [ -d "$DRIVE" ] || { [ -d "$(dirname "$DRIVE")" ] && mkdir "$DRIVE"; }
    if [ ! -d "$DRIVE" ] && drive_blocked "$DRIVE"; then
      log "  $BLOCKED_MSG."; result="partial"; drive="blocked"
    elif [ ! -d "$DRIVE" ]; then
      log "  Drive folder not found: $DRIVE (is Google Drive for desktop running?)"; result="partial"; drive="failed"
    elif [ -f "$bundle" ] && [ "$(cat "$bundled_file" 2>/dev/null)" = "$head" ]; then
      log "  Drive bundle already up to date"; drive="up to date"
    else
      mkdir -p "$DRIVE/$project"
      local tmp="$DRIVE/$project/.$org.bundle.tmp"
      if git -C "$dir" bundle create -q "$tmp" --all && mv -f "$tmp" "$bundle"; then
        echo "$head" > "$bundled_file"
        log "  bundle written to Drive"; drive="written"
      else
        rm -f "$tmp"; result="partial"
        if drive_blocked "$DRIVE/$project"; then log "  $BLOCKED_MSG."; drive="blocked"
        else log "  bundle to Drive failed"; drive="failed"; fi
      fi
    fi
  fi
  echo "$started|$result" > "$(status_file "$project" "$org")"
  record_run "$started" "$project" "$org" "$result" "$change" "$n" "$drive"
  log "$project / $org: done ($result)"
}

if [ "${1:-}" = "--status" ]; then show_status; exit 0; fi

# One run at a time: a scheduled run that starts while another is going exits. The lock holds the run's process
# ID, so a lock left behind by a run that never finished (power loss, crash) is noticed and cleared.
LOCK="$BACKUP_DIR/.lock"
take_lock() {
  if mkdir "$LOCK" 2>/dev/null; then echo "$$" > "$LOCK/pid"; return 0; fi
  local pid; pid="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [ -n "$pid" ]; then
    # Still running only if that process exists and is a backup run (process IDs get reused).
    ps -p "$pid" -o command= 2>/dev/null | grep -q "backup-orgs" && return 1
  else
    # A lock with no process ID (an older version made it): trust it for 12 hours.
    [ -n "$(find "$LOCK" -maxdepth 0 -mmin +720 2>/dev/null)" ] || return 1
  fi
  log "Clearing a lock left by a run that didn't finish (process ${pid:-unknown} is gone)."
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null || return 1
  echo "$$" > "$LOCK/pid"
}
if ! take_lock; then
  log "Another backup run is in progress. Exiting."
  exit 0
fi
trap 'rm -rf "$LOCK"' EXIT
# Keep the Mac from sleeping until this run ends.
/usr/bin/caffeinate -i -w $$ &

only_project="${1:-}"; only_org="${2:-}"
failed=0; ran=0
while IFS='|' read -r project org alias; do
  [ -n "$only_project" ] && [ "$project" != "$only_project" ] && continue
  [ -n "$only_org" ] && [ "$org" != "$only_org" ] && continue
  ran=$((ran + 1))
  problem="$(name_problem project "$project")$(name_problem org "$org")"
  if [ -n "$problem" ]; then
    log "$project / $org: skipped. $problem Fix the line in orgs.csv."
    failed=$((failed + 1)); continue
  fi
  backup_org "$project" "$org" "$alias" < /dev/null || failed=$((failed + 1))
done < <(org_rows)

[ "$ran" -gt 0 ] || { log "No org in orgs.csv matches: ${only_project:-all} ${only_org}"; exit 1; }

# The setup copy: what's needed to rebuild this backup folder on another Mac (the kit itself is in Git).
# A project whose Drive copy is off keeps its objects.txt off Drive too.
if [ -n "$DRIVE" ] && [ -d "$DRIVE" ]; then
  mkdir -p "$DRIVE/_setup"
  # Copied only when changed, so Drive doesn't keep a new version of each file every run.
  copy_if_changed() { cmp -s "$1" "$2" 2>/dev/null || cp -f "$1" "$2"; }
  [ -f "$BACKUP_DIR/settings.env" ] && copy_if_changed "$BACKUP_DIR/settings.env" "$DRIVE/_setup/settings.env"
  # orgs.csv without the orgs of projects whose Drive copy is off: their client names stay off Drive too.
  filtered="$(mktemp "$BACKUP_DIR/.orgs-drive.XXXXXX")"
  while IFS= read -r line || [ -n "$line" ]; do
    p="$(trim "${line%%,*}")"
    case "$p" in ''|'#'*|project) ;; *) project_drive_on "$p" || continue ;; esac
    printf '%s\n' "$line" >> "$filtered"
  done < "$BACKUP_DIR/orgs.csv"
  copy_if_changed "$filtered" "$DRIVE/_setup/orgs.csv"
  rm -f "$filtered"
  for f in "$BACKUP_DIR"/*/objects.txt; do
    [ -f "$f" ] || continue
    p="$(basename "$(dirname "$f")")"
    project_drive_on "$p" && copy_if_changed "$f" "$DRIVE/_setup/$p objects.txt"
  done
fi
# Only the log files directly in logs/, never anything below it.
find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime +30 -delete 2>/dev/null
log "Run finished: $ran org(s), $failed failed"
[ "$failed" -eq 0 ]
