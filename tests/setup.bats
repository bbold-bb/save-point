#!/usr/bin/env bats

load helpers

# A fake bin folder with every dependency present; tests remove or change one.
setup() {
  setup_home
  FAKEBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKEBIN" "$HOME/Library/CloudStorage/GoogleDrive-consultant@kicksaw.com/My Drive"
  cp "$KIT/tests/fakes/sf" "$FAKEBIN/sf"
  fake node 'echo "${FAKE_NODE_VERSION:-v24.18.0}"'
  fake npm 'echo "npm $*" >> "$HOME/calls.log"'
  fake brew 'echo "brew $*" >> "$HOME/calls.log"'
  fake git 'echo "git version 2.50.1 (Apple Git-155)"'
  fake python3 '[ "$1" = --version ] && { echo "Python 3.9.6"; exit 0; }; exec /usr/bin/python3 "$@"'
  fake xcode-select '[ "$1" = "-p" ] && { echo /Library/Developer/CommandLineTools; exit 0; }; echo "xcode-select $*" >> "$HOME/calls.log"'
  export SAVE_POINT_PATH="$FAKEBIN:/usr/bin:/bin:/usr/sbin:/sbin"
  export FAKE_SF_CALLS="$HOME/calls.log"
}

fake() { printf '#!/bin/bash\n%s\n' "$2" > "$FAKEBIN/$1"; chmod +x "$FAKEBIN/$1"; }
check_json() { run /bin/bash "$KIT/bin/setup.sh" --check --json; }
item() { # name field -> value, from the last check_json output
  /usr/bin/python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); print([i for i in d["items"] if i["name"]==sys.argv[2]][0][sys.argv[3]])' "$output" "$1" "$2"
}

@test "everything present: every item ok, in order, exit 0" {
  check_json
  [ "$status" -eq 0 ]
  names="$(/usr/bin/python3 -I -c 'import json,sys; print(" ".join(i["name"] for i in json.loads(sys.argv[1])["items"]))' "$output")"
  [ "$names" = "xcode-clt homebrew node sf sfdx-hardis google-drive" ]
  for n in xcode-clt homebrew node sf sfdx-hardis google-drive; do [ "$(item "$n" status)" = ok ]; done
  [ "$(item node version)" = "24.18.0" ]
  [ "$(item sf version)" = "2.158.7" ]
  [ "$(item sfdx-hardis version)" = "8.30.0" ]
}

@test "node 18 is old" {
  FAKE_NODE_VERSION=v18.0.0 check_json
  [ "$(item node status)" = old ]
  [ "$(item node fix)" = "brew install node" ]
  [ "$status" -eq 1 ]
}

@test "no sf on PATH: sf and sfdx-hardis missing, with the npm fix" {
  rm "$FAKEBIN/sf"
  check_json
  [ "$(item sf status)" = missing ]
  [ "$(item sf fix)" = "npm install -g @salesforce/cli" ]
  [ "$(item sfdx-hardis status)" = missing ]
}

@test "sf plugins without sfdx-hardis: hardis missing" {
  FAKE_SF_PLUGINS="community 4.0.25" check_json
  [ "$(item sfdx-hardis status)" = missing ]
  [ "$(item sfdx-hardis fix)" = "sf plugins install sfdx-hardis" ]
}

@test "sfdx-hardis older than 8.24.0 is old, 8.24.0 is ok" {
  FAKE_SF_PLUGINS="sfdx-hardis 8.9.1" check_json
  [ "$(item sfdx-hardis status)" = old ]
  FAKE_SF_PLUGINS="sfdx-hardis 8.24.0" check_json
  [ "$(item sfdx-hardis status)" = ok ]
}

@test "Drive ok only when a GoogleDrive folder exists" {
  rm -rf "$HOME/Library/CloudStorage"
  check_json
  [ "$(item google-drive status)" = missing ]
  [[ "$(item google-drive fix)" == *"google.com/drive/download"* ]] || false
}

@test "no Homebrew is fine while Node is ok, and missing when Node is missing" {
  rm "$FAKEBIN/brew"
  check_json
  [ "$(item homebrew status)" = "not needed" ]
  rm "$FAKEBIN/node"
  check_json
  [ "$(item homebrew status)" = missing ]
  [ "$(item node status)" = missing ]
}

@test "no Command Line Tools: xcode-clt missing with the fix" {
  fake xcode-select 'exit 2'
  check_json
  [ "$(item xcode-clt status)" = missing ]
  [ "$(item xcode-clt fix)" = "xcode-select --install" ]
}

@test "plain check prints a table" {
  run /bin/bash "$KIT/bin/setup.sh" --check
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == ITEM*STATUS*VERSION* ]] || false
  [[ "$output" == *"sfdx-hardis"*"ok"*"8.30.0"* ]] || false
}

@test "--install sfdx-hardis allowlists the plugin and installs it unattended" {
  mkdir -p "$HOME/.config/sf"
  echo '["some-plugin"]' > "$HOME/.config/sf/unsignedPluginAllowList.json"
  run /bin/bash "$KIT/bin/setup.sh" --install sfdx-hardis < /dev/null
  [ "$status" -eq 0 ]
  grep -q "sf plugins install sfdx-hardis" "$HOME/calls.log"
  /usr/bin/python3 -I -c 'import json,sys; a=json.load(open(sys.argv[1])); assert a==["some-plugin","sfdx-hardis"], a' "$HOME/.config/sf/unsignedPluginAllowList.json"
  run /bin/bash "$KIT/bin/setup.sh" --install sfdx-hardis < /dev/null
  /usr/bin/python3 -I -c 'import json,sys; a=json.load(open(sys.argv[1])); assert a.count("sfdx-hardis")==1, a' "$HOME/.config/sf/unsignedPluginAllowList.json"
}

@test "--install sf runs npm and --install node runs brew" {
  rm "$FAKEBIN/sf"
  run /bin/bash "$KIT/bin/setup.sh" --install sf < /dev/null
  grep -qx "npm install -g @salesforce/cli" "$HOME/calls.log"
  [[ "$output" == *"npm install -g @salesforce/cli"* ]] || false
  run /bin/bash "$KIT/bin/setup.sh" --install node < /dev/null
  grep -qx "brew install node" "$HOME/calls.log"
}

@test "--install google-drive only points to the download page" {
  run /bin/bash "$KIT/bin/setup.sh" --install google-drive < /dev/null
  [ "$status" -eq 3 ]
  [[ "$output" == *"https://www.google.com/drive/download/"* ]] || false
}

@test "--install homebrew without a terminal gives the command for the consultant to run" {
  rm "$FAKEBIN/brew"
  run /bin/bash "$KIT/bin/setup.sh" --install homebrew < /dev/null
  [ "$status" -eq 3 ]
  [[ "$output" == *"raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"* ]] || false
  [[ "$output" == *"password"* ]] || false
}

@test "--install of an unknown item exits 2" {
  run /bin/bash "$KIT/bin/setup.sh" --install nope
  [ "$status" -eq 2 ]
}
