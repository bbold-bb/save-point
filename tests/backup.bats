#!/usr/bin/env bats

load helpers

setup() {
  setup_home
  use_fakes
  make_backup_dir
  ORG="$BACKUP_DIR/Client A/Partial"
}

backup() { run /bin/bash "$KIT/bin/backup-orgs.sh" --dir "$BACKUP_DIR" "$@"; }
last_history() { tail -1 "$BACKUP_DIR/run-history.csv"; }
commits() { git -C "$ORG" rev-list --count HEAD; }

@test "first run commits a baseline and writes the bundle" {
  backup
  [ "$status" -eq 0 ]
  [ "$(commits)" -eq 1 ]
  [ "$(head -1 "$BACKUP_DIR/run-history.csv")" = "started,finished,project,org,result,change,files,drive" ]
  [[ "$(last_history)" =~ ,Client\ A,Partial,ok,new\ snapshot,[0-9]+,written$ ]] || false
  [ -f "$DRIVE_DIR/Client A/Partial.bundle" ]
  git bundle verify -q "$DRIVE_DIR/Client A/Partial.bundle"
  [ "$(cat "$BACKUP_DIR/.status/Client A__Partial.bundled")" = "$(git -C "$ORG" rev-parse HEAD)" ]
  grep -q '|ok$' "$BACKUP_DIR/.status/Client A__Partial"
}

@test "object settings are retrieved for empty placeholders and objects.txt" {
  printf 'Case\nContact\nNotInOrg__c\n' > "$BACKUP_DIR/Client A/objects.txt" 2>/dev/null || {
    mkdir -p "$BACKUP_DIR/Client A"; printf 'Case\nContact\nNotInOrg__c\n' > "$BACKUP_DIR/Client A/objects.txt"; }
  backup
  [ "$status" -eq 0 ]
  grep -q -- '--metadata CustomObject:Account --metadata CustomObject:Case --metadata CustomObject:Contact --target-org ClientA-Partial' "$FAKE_SF_CALLS"
  grep -q '<label>Account</label>' "$ORG/force-app/main/default/objects/Account/Account.object-meta.xml"
}

@test "the commit message lists the changed components" {
  backup
  body="$(git -C "$ORG" log -1 --format=%B)"
  [[ "$body" == *"Partial metadata backup "* ]] || false
  [[ "$body" == *"Added     FlexiPage Case_Record_Page"* ]] || false
  [[ "$body" == *"Added     CustomField Case.Status__c"* ]] || false
  [[ "$body" == *"Taken by backup-orgs.sh."* ]] || false
}

@test "a second run with no change makes no commit" {
  backup
  backup
  [ "$status" -eq 0 ]
  [ "$(commits)" -eq 1 ]
  [[ "$(last_history)" == *",ok,no change,0,up to date" ]] || false
}

@test "a real change makes a new snapshot and a new bundle" {
  backup
  FAKE_SF_CHANGE=1 backup
  [ "$status" -eq 0 ]
  [ "$(commits)" -eq 2 ]
  [[ "$(last_history)" == *",ok,new snapshot,1,written" ]] || false
  [[ "$(git -C "$ORG" log -1 --format=%B)" == *"Modified  FlexiPage Case_Record_Page"* ]] || false
}

@test "a run where only the site file and clean rules change makes no commit" {
  backup
  FAKE_SF_NOISE="different bytes" backup
  [ "$status" -eq 0 ]
  [ "$(commits)" -eq 1 ]
  [[ "$(last_history)" == *",ok,no change,0,up to date" ]] || false
  [ -z "$(git -C "$ORG" status --porcelain)" ]
}

@test "drive=off gives drive off and no bundle" {
  mkdir -p "$BACKUP_DIR/Client A"
  echo "drive=off" > "$BACKUP_DIR/Client A/project.conf"
  echo "Account" > "$BACKUP_DIR/Client A/objects.txt"
  backup
  [ "$status" -eq 0 ]
  [[ "$(last_history)" == *",ok,new snapshot,"*",off" ]] || false
  [ ! -e "$DRIVE_DIR/Client A" ]
  [ ! -e "$DRIVE_DIR/_setup/Client A objects.txt" ]
}

@test "DRIVE_DIR=off gives drive off and no _setup copy" {
  grep -v '^DRIVE_DIR=' "$BACKUP_DIR/settings.env" > "$BATS_TEST_TMPDIR/s"
  echo "DRIVE_DIR=off" >> "$BATS_TEST_TMPDIR/s"
  mv "$BATS_TEST_TMPDIR/s" "$BACKUP_DIR/settings.env"
  backup
  [ "$status" -eq 0 ]
  [[ "$(last_history)" == *",ok,new snapshot,"*",off" ]] || false
  [ ! -e "$DRIVE_DIR/_setup" ]
  [ ! -e "off" ]
  [ ! -e "$BACKUP_DIR/off" ]
}

@test "no Drive folder set gives drive off" {
  grep -v '^DRIVE_DIR=' "$BACKUP_DIR/settings.env" > "$BATS_TEST_TMPDIR/s"
  mv "$BATS_TEST_TMPDIR/s" "$BACKUP_DIR/settings.env"
  backup
  [ "$status" -eq 0 ]
  [[ "$(last_history)" == *",ok,new snapshot,"*",off" ]] || false
}

@test "Drive not reachable gives partial, and the next run writes the bundle (Review Focus 3)" {
  rm -rf "$(dirname "$DRIVE_DIR")"
  backup
  [ "$status" -eq 0 ]
  [[ "$(last_history)" == *",partial,new snapshot,"*",failed" ]] || false
  [ ! -e "$BACKUP_DIR/.status/Client A__Partial.bundled" ]
  grep -q '|partial$' "$BACKUP_DIR/.status/Client A__Partial"
  mkdir -p "$DRIVE_DIR"
  backup
  [ "$status" -eq 0 ]
  [[ "$(last_history)" == *",ok,no change,0,written" ]] || false
  [ -f "$DRIVE_DIR/Client A/Partial.bundle" ]
}

@test "Drive folder itself missing but My Drive present: the folder is created" {
  rm -rf "$DRIVE_DIR"
  backup
  [ "$status" -eq 0 ]
  [ -f "$DRIVE_DIR/Client A/Partial.bundle" ]
}

@test "an org that fails gets FAILED, the next org still runs, exit 1 (Review Focus 2)" {
  make_backup_dir "Client A,Partial,ClientA-Partial" "Client A,Full,ClientA-Full"
  FAKE_SF_FAIL=ClientA-Partial backup
  [ "$status" -eq 1 ]
  grep -q ',Client A,Partial,FAILED,not checked,0,not written$' "$BACKUP_DIR/run-history.csv"
  grep -q ',Client A,Full,ok,new snapshot,[0-9]*,written$' "$BACKUP_DIR/run-history.csv"
  grep -q '|FAILED$' "$BACKUP_DIR/.status/Client A__Partial"
  [[ "$output" == *"sf org display -o \"ClientA-Partial\""* ]] || false
}

@test "one project or one org runs only that" {
  make_backup_dir "Client A,Partial,ClientA-Partial" "Client A,Full,ClientA-Full" "Client B,Partial,ClientB-Partial"
  backup "Client A" Full
  [ "$status" -eq 0 ]
  [ "$(grep -c ',ok,' "$BACKUP_DIR/run-history.csv")" -eq 1 ]
  [ -d "$BACKUP_DIR/Client A/Full/.git" ]
  [ ! -e "$BACKUP_DIR/Client A/Partial" ]
  backup "Client B"
  [ -d "$BACKUP_DIR/Client B/Partial/.git" ]
}

@test "nothing matching exits 1" {
  backup "No Such Project"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No org in orgs.csv matches"* ]] || false
}

@test "a lock already present: the run exits 0 and touches no org (Review Focus 4)" {
  mkdir "$BACKUP_DIR/.lock"
  backup
  [ "$status" -eq 0 ]
  [[ "$output" == *"Another backup run is in progress"* ]] || false
  [ ! -e "$FAKE_SF_CALLS" ]
  [ -d "$BACKUP_DIR/.lock" ]
}

@test "after a normal run the lock is gone" {
  backup
  [ "$status" -eq 0 ]
  [ ! -e "$BACKUP_DIR/.lock" ]
}

@test "the _setup copy holds orgs.csv, settings.env and objects.txt, not the kit" {
  mkdir -p "$BACKUP_DIR/Client A"
  echo "Account" > "$BACKUP_DIR/Client A/objects.txt"
  backup
  [ -f "$DRIVE_DIR/_setup/orgs.csv" ]
  [ -f "$DRIVE_DIR/_setup/settings.env" ]
  [ -f "$DRIVE_DIR/_setup/Client A objects.txt" ]
  [ ! -e "$DRIVE_DIR/_setup/backup-orgs.sh" ]
}

@test "--status lists each org with its last result" {
  backup
  run /bin/bash "$KIT/bin/backup-orgs.sh" --dir "$BACKUP_DIR" --status
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" == "Client A"*"Partial"*"ClientA-Partial"*"ok"* ]] || false
}

@test "the backup repo has no Git remote and ignores Hardis's report" {
  backup
  [ -z "$(git -C "$ORG" remote)" ]
  if git -C "$ORG" ls-files | grep -q '^hardis-report/'; then false; fi
}

@test "a project named Logs in orgs.csv is skipped, and logs/ is left alone" {
  make_backup_dir "Logs,Partial,ClientA-Partial" "Client A,Full,ClientA-Full"
  backup
  [ "$status" -eq 1 ]
  [[ "$output" == *"Logs / Partial: skipped"* ]] || false
  [ ! -d "$BACKUP_DIR/logs/Partial" ]
  [ -d "$BACKUP_DIR/Client A/Full/.git" ]
}

@test "the 30-day cleanup deletes only old .log files directly in logs/" {
  mkdir -p "$BACKUP_DIR/logs/sub"
  touch -t 202001010000 "$BACKUP_DIR/logs/2020-01-01.log" "$BACKUP_DIR/logs/sub/keep.log" "$BACKUP_DIR/logs/keep.txt"
  backup
  [ ! -e "$BACKUP_DIR/logs/2020-01-01.log" ]
  [ -e "$BACKUP_DIR/logs/sub/keep.log" ]
  [ -e "$BACKUP_DIR/logs/keep.txt" ]
}

@test "a relative --dir works from the folder above" {
  cd "$(dirname "$BACKUP_DIR")"
  run /bin/bash "$KIT/bin/backup-orgs.sh" --dir "$(basename "$BACKUP_DIR")"
  [ "$status" -eq 0 ]
  [ -d "$ORG/.git" ]
  [ ! -e "$BACKUP_DIR/$(basename "$BACKUP_DIR")" ]
}

@test "a lock left by a process that's gone is cleared and the run goes ahead" {
  mkdir "$BACKUP_DIR/.lock"
  /bin/bash -c 'exit 0' & dead=$!; wait "$dead"
  echo "$dead" > "$BACKUP_DIR/.lock/pid"
  backup
  [ "$status" -eq 0 ]
  [[ "$output" == *"Clearing a lock"* ]] || false
  [ -d "$ORG/.git" ]
  [ ! -e "$BACKUP_DIR/.lock" ]
}

@test "a lock held by a running backup is respected" {
  mkdir "$BACKUP_DIR/.lock"
  /bin/bash -c 'sleep 20; true' backup-orgs.sh & live=$!
  echo "$live" > "$BACKUP_DIR/.lock/pid"
  backup
  kill "$live"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Another backup run is in progress"* ]] || false
  [ ! -e "$FAKE_SF_CALLS" ]
}

@test "an old lock with no process ID (from the old script) is cleared after 12 hours" {
  mkdir "$BACKUP_DIR/.lock"
  touch -t 202001010000 "$BACKUP_DIR/.lock"
  backup
  [ "$status" -eq 0 ]
  [ -d "$ORG/.git" ]
}

@test "a Drive folder that isn't allowed is refused on every run" {
  grep -v '^DRIVE_DIR=' "$BACKUP_DIR/settings.env" > "$BATS_TEST_TMPDIR/s"
  echo "DRIVE_DIR=$HOME/Library/CloudStorage/GoogleDrive-consultant@gmail.com/My Drive/x" >> "$BATS_TEST_TMPDIR/s"
  mv "$BATS_TEST_TMPDIR/s" "$BACKUP_DIR/settings.env"
  mkdir -p "$HOME/Library/CloudStorage/GoogleDrive-consultant@gmail.com/My Drive/x"
  backup
  [ "$status" -eq 0 ]
  [[ "$(last_history)" == *",partial,new snapshot,"*",refused" ]] || false
  [ -z "$(ls -A "$HOME/Library/CloudStorage/GoogleDrive-consultant@gmail.com/My Drive/x")" ]
}

@test "macOS blocking the Drive folder is recorded as blocked, not as Drive not running" {
  FAKEBIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$FAKEBIN"
  printf '#!/bin/bash\nfor a in "$@"; do case "$a" in *CloudStorage*) echo "ls: $a: Operation not permitted" >&2; exit 1 ;; esac; done\nexec /bin/ls "$@"\n' > "$FAKEBIN/ls"
  chmod +x "$FAKEBIN/ls"
  export SAVE_POINT_PATH="$FAKEBIN:$SAVE_POINT_PATH"
  rm -rf "$DRIVE_DIR"; rm -rf "$(dirname "$DRIVE_DIR")"
  backup
  [ "$status" -eq 0 ]
  [[ "$(last_history)" == *",partial,new snapshot,"*",blocked" ]] || false
  [[ "$output" == *"Full Disk Access"* ]] || false
}

@test "the Drive copy of orgs.csv leaves out projects whose Drive copy is off" {
  make_backup_dir "Client A,Partial,ClientA-Partial" "Secret Client,Prod,Secret-Prod"
  mkdir -p "$BACKUP_DIR/Secret Client"
  echo "drive=off" > "$BACKUP_DIR/Secret Client/project.conf"
  backup "Client A"
  [ -f "$DRIVE_DIR/_setup/orgs.csv" ]
  grep -q "Client A,Partial" "$DRIVE_DIR/_setup/orgs.csv"
  if grep -q "Secret" "$DRIVE_DIR/_setup/orgs.csv"; then false; fi
  grep -qx "project,org,alias" "$DRIVE_DIR/_setup/orgs.csv"
}
