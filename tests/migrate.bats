#!/usr/bin/env bats
# Review Focus 5: Ben's existing backup folder moved onto the kit makes no new baseline snapshot, honors his
# .status/*.bundled files, and leaves his history untouched.

load helpers

setup() {
  setup_home
  use_fakes
  make_backup_dir
  ORG="$BACKUP_DIR/Client A/Partial"
  # Two snapshots, made the way today's script makes them (same repo layout, status files and bundle path).
  /bin/bash "$KIT/bin/backup-orgs.sh" --dir "$BACKUP_DIR" > /dev/null
  FAKE_SF_PAGE=v2 /bin/bash "$KIT/bin/backup-orgs.sh" --dir "$BACKUP_DIR" > /dev/null
  [ "$(git -C "$ORG" rev-list --count HEAD)" -eq 2 ]
  # Turn it into today's layout: no settings.env, the Drive folder in .drive-dir, and no pointer file.
  echo "$DRIVE_DIR" > "$BACKUP_DIR/.drive-dir"
  rm "$BACKUP_DIR/settings.env"
  rm -f "$HOME/.config/org-backups/backup-dir"
}

@test "init, set-drive from .drive-dir, then a run with no org change: no commit, drive up to date" {
  head_before="$(git -C "$ORG" rev-parse HEAD)"
  log_before="$(git -C "$ORG" log --format='%H %s')"
  history_before="$(cat "$BACKUP_DIR/run-history.csv")"
  bundle_before="$(md5 -q "$DRIVE_DIR/Client A/Partial.bundle")"
  orgs_before="$(cat "$BACKUP_DIR/orgs.csv")"

  run /bin/bash "$KIT/bin/init.sh" "$BACKUP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"set-drive.sh"* ]] || false
  run /bin/bash "$KIT/bin/set-drive.sh" --dir "$BACKUP_DIR" "$(cat "$BACKUP_DIR/.drive-dir")"
  [ "$status" -eq 0 ]
  [ "$(cat "$BACKUP_DIR/orgs.csv")" = "$orgs_before" ]

  FAKE_SF_PAGE=v2 run /bin/bash "$KIT/bin/backup-orgs.sh"
  [ "$status" -eq 0 ]
  [ "$(git -C "$ORG" rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C "$ORG" log --format='%H %s')" = "$log_before" ]
  [[ "$(tail -1 "$BACKUP_DIR/run-history.csv")" == *",Client A,Partial,ok,no change,0,up to date" ]] || false
  [ "$(head -n "$(echo "$history_before" | wc -l)" "$BACKUP_DIR/run-history.csv")" = "$history_before" ]
  [ "$(md5 -q "$DRIVE_DIR/Client A/Partial.bundle")" = "$bundle_before" ]
}
