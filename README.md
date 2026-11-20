# Save Point

Scheduled metadata backups of your Salesforce orgs, on your Mac. Each org's metadata is saved twice a day into its own local Git history, with a copy of that history in your Kicksaw Google Drive. Read-only on every org.

Save Point is a set of scripts plus one agent skill (`org-backups`) that works in Claude Code and Codex. The skill walks you through setup and handles the day-to-day jobs. The scripts also work on their own from the Terminal.

## Get started

```bash
git clone https://github.com/bbold-bb/save-point.git "$HOME/Save Point"
```

```bash
"$HOME/Save Point/bin/install-skill.sh"
```

Then open Claude Code or Codex and say "set up org backups".

## Two folders

- **The kit** (this repo): scripts, the skill and these docs. Update it with `git pull`. The schedule runs the kit's own script, so an update takes effect on the next run.
- **Your backup folder** (default `~/Org Backups`): `orgs.csv`, each `<Project>/objects.txt`, each `<Project>/<Org>/` backup repo, `run-history.csv`, `logs/`, `.status/` and `settings.env`. A kit update never touches it.

## Scripts

| Script | Job |
|---|---|
| `bin/setup.sh --check [--json]` | Lists each dependency as ok, old or missing, with the fix |
| `bin/setup.sh --install <item>` | Installs one missing dependency |
| `bin/list-orgs.sh [--json]` | Lists your Salesforce CLI logins and which ones are backed up |
| `bin/init.sh <folder>` | Creates the backup folder |
| `bin/set-drive.sh <folder>\|off` | Sets the Drive folder for the copies (your Kicksaw My Drive only) |
| `bin/add-org.sh <project> <org> <alias> [--no-drive]` | Adds an org |
| `bin/remove-org.sh <project> <org>` | Stops backing up an org (its history stays) |
| `bin/schedule.sh install [--times 03:00,18:00] \| remove \| show` | Manages the schedule |
| `bin/backup-orgs.sh [<project> [<org>]]` | Runs a backup now |
| `bin/backup-orgs.sh --status` | When each org last backed up, and whether it worked |
| `bin/doctor.sh` | One health check of everything |
| `bin/install-skill.sh` | Links the skill into Claude Code and Codex |

Every script that works on the backup folder takes `--dir <folder>`; without it, it uses the folder `init.sh` set up.

## Rules

- Read-only on every org. Save Point never deploys. A restore gives you the files and the deploy command; the deploy is yours.
- No passwords. Logins are browser logins (`sf org login web`).
- Drive copies go only to your own Kicksaw My Drive, never a personal Drive or a shared drive. A project can turn its Drive copy off.
- Backup repos never get a Git remote.
- Metadata only: no records.

## Development

Tests use bats-core (`brew install bats-core`) and Python's unittest:

```bash
bats tests && python3 -m unittest discover -s tests -p 'test_*.py'
```
