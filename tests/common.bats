#!/usr/bin/env bats

load helpers

setup() {
  setup_home
}

@test "backup_dir_from_args takes --dir, spaces intact, and keeps the other arguments" {
  run /bin/bash -c 'source "$1/lib/common.sh"; backup_dir_from_args --dir "/tmp/x y" "Client A" Full; echo "dir=$BACKUP_DIR"; for a in "${REST_ARGS[@]}"; do echo "arg=$a"; done' _ "$KIT"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "dir=/tmp/x y" ]
  [ "${lines[1]}" = "arg=Client A" ]
  [ "${lines[2]}" = "arg=Full" ]
}

@test "backup_dir_from_args falls back to the pointer file" {
  mkdir -p "$HOME/.config/org-backups"
  echo "/tmp/from pointer" > "$HOME/.config/org-backups/backup-dir"
  run /bin/bash -c 'source "$1/lib/common.sh"; backup_dir_from_args; echo "$BACKUP_DIR"' _ "$KIT"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/from pointer" ]
}

@test "backup_dir_from_args with no flag and no pointer exits 2" {
  run /bin/bash -c 'source "$1/lib/common.sh"; backup_dir_from_args; echo "not reached"' _ "$KIT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"No backup folder set"* ]] || false
  [[ "$output" != *"not reached"* ]] || false
}

@test "load_settings reads settings.env without running it" {
  make_backup_dir
  echo 'EXTRA=$(touch "$HOME/ran")' >> "$BACKUP_DIR/settings.env"
  run /bin/bash -c 'source "$1/lib/common.sh"; BACKUP_DIR="$2"; load_settings; echo "$DRIVE_DIR"; echo "$SCHEDULE"' _ "$KIT" "$BACKUP_DIR"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$DRIVE_DIR" ]
  [ "${lines[1]}" = "03:00,18:00" ]
  [ ! -e "$HOME/ran" ]
}

@test "set_setting replaces one key and keeps the rest" {
  make_backup_dir
  run /bin/bash -c 'source "$1/lib/common.sh"; BACKUP_DIR="$2"; set_setting SCHEDULE "02:30,19:15"; set_setting NEWKEY "a b"' _ "$KIT" "$BACKUP_DIR"
  [ "$status" -eq 0 ]
  grep -qx 'SCHEDULE=02:30,19:15' "$BACKUP_DIR/settings.env"
  grep -qx 'NEWKEY=a b' "$BACKUP_DIR/settings.env"
  grep -qx "DRIVE_DIR=$DRIVE_DIR" "$BACKUP_DIR/settings.env"
  [ "$(grep -c '^SCHEDULE=' "$BACKUP_DIR/settings.env")" -eq 1 ]
}

@test "org_rows skips comments, blank lines and the header, and trims spaces" {
  make_backup_dir
  printf '# comment\n\nproject,org,alias\nClient A , Partial , ClientA-Partial\n  # indented comment\nClient B,Partial,ClientB-Partial\r\n' > "$BACKUP_DIR/orgs.csv"
  run /bin/bash -c 'source "$1/lib/common.sh"; BACKUP_DIR="$2"; org_rows' _ "$KIT" "$BACKUP_DIR"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "Client A|Partial|ClientA-Partial" ]
  [ "${lines[1]}" = "Client B|Partial|ClientB-Partial" ]
}

@test "project_drive_on is false when project.conf says drive=off" {
  make_backup_dir
  mkdir -p "$BACKUP_DIR/Client A"
  echo "drive=off" > "$BACKUP_DIR/Client A/project.conf"
  run /bin/bash -c 'source "$1/lib/common.sh"; BACKUP_DIR="$2"; project_drive_on "Client A"' _ "$KIT" "$BACKUP_DIR"
  [ "$status" -ne 0 ]
}

@test "project_drive_on is true when project.conf is missing or says on" {
  make_backup_dir
  run /bin/bash -c 'source "$1/lib/common.sh"; BACKUP_DIR="$2"; project_drive_on "Client A"' _ "$KIT" "$BACKUP_DIR"
  [ "$status" -eq 0 ]
  mkdir -p "$BACKUP_DIR/Client A"
  echo "drive=on" > "$BACKUP_DIR/Client A/project.conf"
  run /bin/bash -c 'source "$1/lib/common.sh"; BACKUP_DIR="$2"; project_drive_on "Client A"' _ "$KIT" "$BACKUP_DIR"
  [ "$status" -eq 0 ]
}

@test "log writes a timestamped line to the day's log" {
  make_backup_dir
  run /bin/bash -c 'source "$1/lib/common.sh"; BACKUP_DIR="$2"; log "hello there"' _ "$KIT" "$BACKUP_DIR"
  [ "$status" -eq 0 ]
  grep -q 'hello there$' "$BACKUP_DIR/logs/$(date +%Y-%m-%d).log"
}

@test "kit_version prints VERSION" {
  run /bin/bash -c 'source "$1/lib/common.sh"; kit_version' _ "$KIT"
  [ "$output" = "$(cat "$KIT/VERSION")" ]
}

@test "set_launchd_path uses SAVE_POINT_PATH when set, else the launchd list" {
  run /bin/bash -c 'source "$1/lib/common.sh"; SAVE_POINT_PATH=/a:/b set_launchd_path; echo "$PATH"' _ "$KIT"
  [ "$output" = "/a:/b" ]
  run /bin/bash -c 'unset SAVE_POINT_PATH; source "$1/lib/common.sh"; set_launchd_path; echo "$PATH"' _ "$KIT"
  [[ "$output" == *"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" ]] || false
  [[ "$output" == "$HOME/.npm-global/bin:"* ]] || false
}

@test "name_problem: reserved names in any capitals, odd characters, double underscores" {
  for n in logs Logs LOGS _setup _Setup; do
    run /bin/bash -c 'source "$1/lib/common.sh"; name_problem project "$2"' _ "$KIT" "$n"
    [ -n "$output" ]
  done
  run /bin/bash -c 'source "$1/lib/common.sh"; name_problem org Logs' _ "$KIT"
  [ -z "$output" ]
  for n in 'a"b' 'a\b' 'a__b' '.x' 'a/b' 'a,b' 'a|b' ''; do
    run /bin/bash -c 'source "$1/lib/common.sh"; name_problem project "$2"' _ "$KIT" "$n"
    [ -n "$output" ]
  done
  for n in "Client A" "O'Brien & Co" "Client_A-2.0"; do
    run /bin/bash -c 'source "$1/lib/common.sh"; name_problem project "$2"' _ "$KIT" "$n"
    [ -z "$output" ]
  done
}

@test "backup_dir_from_args makes a relative folder absolute" {
  cd "$BATS_TEST_TMPDIR"
  run /bin/bash -c 'source "$1/lib/common.sh"; backup_dir_from_args --dir "Org Backups"; echo "$BACKUP_DIR"' _ "$KIT"
  [ "$output" = "$(pwd)/Org Backups" ]
  run /bin/bash -c 'source "$1/lib/common.sh"; backup_dir_from_args --dir "~/Org Backups"; echo "$BACKUP_DIR"' _ "$KIT"
  [ "$output" = "$HOME/Org Backups" ]
}

@test "drive_dir_problem refuses a link inside My Drive that leads outside it" {
  ks="$HOME/Library/CloudStorage/GoogleDrive-consultant@kicksaw.com/My Drive"
  mkdir -p "$ks" "$HOME/Library/CloudStorage/GoogleDrive-consultant@gmail.com/My Drive/x"
  ln -s "$HOME/Library/CloudStorage/GoogleDrive-consultant@gmail.com/My Drive/x" "$ks/Backups"
  run /bin/bash -c 'source "$1/lib/common.sh"; drive_dir_problem "$2"' _ "$KIT" "$ks/Backups"
  [[ "$output" == *"isn't in your Kicksaw My Drive"* ]] || false
  mkdir -p "$ks/Real"
  run /bin/bash -c 'source "$1/lib/common.sh"; drive_dir_problem "$2"' _ "$KIT" "$ks/Real"
  [ -z "$output" ]
}
