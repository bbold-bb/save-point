#!/bin/bash
# Save Point: starts backing up an org.
#
#   add-org.sh [--dir <backup folder>] <project> <org> <alias> [--no-drive]
#
# Adds the line to orgs.csv. For a new project, also creates <project>/objects.txt from the kit's default list
# and <project>/project.conf (drive=on, or drive=off with --no-drive, for a client whose contract keeps its
# metadata off Kicksaw Drive). The alias must be a Salesforce CLI login on this Mac.
# The first backup of the org runs with the next scheduled run, or now with: backup-orgs.sh "<project>" "<org>"

set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
backup_dir_from_args "$@"
set -- ${REST_ARGS[@]+"${REST_ARGS[@]}"}
load_settings

no_drive=0; args=()
for a in "$@"; do
  if [ "$a" = "--no-drive" ]; then no_drive=1; else args+=("$a"); fi
done
[ "${#args[@]}" -eq 3 ] || { echo "Usage: add-org.sh [--dir <backup folder>] <project> <org> <alias> [--no-drive]" >&2; exit 2; }
project="$(trim "${args[0]}")"; org="$(trim "${args[1]}")"; alias="$(trim "${args[2]}")"

for kind in project org; do
  if [ "$kind" = project ]; then v="$project"; else v="$org"; fi
  problem="$(name_problem "$kind" "$v")"
  [ -z "$problem" ] || die "$problem"
done
[ -n "$alias" ] && case "$alias" in *,*|*'|'*) false ;; esac || die "The alias \"$alias\" can't be empty or contain , or |."

while IFS='|' read -r p o a; do
  # Folder names ignore capitals, so "client a" and "Client A" would share one folder.
  if [ "$p" != "$project" ] && [ "$(lower "$p")" = "$(lower "$project")" ]; then
    echo "A project spelled \"$p\" already exists. Use that spelling: folder names on a Mac ignore capitals." >&2; exit 2
  fi
  if [ "$(lower "$p")" = "$(lower "$project")" ] && [ "$(lower "$o")" = "$(lower "$org")" ]; then
    echo "$project / $org is already backed up (alias $a)." >&2; exit 1
  fi
  if [ "$a" = "$alias" ]; then
    echo "$alias is already backed up as $p / $o." >&2; exit 1
  fi
done < <(org_rows)

if ! "$KIT_DIR/bin/list-orgs.sh" --json 2>/dev/null | python3 -I -c '
import json, sys
want = sys.argv[1]
orgs = json.load(sys.stdin)["orgs"]
sys.exit(0 if any(want in (o["alias"], o["username"]) for o in orgs) else 1)' "$alias"; then
  echo "$alias is not a Salesforce CLI login on this Mac. Log in first (the browser opens; you sign in):" >&2
  echo "  sf org login web --alias $alias" >&2
  echo "Add --instance-url <https://...> for Government Cloud or an org with a custom login domain." >&2
  exit 1
fi

file="$BACKUP_DIR/orgs.csv"
[ -f "$file" ] || cp "$KIT_DIR/templates/orgs.csv" "$file"
[ -z "$(tail -c 1 "$file")" ] || echo >> "$file"
echo "$project,$org,$alias" >> "$file"
echo "Added: $project / $org ($alias)"

mkdir -p "$BACKUP_DIR/$project"
if [ ! -f "$BACKUP_DIR/$project/objects.txt" ]; then
  cp "$KIT_DIR/templates/objects.txt" "$BACKUP_DIR/$project/objects.txt"
  echo "Created $project/objects.txt with the default standard objects. Edit it to match what the project uses."
fi
conf="$BACKUP_DIR/$project/project.conf"
if [ ! -f "$conf" ]; then
  if [ "$no_drive" = 1 ]; then echo "drive=off" > "$conf"; else echo "drive=on" > "$conf"; fi
elif [ "$no_drive" = 1 ] && project_drive_on "$project"; then
  echo "drive=off" > "$conf"
fi
if project_drive_on "$project"; then
  [ -n "$DRIVE_DIR" ] && echo "Drive copy: on, in $DRIVE_DIR/$project/" || echo "Drive copy: no Drive folder is set yet (set-drive.sh)."
else
  echo "Drive copy: off for $project. Its backups stay on this Mac only."
fi
