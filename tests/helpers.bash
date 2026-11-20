# Shared test setup. Every test gets its own HOME, backup folder and Drive folder under BATS_TEST_TMPDIR.

KIT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup_home() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

# A backup folder with settings.env and orgs.csv. Project "Client A", one org Partial unless rows are given:
#   make_backup_dir "Client A,Partial,ClientA-Partial" "Client A,Full,ClientA-Full"
make_backup_dir() {
  BACKUP_DIR="$BATS_TEST_TMPDIR/Org Backups"
  DRIVE_DIR="$BATS_TEST_TMPDIR/home/Library/CloudStorage/GoogleDrive-consultant@kicksaw.com/My Drive/Org Backups"
  mkdir -p "$BACKUP_DIR/logs" "$BACKUP_DIR/.status" "$DRIVE_DIR"
  {
    echo "KIT_DIR=$KIT"
    echo "DRIVE_DIR=$DRIVE_DIR"
    echo "SCHEDULE=03:00,18:00"
  } > "$BACKUP_DIR/settings.env"
  {
    echo "# Orgs backed up by Save Point."
    echo "project,org,alias"
    if [ "$#" -eq 0 ]; then
      echo "Client A,Partial,ClientA-Partial"
    else
      for row in "$@"; do echo "$row"; done
    fi
  } > "$BACKUP_DIR/orgs.csv"
  export BACKUP_DIR DRIVE_DIR
}

# Fakes first on PATH, and the same PATH inside the scripts (set_launchd_path honors SAVE_POINT_PATH).
use_fakes() {
  export SAVE_POINT_PATH="$KIT/tests/fakes:/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH="$SAVE_POINT_PATH"
  export FAKE_SF_CALLS="$BATS_TEST_TMPDIR/sf-calls.log"
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
}
