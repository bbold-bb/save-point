#!/bin/bash
# Save Point: creates a backup folder, or fills in what's missing in an existing one.
#
#   init.sh <backup folder>
#
# Creates the folder, settings.env (KIT_DIR set to this kit, no Drive folder yet, schedule 03:00,18:00),
# orgs.csv, logs/ and .status/, and points ~/.config/org-backups/backup-dir at the folder so the other scripts
# find it without --dir. In a folder that already has these files, it adds only what's missing and changes
# nothing else: orgs.csv, settings.env, history and backups stay as they are.

set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

[ "$#" -eq 1 ] && [ -n "$1" ] || { echo "Usage: init.sh <backup folder>" >&2; exit 2; }
mkdir -p "$1" || die "Can't create the folder: $1"
BACKUP_DIR="$(cd "$1" && pwd)" || die "Can't open the folder: $1"

made=""
note() { made="$made\n  $1"; }

for d in logs .status; do
  [ -d "$BACKUP_DIR/$d" ] || { mkdir -p "$BACKUP_DIR/$d"; note "$d/"; }
done
if [ ! -f "$BACKUP_DIR/orgs.csv" ]; then
  cp "$KIT_DIR/templates/orgs.csv" "$BACKUP_DIR/orgs.csv"; note "orgs.csv"
fi
if [ ! -f "$BACKUP_DIR/settings.env" ]; then
  printf 'KIT_DIR=%s\nDRIVE_DIR=\nSCHEDULE=03:00,18:00\n' "$KIT_DIR" > "$BACKUP_DIR/settings.env"; note "settings.env"
else
  for key in KIT_DIR DRIVE_DIR SCHEDULE; do
    if ! grep -q "^$key=" "$BACKUP_DIR/settings.env"; then
      case "$key" in KIT_DIR) v="$KIT_DIR" ;; SCHEDULE) v="03:00,18:00" ;; *) v="" ;; esac
      set_setting "$key" "$v"; note "settings.env: $key"
    fi
  done
fi

mkdir -p "$(dirname "$POINTER_FILE")"
if [ "$(cat "$POINTER_FILE" 2>/dev/null)" != "$BACKUP_DIR" ]; then
  old="$(cat "$POINTER_FILE" 2>/dev/null || true)"
  echo "$BACKUP_DIR" > "$POINTER_FILE"
  if [ -n "$old" ]; then note "default backup folder changed from $old"; else note "default backup folder set"; fi
fi

echo "Backup folder: $BACKUP_DIR"
if [ -n "$made" ]; then printf "Added:%b\n" "$made"; else echo "Nothing to add: the folder was already set up."; fi
if [ -f "$BACKUP_DIR/.drive-dir" ] && ! grep -q '^DRIVE_DIR=.' "$BACKUP_DIR/settings.env"; then
  echo "This folder has an older .drive-dir file. To keep using that Drive folder, run:"
  echo "  set-drive.sh --dir \"$BACKUP_DIR\" \"$(head -1 "$BACKUP_DIR/.drive-dir")\""
fi
