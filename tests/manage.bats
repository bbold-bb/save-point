#!/usr/bin/env bats

load helpers

setup() {
  setup_home
  use_fakes
  NEW="$BATS_TEST_TMPDIR/x/Org Backups"
  KS="$HOME/Library/CloudStorage/GoogleDrive-consultant@kicksaw.com"
  export FAKE_SF_ORG_LIST="$BATS_TEST_TMPDIR/orgs.json"
  cat > "$FAKE_SF_ORG_LIST" <<'JSON'
{"status":0,"result":{"nonScratchOrgs":[
 {"alias":"ClientA-Partial","username":"consultant@clienta.com.partial","instanceUrl":"https://clienta--partial.sandbox.my.salesforce.com","isSandbox":true,"connectedStatus":"Connected"},
 {"alias":"ClientA-Prod","username":"consultant@clienta.com","instanceUrl":"https://clienta.my.salesforce.com","isSandbox":false,"connectedStatus":"Connected"}
],"scratchOrgs":[]}}
JSON
}

sp() { run /bin/bash "$KIT/bin/$1" "${@:2}"; }
snapshot() { (cd "$NEW" && find . -type f -exec md5 -r {} \; | sort); }

@test "init.sh creates every file and the pointer" {
  sp init.sh "$NEW"
  [ "$status" -eq 0 ]
  [ -f "$NEW/settings.env" ]
  [ -f "$NEW/orgs.csv" ]
  [ -d "$NEW/logs" ]
  [ -d "$NEW/.status" ]
  grep -qx "KIT_DIR=$KIT" "$NEW/settings.env"
  grep -qx "SCHEDULE=03:00,18:00" "$NEW/settings.env"
  grep -qx "DRIVE_DIR=" "$NEW/settings.env"
  grep -qx "project,org,alias" "$NEW/orgs.csv"
  [ "$(cat "$HOME/.config/org-backups/backup-dir")" = "$NEW" ]
}

@test "init.sh run again changes nothing" {
  sp init.sh "$NEW"
  echo "Client A,Partial,ClientA-Partial" >> "$NEW/orgs.csv"
  echo "DRIVE_DIR=$KS/My Drive/Org Backups" >> "$NEW/settings.env"
  before="$(snapshot)"
  sp init.sh "$NEW"
  [ "$status" -eq 0 ]
  [ "$(snapshot)" = "$before" ]
}

@test "init.sh on a folder with orgs.csv but no settings adds only what's missing" {
  mkdir -p "$NEW"
  printf 'project,org,alias\nClient A,Partial,ClientA-Partial\n' > "$NEW/orgs.csv"
  echo "/some/drive" > "$NEW/.drive-dir"
  sp init.sh "$NEW"
  [ "$status" -eq 0 ]
  [ "$(cat "$NEW/orgs.csv")" = "$(printf 'project,org,alias\nClient A,Partial,ClientA-Partial')" ]
  [ -f "$NEW/settings.env" ]
  [[ "$output" == *"set-drive.sh"* ]] || false
}

@test "set-drive.sh accepts a folder in the consultant's Kicksaw My Drive" {
  sp init.sh "$NEW"
  sp set-drive.sh --dir "$NEW" "$KS/My Drive/Org Backups"
  [ "$status" -eq 0 ]
  grep -qx "DRIVE_DIR=$KS/My Drive/Org Backups" "$NEW/settings.env"
  sp set-drive.sh --dir "$NEW" "$KS/My Drive/Org Backups/"
  grep -qx "DRIVE_DIR=$KS/My Drive/Org Backups" "$NEW/settings.env"
}

@test "set-drive.sh refuses another account, a shared drive and My Drive itself" {
  sp init.sh "$NEW"
  sp set-drive.sh --dir "$NEW" "$HOME/Library/CloudStorage/GoogleDrive-consultant@gmail.com/My Drive/x"
  [ "$status" -ne 0 ]; [[ "$output" == *"kicksaw.com"* ]] || false
  sp set-drive.sh --dir "$NEW" "$KS/Shared drives/x"
  [ "$status" -ne 0 ]; [[ "$output" == *"Shared drives"* ]] || false
  sp set-drive.sh --dir "$NEW" "$KS/My Drive"
  [ "$status" -ne 0 ]
  sp set-drive.sh --dir "$NEW" "$KS/My Drive/../Shared drives/x"
  [ "$status" -ne 0 ]
  sp set-drive.sh --dir "$NEW" "/tmp/x"
  [ "$status" -ne 0 ]
  grep -qx "DRIVE_DIR=" "$NEW/settings.env"
}

@test "set-drive.sh off clears the Drive folder" {
  sp init.sh "$NEW"
  sp set-drive.sh --dir "$NEW" "$KS/My Drive/Org Backups"
  sp set-drive.sh --dir "$NEW" off
  [ "$status" -eq 0 ]
  grep -qx "DRIVE_DIR=off" "$NEW/settings.env"
  run /bin/bash -c 'source "$1/lib/common.sh"; BACKUP_DIR="$2"; load_settings; echo "[$DRIVE_DIR] [$DRIVE_CHOICE]"' _ "$KIT" "$NEW"
  [ "$output" = "[] [off]" ]
}

@test "add-org.sh adds the line, objects.txt and project.conf" {
  sp init.sh "$NEW"
  sp add-org.sh --dir "$NEW" "Client A" Partial ClientA-Partial
  [ "$status" -eq 0 ]
  grep -qx "Client A,Partial,ClientA-Partial" "$NEW/orgs.csv"
  diff -q "$KIT/templates/objects.txt" "$NEW/Client A/objects.txt"
  grep -qx "drive=on" "$NEW/Client A/project.conf"
  run /bin/bash -c 'source "$1/lib/common.sh"; BACKUP_DIR="$2"; org_rows' _ "$KIT" "$NEW"
  [ "$output" = "Client A|Partial|ClientA-Partial" ]
}

@test "add-org.sh twice fails with already backed up, by pair or by alias" {
  sp init.sh "$NEW"
  sp add-org.sh --dir "$NEW" "Client A" Partial ClientA-Partial
  sp add-org.sh --dir "$NEW" "Client A" Partial ClientA-Prod
  [ "$status" -eq 1 ]; [[ "$output" == *"already backed up"* ]] || false
  sp add-org.sh --dir "$NEW" "Client A" Partial2 ClientA-Partial
  [ "$status" -eq 1 ]; [[ "$output" == *"already backed up"* ]] || false
  [ "$(grep -c '^Client A,' "$NEW/orgs.csv")" -eq 1 ]
}

@test "add-org.sh --no-drive writes drive=off and keeps an existing objects.txt" {
  sp init.sh "$NEW"
  mkdir -p "$NEW/Client A"; echo "Account" > "$NEW/Client A/objects.txt"
  sp add-org.sh --dir "$NEW" "Client A" Partial ClientA-Partial --no-drive
  [ "$status" -eq 0 ]
  grep -qx "drive=off" "$NEW/Client A/project.conf"
  [ "$(cat "$NEW/Client A/objects.txt")" = "Account" ]
}

@test "add-org.sh refuses an alias that isn't a login on this Mac" {
  sp init.sh "$NEW"
  sp add-org.sh --dir "$NEW" "Client A" UAT ClientA-UAT
  [ "$status" -eq 1 ]
  [[ "$output" == *"sf org login web --alias ClientA-UAT"* ]] || false
  if grep -q ClientA-UAT "$NEW/orgs.csv"; then false; fi
}

@test "add-org.sh refuses names that would break the folder layout" {
  sp init.sh "$NEW"
  for bad in "a/b" "a,b" ".hidden" "logs" "_setup"; do
    sp add-org.sh --dir "$NEW" "$bad" Partial ClientA-Partial
    [ "$status" -eq 2 ]
  done
  sp add-org.sh --dir "$NEW" "Client A" "x,y" ClientA-Partial
  [ "$status" -eq 2 ]
}

@test "remove-org.sh removes the line and leaves the org's folder and history" {
  sp init.sh "$NEW"
  sp add-org.sh --dir "$NEW" "Client A" Partial ClientA-Partial
  mkdir -p "$NEW/Client A/Partial/.git"
  sp remove-org.sh --dir "$NEW" "Client A" Partial
  [ "$status" -eq 0 ]
  if grep -q "ClientA-Partial" "$NEW/orgs.csv"; then false; fi
  [ -d "$NEW/Client A/Partial/.git" ]
  grep -qx "project,org,alias" "$NEW/orgs.csv"
}

@test "remove-org.sh of an org that isn't there fails" {
  sp init.sh "$NEW"
  sp remove-org.sh --dir "$NEW" "Client A" Partial
  [ "$status" -eq 1 ]
}

@test "add-org.sh refuses a project named Logs in any capitals, and a project that differs only in capitals" {
  sp init.sh "$NEW"
  sp add-org.sh --dir "$NEW" "Logs" Partial ClientA-Partial
  [ "$status" -eq 2 ]
  sp add-org.sh --dir "$NEW" "Client A" Partial ClientA-Partial
  [ "$status" -eq 0 ]
  sp add-org.sh --dir "$NEW" "client a" Prod ClientA-Prod
  [ "$status" -eq 2 ]
  [[ "$output" == *"Client A"* ]] || false
  sp add-org.sh --dir "$NEW" "Client A" partial ClientA-Prod
  [ "$status" -eq 1 ]
}

@test "set-drive.sh refuses a link in My Drive that leads to a personal Drive" {
  sp init.sh "$NEW"
  mkdir -p "$KS/My Drive" "$HOME/Library/CloudStorage/GoogleDrive-consultant@gmail.com/My Drive/x"
  ln -s "$HOME/Library/CloudStorage/GoogleDrive-consultant@gmail.com/My Drive/x" "$KS/My Drive/Backups"
  sp set-drive.sh --dir "$NEW" "$KS/My Drive/Backups"
  [ "$status" -ne 0 ]
  grep -qx "DRIVE_DIR=" "$NEW/settings.env"
}
