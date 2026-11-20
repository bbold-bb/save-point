#!/bin/bash
# Save Point: installs, removes or shows the backup schedule (a launchd job, com.kicksaw.org-backups).
#
#   schedule.sh [--dir <backup folder>] install [--times 03:00,18:00]
#   schedule.sh remove
#   schedule.sh [--dir <backup folder>] show [--json]
#
# install writes ~/Library/LaunchAgents/com.kicksaw.org-backups.plist from the kit's template (the kit's
# backup-orgs.sh, this backup folder, one start time per entry, log in <backup folder>/logs/launchd.log), saves
# the times in settings.env, and loads the job. Without --times it uses the times in settings.env.
# show prints whether the job is loaded, its times, the last exit code, and what that says about Full Disk
# Access: a scheduled run that ends with exit 126, or "Operation not permitted" in launchd.log, means macOS
# blocked /bin/bash from the protected folders.
# LAUNCH_AGENTS_DIR and LAUNCHCTL can be set to test it without touching the real schedule.

set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

LABEL="com.kicksaw.org-backups"
AGENTS="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
LCTL="${LAUNCHCTL:-/bin/launchctl}"
PLIST="$AGENTS/$LABEL.plist"
DOMAIN="gui/$(id -u)"

usage() { echo "Usage: schedule.sh [--dir <backup folder>] install [--times HH:MM,HH:MM] | remove | show [--json]" >&2; exit 2; }

# The backup folder is needed for install, and used by show when known.
dir=""; args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "--dir needs a folder path." >&2; exit 2; }
      dir="$(abs_path "${2%/}")"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- ${args[@]+"${args[@]}"}
[ "$#" -ge 1 ] || usage
cmd="$1"; shift

xml_escape() { local s="$1"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; printf '%s' "$s"; }

# Checks a list like 03:00,18:00. Each time is HH:MM, 24-hour, two digits each.
valid_times() {
  local t list="$1"
  [ -n "$list" ] || return 1
  case "$list" in ,*|*,|*,,*) return 1 ;; esac
  local IFS=,
  for t in $list; do
    [[ "$t" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || return 1
  done
}

do_install() {
  local times=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --times) [ "$#" -ge 2 ] || usage
        times="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  if [ -n "$dir" ]; then BACKUP_DIR="$dir"; else backup_dir_from_args; fi
  load_settings
  [ -n "$times" ] || times="${SCHEDULE:-03:00,18:00}"
  valid_times "$times" || { echo "Times must look like 03:00,18:00 (24-hour, HH:MM, comma between). Got: $times" >&2; exit 2; }

  local intervals="" t h m IFS_old="$IFS"
  IFS=,
  for t in $times; do
    h="$((10#${t%%:*}))"; m="$((10#${t##*:}))"
    intervals="$intervals        <dict><key>Hour</key><integer>$h</integer><key>Minute</key><integer>$m</integer></dict>
"
  done
  IFS="$IFS_old"
  intervals="${intervals%
}"

  mkdir -p "$AGENTS" "$BACKUP_DIR/logs"
  local tmp; tmp="$(mktemp "$AGENTS/.$LABEL.XXXXXX")"
  local tmpl; tmpl="$(cat "$KIT_DIR/templates/$LABEL.plist")"
  tmpl="${tmpl//__LABEL__/$LABEL}"
  tmpl="${tmpl//__SCRIPT__/$(xml_escape "$KIT_DIR/bin/backup-orgs.sh")}"
  tmpl="${tmpl//__BACKUP_DIR__/$(xml_escape "$BACKUP_DIR")}"
  tmpl="${tmpl//__LOG__/$(xml_escape "$BACKUP_DIR/logs/launchd.log")}"
  tmpl="${tmpl//__INTERVALS__/$intervals}"
  printf '%s\n' "$tmpl" > "$tmp"
  if ! /usr/bin/plutil -lint -s "$tmp"; then rm -f "$tmp"; echo "The schedule file came out invalid; nothing was changed." >&2; exit 1; fi
  mv -f "$tmp" "$PLIST"
  set_setting SCHEDULE "$times"

  "$LCTL" bootout "$DOMAIN/$LABEL" > /dev/null 2>&1 || true     # not loaded yet is fine
  if ! "$LCTL" bootstrap "$DOMAIN" "$PLIST"; then
    echo "The schedule file is written but macOS didn't load it. Try: launchctl bootstrap $DOMAIN \"$PLIST\"" >&2
    exit 1
  fi
  echo "Schedule installed: $(echo "$times" | sed 's/,/, /g') every day, backing up \"$BACKUP_DIR\"."
  echo "Next: give /bin/bash Full Disk Access (System Settings > Privacy & Security > Full Disk Access), or the"
  echo "scheduled runs can't read the backup folder or Google Drive."
}

do_remove() {
  "$LCTL" bootout "$DOMAIN/$LABEL" > /dev/null 2>&1 || true
  if [ -f "$PLIST" ]; then rm -f "$PLIST"; echo "Schedule removed. Backups no longer run on their own; your backups stay."
  else echo "No schedule was installed."; fi
}

do_show() {
  local json=0
  [ "${1:-}" = "--json" ] && json=1
  local installed=false loaded=false last="" times="" fda="unknown" detail="" folder="" print_out
  if [ -f "$PLIST" ]; then
    installed=true
    times="$(python3 -I - "$PLIST" 2>/dev/null <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    p = plistlib.load(f)
iv = p.get("StartCalendarInterval", [])
if isinstance(iv, dict):
    iv = [iv]
print(",".join("%02d:%02d" % (i.get("Hour", 0), i.get("Minute", 0)) for i in iv))
args = p.get("ProgramArguments", [])
print(args[args.index("--dir") + 1] if "--dir" in args and args.index("--dir") + 1 < len(args) else "")
PY
)" || times=""
    folder="$(echo "$times" | sed -n 2p)"; times="$(echo "$times" | sed -n 1p)"
  fi
  if print_out="$("$LCTL" print "$DOMAIN/$LABEL" 2>/dev/null)"; then
    loaded=true
    last="$(echo "$print_out" | sed -n 's/^[[:space:]]*last exit code = \([0-9-]*\).*/\1/p' | head -1)"
  fi
  [ -n "$folder" ] || folder="${dir%/}"
  local launchd_log="$folder/logs/launchd.log"
  # The newest run-history line's drive value: "blocked" means macOS kept the run out of the Drive folder.
  local last_drive=""
  [ -n "$folder" ] && last_drive="$(tail -1 "$folder/run-history.csv" 2>/dev/null | awk -F, '{print $NF}')"
  if [ "$last_drive" = "blocked" ]; then
    fda="missing"; detail="the last run was blocked from the Google Drive folder"
  elif [ -z "$last" ]; then
    fda="unknown"; detail="no scheduled run has finished yet"
  elif [ "$last" = 126 ]; then
    fda="missing"; detail="the last scheduled run ended with exit 126"
  elif [ "$last" != 0 ] && [ -n "$folder" ] && tail -20 "$launchd_log" 2>/dev/null | grep -q "Operation not permitted"; then
    fda="missing"; detail="launchd.log shows Operation not permitted"
  elif [ "$last" = 0 ]; then
    fda="ok"; detail="the last scheduled run finished"
  else
    fda="unknown"; detail="the last run ended with exit $last; see the logs"
  fi

  if [ "$json" = 1 ]; then
    python3 -I -c '
import json, sys
installed, loaded, times, last, fda, detail, folder = sys.argv[1:8]
print(json.dumps({"installed": installed == "true", "loaded": loaded == "true",
  "times": [t for t in times.split(",") if t], "last_exit": int(last) if last.lstrip("-").isdigit() else None,
  "full_disk_access": fda, "detail": detail, "backup_dir": folder, "label": "com.kicksaw.org-backups"}))
' "$installed" "$loaded" "$times" "$last" "$fda" "$detail" "$folder"
  else
    if [ "$installed" = false ]; then echo "Schedule: not installed (schedule.sh install)"
    elif [ "$loaded" = true ]; then echo "Schedule: loaded"
    else echo "Schedule: installed but not loaded (schedule.sh install loads it again)"; fi
    [ -n "$times" ] && echo "Times: $(echo "$times" | sed 's/,/, /g')"
    [ -n "$folder" ] && echo "Backup folder: $folder"
    echo "Last exit code: ${last:-none yet}"
    echo "Full Disk Access: $fda ($detail)"
  fi
  [ "$loaded" = true ]
}

case "$cmd" in
  install) do_install "$@" ;;
  remove) do_remove ;;
  show) do_show "$@" ;;
  *) usage ;;
esac
