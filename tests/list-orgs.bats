#!/usr/bin/env bats

load helpers

setup() {
  setup_home
  use_fakes
  make_backup_dir "Client A,Production,ClientA-Prod"
  export FAKE_SF_ORG_LIST="$BATS_TEST_TMPDIR/orgs.json"
  cat > "$FAKE_SF_ORG_LIST" <<'JSON'
{"status":0,"result":{
"other":[{"alias":"ClientA-Prod","username":"consultant@clienta.com","instanceUrl":"https://clienta.my.salesforce.com","isSandbox":false,"connectedStatus":"Connected","accessToken":"SECRET-TOKEN-1"}],
"sandboxes":[{"alias":"ClientB-UAT","username":"consultant@clientb.com.uat","instanceUrl":"https://clientb--uat.sandbox.my.salesforce.com","isSandbox":true,"connectedStatus":"Unable to refresh session due to: Error authenticating with the refresh token due to: expired access/refresh token","accessToken":"SECRET-TOKEN-2"},
 {"alias":"ClientC-Old","username":"consultant@clientc.com.old","instanceUrl":"https://clientc--old.sandbox.my.salesforce.com","isSandbox":true,"connectedStatus":"DomainNotFoundError","accessToken":"SECRET-TOKEN-3"}],
"nonScratchOrgs":[
 {"alias":"ClientA-Prod","username":"consultant@clienta.com","instanceUrl":"https://clienta.my.salesforce.com","isSandbox":false,"connectedStatus":"Connected","accessToken":"SECRET-TOKEN-1"},
 {"alias":"ClientB-UAT","username":"consultant@clientb.com.uat","instanceUrl":"https://clientb--uat.sandbox.my.salesforce.com","isSandbox":true,"connectedStatus":"Unable to refresh session due to: Error authenticating with the refresh token due to: expired access/refresh token","accessToken":"SECRET-TOKEN-2"},
 {"alias":"ClientC-Old","username":"consultant@clientc.com.old","instanceUrl":"https://clientc--old.sandbox.my.salesforce.com","isSandbox":true,"connectedStatus":"DomainNotFoundError","accessToken":"SECRET-TOKEN-3"}],
"scratchOrgs":[{"alias":"scratch1","username":"test-abc@example.com","instanceUrl":"https://x.scratch.my.salesforce.com","isSandbox":false,"isScratch":true,"accessToken":"SECRET-TOKEN-4","password":"hunter2"}]
}}
JSON
}

field() { # alias field -> value from the last JSON output
  /usr/bin/python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); print([o for o in d["orgs"] if o["alias"]==sys.argv[2]][0][sys.argv[3]])' "$output" "$1" "$2"
}

@test "JSON: one row per non-scratch login with kind, connected and backed_up" {
  run /bin/bash "$KIT/bin/list-orgs.sh" --dir "$BACKUP_DIR" --json
  [ "$status" -eq 0 ]
  count="$(/usr/bin/python3 -I -c 'import json,sys; print(len(json.loads(sys.argv[1])["orgs"]))' "$output")"
  [ "$count" -eq 3 ]
  [ "$(field ClientA-Prod kind)" = production ]
  [ "$(field ClientA-Prod connected)" = yes ]
  [ "$(field ClientA-Prod backed_up)" = "Client A/Production" ]
  [ "$(field ClientA-Prod username)" = "consultant@clienta.com" ]
  [ "$(field ClientA-Prod instance_url)" = "https://clienta.my.salesforce.com" ]
  [ "$(field ClientB-UAT kind)" = sandbox ]
  [ "$(field ClientB-UAT connected)" = expired ]
  [ "$(field ClientB-UAT backed_up)" = "" ]
  [ "$(field ClientC-Old connected)" = error ]
}

@test "no scratch orgs, and nothing from the login beyond the six fields" {
  run /bin/bash "$KIT/bin/list-orgs.sh" --dir "$BACKUP_DIR" --json
  [[ "$output" != *scratch1* ]] || false
  [[ "$output" != *SECRET* ]] || false
  [[ "$output" != *hunter2* ]] || false
  keys="$(/usr/bin/python3 -I -c 'import json,sys; print(" ".join(sorted(json.loads(sys.argv[1])["orgs"][0])))' "$output")"
  [ "$keys" = "alias backed_up connected instance_url kind username" ]
}

@test "plain output is a table" {
  run /bin/bash "$KIT/bin/list-orgs.sh" --dir "$BACKUP_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == ALIAS*USERNAME*KIND*CONNECTED*BACKED\ UP* ]] || false
  [[ "$output" == *"ClientA-Prod"*"production"*"yes"*"Client A/Production"* ]] || false
  [[ "$output" != *SECRET* ]] || false
}

@test "works with no backup folder set yet" {
  run /bin/bash "$KIT/bin/list-orgs.sh" --json
  [ "$status" -eq 0 ]
  [ "$(field ClientA-Prod backed_up)" = "" ]
}

@test "an alias backed up by username still shows as backed up" {
  make_backup_dir "Client B,UAT,consultant@clientb.com.uat"
  run /bin/bash "$KIT/bin/list-orgs.sh" --dir "$BACKUP_DIR" --json
  [ "$(field ClientB-UAT backed_up)" = "Client B/UAT" ]
}

@test "sf failing gives a plain error and exit 1" {
  echo 'not json' > "$FAKE_SF_ORG_LIST"
  run /bin/bash "$KIT/bin/list-orgs.sh" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not read the Salesforce CLI logins"* ]] || false
}
