# Save Point shared library. Sourced by every script in bin/. Written for macOS /bin/bash 3.2.

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POINTER_FILE="$HOME/.config/org-backups/backup-dir"

kit_version() { cat "$KIT_DIR/VERSION"; }

die() { echo "$*" >&2; exit 2; }

# A path made absolute against the current folder, without needing it to exist yet. The schedule and every
# script cd around, so a relative backup folder would point somewhere else.
abs_path() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    '~/'*) printf '%s' "$HOME/${1#'~/'}" ;;
    *) printf '%s' "$PWD/${1#./}" ;;
  esac
}

# Sets BACKUP_DIR from --dir <path>, else from the pointer file that init.sh writes. The other arguments are
# left in REST_ARGS, in order. Callers then run:  set -- ${REST_ARGS[@]+"${REST_ARGS[@]}"}
backup_dir_from_args() {
  BACKUP_DIR=""
  REST_ARGS=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dir)
        [ -n "${2:-}" ] || die "--dir needs a folder path."
        BACKUP_DIR="$2"; shift 2 ;;
      --dir=*)
        BACKUP_DIR="${1#--dir=}"; shift ;;
      *)
        REST_ARGS+=("$1"); shift ;;
    esac
  done
  if [ -z "$BACKUP_DIR" ] && [ -s "$POINTER_FILE" ]; then
    BACKUP_DIR="$(head -1 "$POINTER_FILE")"
  fi
  [ -n "$BACKUP_DIR" ] || die "No backup folder set. Run init.sh <folder> first, or pass --dir <folder>."
  BACKUP_DIR="$(abs_path "${BACKUP_DIR%/}")"
}

# Reads settings.env as plain KEY=value lines. It is never sourced, so a value can't run anything.
load_settings() {
  local file="$BACKUP_DIR/settings.env" key value
  [ -f "$file" ] || die "Not a Save Point backup folder (no settings.env): $BACKUP_DIR. Run init.sh on it first."
  SETTINGS_KIT_DIR=""; DRIVE_DIR=""; DRIVE_CHOICE=""; SCHEDULE=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}"; value="${line#*=}"
    case "$key" in
      KIT_DIR) SETTINGS_KIT_DIR="$value" ;;
      DRIVE_DIR) DRIVE_DIR="$value" ;;
      SCHEDULE) SCHEDULE="$value" ;;
    esac
  done < "$file"
  # DRIVE_DIR=off: the consultant turned the Drive copy off on purpose (set-drive.sh off).
  if [ "$DRIVE_DIR" = "off" ]; then DRIVE_DIR=""; DRIVE_CHOICE="off"; fi
}

# Sets one KEY=value line in settings.env, replacing the old one and keeping every other line.
set_setting() {
  local key="$1" value="$2" file="$BACKUP_DIR/settings.env" tmp
  tmp="$(mktemp "$BACKUP_DIR/.settings.XXXXXX")"
  if [ -f "$file" ]; then
    grep -v "^$key=" "$file" > "$tmp" || true
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv -f "$tmp" "$file"
}

# Prints why a Drive folder isn't allowed, or nothing when it is. Only a folder inside the consultant's own
# Kicksaw My Drive: ~/Library/CloudStorage/GoogleDrive-<you>@kicksaw.com/My Drive/<folder>. When the folder
# exists, its real path (links followed) is checked too, so a link inside My Drive can't point elsewhere.
drive_dir_problem() {
  local path="$1" real
  if _drive_path_problem "$path" "$HOME"; then return 0; fi    # the path itself isn't allowed (printed why)
  [ -d "$path" ] || return 0
  real="$(cd "$path" 2>/dev/null && pwd -P)" || return 0
  if _drive_path_problem "$real" "$(cd "$HOME" && pwd -P)" > /dev/null; then
    echo "$path leads to $real, which isn't in your Kicksaw My Drive."
  fi
  return 0
}
_drive_path_problem() { # path home: prints the problem and returns 0, or returns 1 when the path is fine
  local path="$1" prefix="$2/Library/CloudStorage/GoogleDrive-" rest account inside domain
  while [ "${path%/}" != "$path" ]; do path="${path%/}"; done
  case "/$path/" in */./*|*/../*) echo "Use the folder's full path, without . or .. in it."; return 0 ;; esac
  case "$path" in
    "$prefix"*) ;;
    *) echo "The folder must be in Google Drive for desktop's folder, $2/Library/CloudStorage/GoogleDrive-<you>@kicksaw.com/My Drive/."; return 0 ;;
  esac
  rest="${path#"$prefix"}"
  account="${rest%%/*}"
  inside="${rest#*/}"
  [ "$inside" != "$rest" ] || inside=""
  domain="$(echo "${account##*@}" | tr 'A-Z' 'a-z')"
  [ "$domain" = "kicksaw.com" ] || { echo "$account is not a kicksaw.com account. Use your own Kicksaw Google Drive, signed in as you@kicksaw.com."; return 0; }
  case "$inside" in
    "Shared drives"|"Shared drives/"*) echo "Shared drives aren't allowed: two consultants backing up the same org would overwrite each other's copy. Use a folder in your My Drive."; return 0 ;;
    "My Drive") echo "Pick a folder inside My Drive, for example \"$prefix$account/My Drive/Org Backups\"."; return 0 ;;
    "My Drive/"*) return 1 ;;
    *) echo "The folder must be inside My Drive: $prefix$account/My Drive/<folder>."; return 0 ;;
  esac
}

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# Prints why a project or org name can't be used, or nothing when it's fine. Folder names on a Mac ignore
# capitals, so the reserved names are compared that way: a project "Logs" would share the logs/ folder.
name_problem() { # kind name
  local kind="$1" name="$2"
  case "$name" in
    '') echo "The $kind name is empty."; return ;;
    .*) echo "The $kind name \"$name\" can't start with a dot."; return ;;
    */*|*,*|*'|'*|*'"'*|*'\'*) echo "The $kind name \"$name\" can't contain / , | \" or \\."; return ;;
    *__*) echo "The $kind name \"$name\" can't contain two underscores in a row."; return ;;
  esac
  if [ "$kind" = project ]; then
    case "$(lower "$name")" in
      logs|_setup) echo "\"$name\" is a folder Save Point uses itself. Pick another project name."; return ;;
    esac
  fi
}

trim() {
  local s="$1"
  s="${s%$'\r'}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Rows of orgs.csv as project|org|alias, skipping comments, blank lines and the header line.
org_rows() {
  local file="$BACKUP_DIR/orgs.csv" header_seen="" project org alias
  [ -f "$file" ] || return 0
  while IFS=, read -r project org alias || [ -n "$project" ]; do
    project="$(trim "$project")"
    case "$project" in ''|'#'*) continue ;; esac
    if [ -z "$header_seen" ]; then header_seen=1; continue; fi
    echo "$project|$(trim "$org")|$(trim "$alias")"
  done < "$file"
}

# True unless <project>/project.conf turns the Drive copy off.
project_drive_on() {
  local conf="$BACKUP_DIR/$1/project.conf"
  [ -f "$conf" ] || return 0
  ! grep -qiE '^[[:space:]]*drive[[:space:]]*=[[:space:]]*off[[:space:]]*$' "$conf"
}

log() {
  mkdir -p "$BACKUP_DIR/logs"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$BACKUP_DIR/logs/$(date +%Y-%m-%d).log"
}

# launchd starts jobs with a bare PATH: add the Salesforce CLI (npm global), the newest nvm Node and Homebrew.
# SAVE_POINT_PATH replaces the whole list (the tests use it to put their fakes first).
set_launchd_path() {
  if [ -n "${SAVE_POINT_PATH:-}" ]; then
    export PATH="$SAVE_POINT_PATH"
    return 0
  fi
  local node_bin
  node_bin="$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V 2>/dev/null | tail -1)"
  export PATH="$HOME/.npm-global/bin:${node_bin:+$node_bin:}/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}
