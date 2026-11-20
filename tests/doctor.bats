#!/usr/bin/env bats

load helpers

# A healthy setup: every dependency present, logins connected, schedule loaded and last run ok, Drive present,
# both orgs backed up an hour ago.
setup() {
  setup_home
  use_fakes
  make_backup_dir "Client A,Partial,ClientA-Partial" "Client A,Full,ClientA-Full"
  FAKEBIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$FAKEBIN"
  printf '#!/bin/bash\necho v24.18.0\n' > "$FAKEBIN/node"
  printf '#!/bin/bash\necho "Homebrew 5.0.0"\n' > "$FAKEBIN/brew"
  chmod +x "$FAKEBIN"/*
  export SAVE_POINT_PATH="$FAKEBIN:$SAVE_POINT_PATH" PATH="$FAKEBIN:$PATH"
  export LAUNCH_AGENTS_DIR="$BATS_TEST_TMPDIR/LaunchAgents" LAUNCHCTL="$KIT/tests/fakes/launchctl"
  /bin/bash "$KIT/bin/schedule.sh" --dir "$BACKUP_DIR" install > /dev/null
  export FAKE_LAUNCHCTL_LOADED=1 FAKE_LAUNCHCTL_EXIT=0
  history_line "Client A" Partial 1 ok
  history_line "Client A" Full 1 ok
}

# project org hours-ago result
history_line() {
  local f="$BACKUP_DIR/run-history.csv" when
  [ -f "$f" ] || echo "started,finished,project,org,result,change,files,drive" > "$f"
  when="$(date -v-"$3"H '+%Y-%m-%d %H:%M')"
  echo "$when,$when,$1,$2,$4,no change,0,up to date" >> "$f"
}

doctor() { run /bin/bash "$KIT/bin/doctor.sh" --dir "$BACKUP_DIR" "$@"; }
line_for() { echo "$output" | grep -E "^(ok|warn|fail) +$1" | head -1; }

@test "everything healthy exits 0 with no warn or fail" {
  doctor
  [ "$status" -eq 0 ]
  [[ "$output" != *"warn "* ]] || false
  [[ "$output" != *"fail "* ]] || false
  [[ "$(line_for 'Save Point')" == ok*"$(cat "$KIT/VERSION")"* ]] || false
  [[ "$(line_for 'Schedule')" == ok* ]] || false
  [[ "$(line_for 'Full Disk Access')" == ok* ]] || false
}

@test "an expired login fails, naming the alias, with the login command" {
  export FAKE_SF_ORG_LIST="$BATS_TEST_TMPDIR/orgs.json"
  cat > "$FAKE_SF_ORG_LIST" <<'JSON'
{"status":0,"result":{"nonScratchOrgs":[
 {"alias":"ClientA-Partial","username":"a@b.c","instanceUrl":"https://x","isSandbox":true,"connectedStatus":"Connected"},
 {"alias":"ClientA-Full","username":"d@e.f","instanceUrl":"https://y","isSandbox":true,"connectedStatus":"Unable to refresh session due to: expired access/refresh token"}],"scratchOrgs":[]}}
JSON
  doctor
  [ "$status" -eq 1 ]
  [[ "$(line_for 'Login ClientA-Full')" == fail* ]] || false
  [[ "$output" == *"sf org login web --alias ClientA-Full"* ]] || false
  [[ "$(line_for 'Login ClientA-Partial')" == ok* ]] || false
}

@test "a login missing from this Mac fails" {
  make_backup_dir "Client A,Partial,ClientA-Partial" "Client X,Prod,ClientX-Prod"
  history_line "Client A" Partial 1 ok; history_line "Client X" Prod 1 ok
  doctor
  [ "$status" -eq 1 ]
  [[ "$(line_for 'Login ClientX-Prod')" == fail* ]] || false
}

@test "a last run 30 hours old warns" {
  history_line "Client A" Full 30 ok
  # The newest line for Full is now the 30-hour one only if it's the last; rewrite the history to be sure.
  grep -v ',Full,' "$BACKUP_DIR/run-history.csv" > "$BATS_TEST_TMPDIR/h"; mv "$BATS_TEST_TMPDIR/h" "$BACKUP_DIR/run-history.csv"
  history_line "Client A" Full 30 ok
  doctor
  [ "$status" -eq 0 ]
  [[ "$(line_for 'Last run Client A / Full')" == warn* ]] || false
  [[ "$(line_for 'Last run Client A / Partial')" == ok* ]] || false
}

@test "a last run that FAILED fails, and partial warns" {
  history_line "Client A" Full 0 FAILED
  history_line "Client A" Partial 0 partial
  doctor
  [ "$status" -eq 1 ]
  [[ "$(line_for 'Last run Client A / Full')" == fail* ]] || false
  [[ "$(line_for 'Last run Client A / Partial')" == warn* ]] || false
}

@test "an org never backed up warns" {
  make_backup_dir "Client A,Partial,ClientA-Partial"
  rm "$BACKUP_DIR/run-history.csv"
  doctor
  [[ "$(line_for 'Last run Client A / Partial')" == warn*"never"* ]] || false
}

@test "a missing Drive folder fails with the Drive question" {
  rm -rf "$(dirname "$DRIVE_DIR")"
  doctor
  [ "$status" -eq 1 ]
  [[ "$(line_for 'Drive')" == fail* ]] || false
  [[ "$output" == *"Is Google Drive for desktop running?"* ]] || false
}

@test "Drive off by choice is ok, and never set warns" {
  grep -v '^DRIVE_DIR=' "$BACKUP_DIR/settings.env" > "$BATS_TEST_TMPDIR/s"; echo "DRIVE_DIR=off" >> "$BATS_TEST_TMPDIR/s"
  cp "$BATS_TEST_TMPDIR/s" "$BACKUP_DIR/settings.env"
  doctor
  [[ "$(line_for 'Drive')" == ok*"off"* ]] || false
  grep -v '^DRIVE_DIR=' "$BACKUP_DIR/settings.env" > "$BATS_TEST_TMPDIR/s"; echo "DRIVE_DIR=" >> "$BATS_TEST_TMPDIR/s"
  cp "$BATS_TEST_TMPDIR/s" "$BACKUP_DIR/settings.env"
  doctor
  [[ "$(line_for 'Drive')" == warn* ]] || false
}

@test "schedule not installed fails; Full Disk Access missing fails" {
  /bin/bash "$KIT/bin/schedule.sh" remove > /dev/null
  FAKE_LAUNCHCTL_LOADED=0 doctor
  [ "$status" -eq 1 ]
  [[ "$(line_for 'Schedule')" == fail*  ]] || false
  [[ "$output" == *"schedule.sh install"* ]] || false
  /bin/bash "$KIT/bin/schedule.sh" --dir "$BACKUP_DIR" install > /dev/null
  FAKE_LAUNCHCTL_EXIT=126 doctor
  [ "$status" -eq 1 ]
  [[ "$(line_for 'Full Disk Access')" == fail* ]] || false
  [[ "$output" == *"Privacy & Security"* ]] || false
}

@test "a missing dependency fails with its fix" {
  rm "$FAKEBIN/node"
  doctor
  [ "$status" -eq 1 ]
  [[ "$(line_for 'Dependency node')" == fail* ]] || false
  [[ "$output" == *"brew install node"* ]] || false
}

@test "--json gives every check with status, detail and fix" {
  doctor --json
  [ "$status" -eq 0 ]
  /usr/bin/python3 -I -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["ok"] is True
assert all(set(c) == {"check", "status", "detail", "fix"} for c in d["checks"]), d
assert any(c["check"] == "Schedule" for c in d["checks"])' "$output"
}

@test "a leftover lock warns; a Drive folder that isn't allowed fails" {
  mkdir "$BACKUP_DIR/.lock"; echo 999999 > "$BACKUP_DIR/.lock/pid"
  doctor
  [[ "$(line_for 'Leftover lock')" == warn* ]] || false
  grep -v '^DRIVE_DIR=' "$BACKUP_DIR/settings.env" > "$BATS_TEST_TMPDIR/s"
  echo "DRIVE_DIR=/tmp/elsewhere" >> "$BATS_TEST_TMPDIR/s"
  cp "$BATS_TEST_TMPDIR/s" "$BACKUP_DIR/settings.env"
  doctor
  [ "$status" -eq 1 ]
  [[ "$(line_for 'Drive')" == fail*"not allowed"* ]] || false
}
