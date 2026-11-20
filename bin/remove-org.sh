#!/bin/bash
# Save Point: stops backing up an org.
#
#   remove-org.sh [--dir <backup folder>] <project> <org>
#
# Removes the org's line from orgs.csv. Nothing else: the org's backup folder, its Git history, its Drive copy
# and its lines in run-history.csv all stay, so it can still be restored from. Delete them by hand if you mean to.

set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
backup_dir_from_args "$@"
set -- ${REST_ARGS[@]+"${REST_ARGS[@]}"}
load_settings

[ "$#" -eq 2 ] || { echo "Usage: remove-org.sh [--dir <backup folder>] <project> <org>" >&2; exit 2; }
project="$(trim "$1")"; org="$(trim "$2")"
file="$BACKUP_DIR/orgs.csv"
[ -f "$file" ] || { echo "No orgs.csv in $BACKUP_DIR." >&2; exit 1; }

tmp="$(mktemp "$BACKUP_DIR/.orgs.XXXXXX")"
found=0; header_seen=0
while IFS= read -r line || [ -n "$line" ]; do
  IFS=, read -r p o _ <<< "$line"
  p="$(trim "$p")"
  case "$p" in
    ''|'#'*) ;;
    *)
      if [ "$header_seen" = 0 ]; then header_seen=1
      elif [ "$p" = "$project" ] && [ "$(trim "$o")" = "$org" ]; then found=1; continue
      fi ;;
  esac
  printf '%s\n' "$line" >> "$tmp"
done < "$file"

if [ "$found" = 0 ]; then rm -f "$tmp"; echo "$project / $org is not in orgs.csv." >&2; exit 1; fi
mv -f "$tmp" "$file"
echo "Removed $project / $org from orgs.csv. Its backups stay in \"$BACKUP_DIR/$project/$org\" and can still be restored from."
