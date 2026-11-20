#!/usr/bin/env bats

load helpers

setup() {
  setup_home
  use_fakes
  make_backup_dir
  export LAUNCH_AGENTS_DIR="$BATS_TEST_TMPDIR/LaunchAgents"
  export LAUNCHCTL="$KIT/tests/fakes/launchctl"
  export FAKE_LAUNCHCTL_CALLS="$BATS_TEST_TMPDIR/launchctl.log"
  PLIST="$LAUNCH_AGENTS_DIR/com.kicksaw.org-backups.plist"
}

sched() { run /bin/bash "$KIT/bin/schedule.sh" --dir "$BACKUP_DIR" "$@"; }
pl() { /usr/bin/plutil -extract "$1" raw -o - "$PLIST"; }

@test "install writes a valid plist with the times, the paths intact, and loads it" {
  sched install --times 02:30,19:15
  [ "$status" -eq 0 ]
  /usr/bin/plutil -lint "$PLIST"
  /usr/bin/python3 -I -c 'import plistlib,sys; plistlib.load(open(sys.argv[1],"rb"))' "$PLIST"
  [ "$(pl Label)" = "com.kicksaw.org-backups" ]
  [ "$(pl ProgramArguments.0)" = "/bin/bash" ]
  [ "$(pl ProgramArguments.1)" = "$KIT/bin/backup-orgs.sh" ]
  [ "$(pl ProgramArguments.2)" = "--dir" ]
  [ "$(pl ProgramArguments.3)" = "$BACKUP_DIR" ]
  [ "$(pl StartCalendarInterval.0.Hour)" = 2 ]
  [ "$(pl StartCalendarInterval.0.Minute)" = 30 ]
  [ "$(pl StartCalendarInterval.1.Hour)" = 19 ]
  [ "$(pl StartCalendarInterval.1.Minute)" = 15 ]
  [ "$(pl StandardOutPath)" = "$BACKUP_DIR/logs/launchd.log" ]
  grep -q "^launchctl bootout gui/$(id -u)/com.kicksaw.org-backups$" "$FAKE_LAUNCHCTL_CALLS"
  grep -q "^launchctl bootstrap gui/$(id -u) $PLIST$" "$FAKE_LAUNCHCTL_CALLS"
  grep -qx "SCHEDULE=02:30,19:15" "$BACKUP_DIR/settings.env"
}

@test "install without --times uses settings.env, then the default" {
  sched install
  [ "$(pl StartCalendarInterval.0.Hour)" = 3 ]
  [ "$(pl StartCalendarInterval.1.Hour)" = 18 ]
  grep -v '^SCHEDULE=' "$BACKUP_DIR/settings.env" > "$BATS_TEST_TMPDIR/s"; echo "SCHEDULE=07:05" >> "$BATS_TEST_TMPDIR/s"
  mv "$BATS_TEST_TMPDIR/s" "$BACKUP_DIR/settings.env"
  sched install
  [ "$(pl StartCalendarInterval.0.Hour)" = 7 ]
  [ "$(pl StartCalendarInterval.0.Minute)" = 5 ]
  run /usr/bin/plutil -extract StartCalendarInterval.1 raw -o - "$PLIST"
  [ "$status" -ne 0 ]
}

@test "a path with an ampersand stays valid XML" {
  B2="$BATS_TEST_TMPDIR/R&D <Backups>"
  mkdir -p "$B2"; cp "$BACKUP_DIR/settings.env" "$B2/"
  run /bin/bash "$KIT/bin/schedule.sh" --dir "$B2" install
  [ "$status" -eq 0 ]
  /usr/bin/plutil -lint "$PLIST"
  [ "$(pl ProgramArguments.3)" = "$B2" ]
}

@test "bad times are refused and nothing is written" {
  for t in 25:00 12:60 7 "03:00,," "3:00" "ab:cd"; do
    sched install --times "$t"
    [ "$status" -eq 2 ]
  done
  [ ! -e "$PLIST" ]
}

@test "remove boots the job out and deletes the plist" {
  sched install
  FAKE_LAUNCHCTL_LOADED=1 sched remove
  [ "$status" -eq 0 ]
  [ ! -e "$PLIST" ]
  [ "$(grep -c bootout "$FAKE_LAUNCHCTL_CALLS")" -eq 2 ]
}

@test "show: loaded, times, last exit code" {
  sched install
  FAKE_LAUNCHCTL_LOADED=1 FAKE_LAUNCHCTL_EXIT=0 sched show
  [ "$status" -eq 0 ]
  [[ "$output" == *"Schedule: loaded"* ]] || false
  [[ "$output" == *"Times: 03:00, 18:00"* ]] || false
  [[ "$output" == *"Last exit code: 0"* ]] || false
  [[ "$output" == *"Full Disk Access: ok"* ]] || false
}

@test "show: exit 126 means /bin/bash lacks Full Disk Access" {
  sched install
  FAKE_LAUNCHCTL_LOADED=1 FAKE_LAUNCHCTL_EXIT=126 sched show
  [[ "$output" == *"Full Disk Access: missing"* ]] || false
  FAKE_LAUNCHCTL_LOADED=1 FAKE_LAUNCHCTL_EXIT=126 sched show --json
  [ "$(/usr/bin/python3 -I -c 'import json,sys; print(json.loads(sys.argv[1])["full_disk_access"])' "$output")" = missing ]
}

@test "show: Operation not permitted in the launchd log also means missing" {
  sched install
  echo "/bin/bash: $KIT/bin/backup-orgs.sh: Operation not permitted" > "$BACKUP_DIR/logs/launchd.log"
  FAKE_LAUNCHCTL_LOADED=1 FAKE_LAUNCHCTL_EXIT=1 sched show
  [[ "$output" == *"Full Disk Access: missing"* ]] || false
}

@test "show: never run yet, and not installed" {
  sched install
  FAKE_LAUNCHCTL_LOADED=1 sched show
  [[ "$output" == *"Full Disk Access: unknown"* ]] || false
  rm "$PLIST"
  sched show
  [ "$status" -eq 1 ]
  [[ "$output" == *"Schedule: not installed"* ]] || false
}

@test "show --json gives the fields doctor reads" {
  sched install --times 02:30,19:15
  FAKE_LAUNCHCTL_LOADED=1 FAKE_LAUNCHCTL_EXIT=0 sched show --json
  keys="$(/usr/bin/python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["loaded"], d["times"], d["last_exit"], d["full_disk_access"])' "$output")"
  [ "$keys" = "True ['02:30', '19:15'] 0 ok" ]
}

@test "a relative --dir is written into the schedule as a full path" {
  cd "$(dirname "$BACKUP_DIR")"
  run /bin/bash "$KIT/bin/schedule.sh" --dir "$(basename "$BACKUP_DIR")" install
  [ "$status" -eq 0 ]
  [ "$(pl ProgramArguments.3)" = "$BACKUP_DIR" ]
}

@test "a flag with no value stops with usage instead of hanging" {
  run perl -e 'alarm 5; exec @ARGV' /bin/bash "$KIT/bin/schedule.sh" --dir "$BACKUP_DIR" install --times
  [ "$status" -eq 2 ]
  run perl -e 'alarm 5; exec @ARGV' /bin/bash "$KIT/bin/schedule.sh" show --dir
  [ "$status" -eq 2 ]
  run perl -e 'alarm 5; exec @ARGV' /bin/bash "$KIT/bin/list-orgs.sh" --dir
  [ "$status" -eq 2 ]
}

@test "show: the last run blocked from Drive means Full Disk Access is missing" {
  sched install
  printf 'started,finished,project,org,result,change,files,drive\n2026-11-19 03:00,2026-11-19 03:02,Client A,Partial,partial,no change,0,blocked\n' > "$BACKUP_DIR/run-history.csv"
  FAKE_LAUNCHCTL_LOADED=1 FAKE_LAUNCHCTL_EXIT=0 sched show
  [[ "$output" == *"Full Disk Access: missing (the last run was blocked from the Google Drive folder)"* ]] || false
}
