#!/bin/bash
# Save Point: checks and installs what the backups need.
#
#   setup.sh --check            a table: each item ok, old, missing or not needed, with its fix
#   setup.sh --check --json     the same as one JSON object, for the agent
#   setup.sh --install <item>   installs one item: xcode-clt, homebrew, node, sf, sfdx-hardis, google-drive
#
# --check exits 0 when nothing is missing or old. --install exits 0 when the item is now ok, 3 when the
# consultant has to finish it themselves (a dialog, a password, a download), 1 when it failed.
# The check uses the same PATH the scheduled backup uses, so "ok" here means ok for the schedule too.

set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
set_launchd_path

NODE_MIN=20
HARDIS_MIN=8.24.0
HOMEBREW_INSTALL='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
DRIVE_PAGE="https://www.google.com/drive/download/"
ITEMS="xcode-clt homebrew node sf sfdx-hardis google-drive"

# True when version $1 is at least $2 (both dotted numbers).
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

# check_<item> sets STATUS, VERSION and FIX.
check_xcode-clt() {
  FIX="xcode-select --install"; VERSION=""
  if xcode-select -p > /dev/null 2>&1 && git --version > /dev/null 2>&1 && python3 --version > /dev/null 2>&1; then
    STATUS=ok; VERSION="git $(git --version | awk '{print $3}'), python $(python3 --version 2>&1 | awk '{print $2}')"
  else
    STATUS=missing
  fi
}

check_homebrew() {
  FIX="$HOMEBREW_INSTALL"; VERSION=""
  if command -v brew > /dev/null 2>&1; then
    STATUS=ok; VERSION="$(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
  else
    # Homebrew is only how Node gets installed. With a good Node already there, it isn't needed.
    check_node
    if [ "$STATUS" = ok ]; then STATUS="not needed"; else STATUS=missing; fi
    VERSION=""; FIX="$HOMEBREW_INSTALL"
  fi
}

check_node() {
  FIX="brew install node"; VERSION=""
  if ! command -v node > /dev/null 2>&1; then STATUS=missing; return; fi
  VERSION="$(node --version 2>/dev/null | sed 's/^v//')"
  if version_ge "${VERSION:-0}" "$NODE_MIN"; then STATUS=ok; else STATUS=old; fi
}

check_sf() {
  FIX="npm install -g @salesforce/cli"; VERSION=""
  if ! command -v sf > /dev/null 2>&1; then STATUS=missing; return; fi
  VERSION="$(sf --version 2>/dev/null | sed -n 's#^@salesforce/cli/\([0-9.]*\).*#\1#p' | head -1)"
  if [ -n "$VERSION" ]; then STATUS=ok; else STATUS=missing; fi
}

check_sfdx-hardis() {
  FIX="sf plugins install sfdx-hardis"; VERSION=""
  if ! command -v sf > /dev/null 2>&1; then STATUS=missing; return; fi
  VERSION="$(sf plugins 2>/dev/null | awk '$1 == "sfdx-hardis" {print $2; exit}')"
  if [ -z "$VERSION" ]; then STATUS=missing
  elif version_ge "$VERSION" "$HARDIS_MIN"; then STATUS=ok
  else STATUS=old
  fi
}

check_google-drive() {
  FIX="Install Google Drive for desktop from $DRIVE_PAGE and sign in with your kicksaw.com account"; VERSION=""
  local found
  found="$(ls -d "$HOME"/Library/CloudStorage/GoogleDrive-* 2>/dev/null | sed 's#.*/GoogleDrive-##' | paste -sd ',' -)"
  if [ -n "$found" ]; then
    STATUS=ok; VERSION="$found"
  elif [ -d "/Applications/Google Drive.app" ] && [ -z "${SAVE_POINT_PATH:-}" ]; then
    # Installed, but this shell can't see the Drive folder (not signed in, or macOS privacy protection).
    STATUS=missing; FIX="Google Drive is installed but its folder isn't visible: open Google Drive and sign in with your kicksaw.com account"
  else
    STATUS=missing
  fi
}

json_str() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }

do_check() {
  local json="$1" bad=0 first=1 name
  if [ "$json" = 1 ]; then printf '{"items":['; else printf '%-14s %-11s %-30s %s\n' ITEM STATUS VERSION FIX; fi
  for name in $ITEMS; do
    "check_$name"
    case "$STATUS" in ok|"not needed") ;; *) bad=1 ;; esac
    if [ "$json" = 1 ]; then
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{"name":%s,"status":%s,"version":%s,"fix":%s}' "$(json_str "$name")" "$(json_str "$STATUS")" \
        "$(json_str "$VERSION")" "$(json_str "$FIX")"
    else
      local fix="$FIX"
      case "$STATUS" in ok|"not needed") fix="" ;; esac
      printf '%-14s %-11s %-30s %s\n' "$name" "$STATUS" "${VERSION:--}" "$fix"
    fi
  done
  [ "$json" = 1 ] && printf ']}\n'
  return "$bad"
}

run_cmd() { echo "Running: $*"; "$@"; }

# Adds sfdx-hardis to the Salesforce CLI's allowlist of unsigned plugins.
# sfdx-hardis is not signed with Salesforce's plugin signature (its npm package has no "sfdx" signing field), so
# `sf plugins install sfdx-hardis` stops to ask "This plugin is not digitally signed... continue?". Without a
# terminal that question can't be answered and the install is canceled. The CLI skips the question for plugins
# named in <sf config folder>/unsignedPluginAllowList.json (checked in @salesforce/plugin-trust,
# verifyInstallSignature hook), so the plugin is added there first. Other names in the file are kept.
allowlist_hardis() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/sf"
  mkdir -p "$dir"
  python3 -I - "$dir/unsignedPluginAllowList.json" <<'PY'
import json, os, sys
path = sys.argv[1]
names = []
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        names = json.load(f)
if "sfdx-hardis" not in names:
    names.append("sfdx-hardis")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(names, f)
PY
}

do_install() {
  local item="$1"
  case "$item" in
    xcode-clt)
      check_xcode-clt; [ "$STATUS" = ok ] && { echo "xcode-clt is already installed."; return 0; }
      run_cmd xcode-select --install
      echo "A macOS dialog opened: click Install, wait for it to finish, then check again."
      return 3 ;;
    homebrew)
      command -v brew > /dev/null 2>&1 && { echo "Homebrew is already installed."; return 0; }
      if [ -t 0 ]; then
        echo "Running: $HOMEBREW_INSTALL"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
      else
        echo "Homebrew's installer asks for your Mac password, so run it yourself in Terminal:"
        echo "  $HOMEBREW_INSTALL"
        echo "Then check again."
        return 3
      fi ;;
    node)
      command -v brew > /dev/null 2>&1 || { echo "Install Homebrew first: setup.sh --install homebrew"; return 1; }
      run_cmd brew install node || return 1 ;;
    sf)
      command -v npm > /dev/null 2>&1 || { echo "Install Node first: setup.sh --install node"; return 1; }
      run_cmd npm install -g @salesforce/cli || return 1 ;;
    sfdx-hardis)
      command -v sf > /dev/null 2>&1 || { echo "Install the Salesforce CLI first: setup.sh --install sf"; return 1; }
      allowlist_hardis || { echo "Could not update the Salesforce CLI's plugin allowlist."; return 1; }
      run_cmd sf plugins install sfdx-hardis < /dev/null || return 1 ;;
    google-drive)
      echo "Google Drive for desktop isn't installed by script. Download it from $DRIVE_PAGE,"
      echo "install it, and sign in with your kicksaw.com account. Then check again."
      return 3 ;;
    *)
      echo "Unknown item: $item. Items: $ITEMS" >&2; return 2 ;;
  esac
  hash -r
  "check_$item"
  if [ "$STATUS" = ok ]; then echo "$item: ok ${VERSION}"; return 0; fi
  echo "$item: still $STATUS after the install. Fix: $FIX"
  return 1
}

case "${1:-}" in
  --check)
    if [ "${2:-}" = "--json" ]; then do_check 1; else do_check 0; fi ;;
  --install)
    [ -n "${2:-}" ] || { echo "Usage: setup.sh --install <item>. Items: $ITEMS" >&2; exit 2; }
    do_install "$2" ;;
  *)
    echo "Usage: setup.sh --check [--json] | --install <item>" >&2; exit 2 ;;
esac
