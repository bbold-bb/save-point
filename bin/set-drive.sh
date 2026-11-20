#!/bin/bash
# Save Point: sets the Google Drive folder that gets a copy of each org's history, or turns the copy off.
#
#   set-drive.sh [--dir <backup folder>] <Drive folder>
#   set-drive.sh [--dir <backup folder>] off
#
# Only a folder in your own Kicksaw My Drive is accepted:
#   ~/Library/CloudStorage/GoogleDrive-<you>@kicksaw.com/My Drive/<folder>
# A personal Drive is refused (client metadata stays in Kicksaw's Google Workspace), and so are shared drives
# (two consultants backing up the same org would overwrite each other's copy).

set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
backup_dir_from_args "$@"
set -- ${REST_ARGS[@]+"${REST_ARGS[@]}"}
load_settings

[ "$#" -eq 1 ] && [ -n "$1" ] || { echo "Usage: set-drive.sh [--dir <backup folder>] <Drive folder>|off" >&2; exit 2; }

refuse() { echo "Not changed: $*" >&2; exit 1; }

if [ "$1" = "off" ]; then
  set_setting DRIVE_DIR off
  echo "Drive copy is off for every project. Backups stay on this Mac only."
  exit 0
fi

path="$1"
while [ "${path%/}" != "$path" ]; do path="${path%/}"; done
problem="$(drive_dir_problem "$path")"
[ -z "$problem" ] || refuse "$problem"
prefix="$HOME/Library/CloudStorage/GoogleDrive-"
rest="${path#"$prefix"}"; account="${rest%%/*}"

set_setting DRIVE_DIR "$path"
echo "Drive folder set: $path"
if [ ! -d "$prefix$account/My Drive" ]; then
  echo "Note: $prefix$account/My Drive isn't visible right now. Is Google Drive for desktop running and signed in?"
  echo "Until it is, backups finish as partial and the Drive copy is retried on the next run."
fi
