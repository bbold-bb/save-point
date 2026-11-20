---
name: org-backups
description: Save Point, scheduled metadata backups of Salesforce orgs on this Mac. Use when the user wants to set up org backups, add or remove an org from the backups, back up an org now (for example before a sandbox refresh), check backup status, health or run history, find out why a backup failed, or restore metadata (a component or a whole snapshot) from a backup.
---

# Save Point: org metadata backups

Save Point saves each Salesforce org's metadata into its own local Git history on this Mac, on a schedule, with a copy of that history in the consultant's own Kicksaw Google Drive. You set it up and run it by calling the kit's scripts. Every step that must be right is a script, so call the script rather than doing the step by hand.

## Find the kit

This skill folder is a link into the kit. The kit is two folders above this skill's real path:

```bash
KIT="$(cd "$(dirname "$(readlink -f "<path of this SKILL.md>")")/../.." && pwd)"
```

Scripts are in `$KIT/bin/`. Every script prints its usage at the top of the file; read it when unsure.

## Rules

- **Read-only on every org.** Never deploy, never run `sf project deploy`, never run DML, Apex, or anything that changes an org, even when asked. A restore ends with files on the Mac and the exact deploy command for the consultant to run themselves.
- **No passwords.** Never type, ask for, or handle a password, token, or verification code. Logins are `sf org login web`, finished by the consultant in the browser. Don't run `sf org list --json` or `sf org display --verbose` yourself: they show far more about each login than you need, and some Salesforce CLI versions have shown access tokens there. Use `list-orgs.sh`, which shows only alias, username, instance, kind and connection status.
- **Drive copies go only to the consultant's own Kicksaw My Drive.** `set-drive.sh` enforces it. Never suggest a personal Drive, a shared drive, or another place. A project whose contract keeps metadata off Kicksaw Drive gets `--no-drive`.
- **No Git remote** on any backup repo, and never push one anywhere.
- **Summaries before files.** Start from the scripts' output, commit messages, and `git show --stat`. Open whole metadata files only when the question needs them. Records are never in the backup.
- **Ask before installing anything** and before changing the schedule.
- Each backup repo holds an `AGENTS.md` written by sfdx-hardis. Parts of it describe Hardis's hosted CI setup (one branch per org, pipelines, Grafana), which Save Point doesn't use. Its notes on reading the manifests and the history are right; where it disagrees with this skill, follow this skill.

## First launch or day to day?

Run `"$KIT/bin/doctor.sh"`. If it says no backup folder is set, run the setup wizard. Otherwise do what was asked.

## Setup wizard

Six steps, in order. Each step calls a script and checks the result before moving on. When a step fails, stop, explain it in plain words, and say what to do. Don't skip ahead. Full detail for each step is in `references/setup.md`; read it before starting.

1. **Dependencies.** `setup.sh --check --json`. For each item not ok, say what it is and ask before `setup.sh --install <item>`. Homebrew and the Xcode Command Line Tools need the consultant (a password or a dialog); Google Drive for desktop is a download. Check again until every item is ok.
2. **Folders.** Ask where the backup folder goes (default `~/Org Backups`), then `init.sh "<folder>"`. Ask for the Drive folder (default `~/Library/CloudStorage/GoogleDrive-<them>@kicksaw.com/My Drive/Org Backups`), then `set-drive.sh "<folder>"`. If it's refused, explain why.
3. **Orgs.** `list-orgs.sh`. Show the logins and ask which orgs to back up and which project each belongs to. For an org not logged in, or expired, run `sf org login web --alias <alias>` (add `--instance-url <url>` for Government Cloud or a custom login domain) and let the consultant sign in. Ask whether each project's metadata may go to Kicksaw Drive. Then `add-org.sh "<project>" "<org>" "<alias>"`, with `--no-drive` where the answer was no.
4. **Standard objects.** For each new project, show `<Project>/objects.txt` and ask which standard objects the project uses. Edit the file to match.
5. **Schedule.** Ask for the times (default 03:00 and 18:00). `schedule.sh install --times HH:MM,HH:MM`. Walk the consultant through Full Disk Access for `/bin/bash` (steps in `references/setup.md`).
6. **First backup.** Start it as a scheduled run would: `launchctl kickstart "gui/$(id -u)/com.kicksaw.org-backups"`. It takes a few minutes per org. When it finishes, `schedule.sh show` (Full Disk Access ok?) and `backup-orgs.sh --status` (each org ok?). Then `doctor.sh`. Explain anything not ok. A run that writes to Drive (drive `written` or `up to date` in `run-history.csv`) shows the schedule can reach the protected folders; drive `blocked` means Full Disk Access is still missing.

## Day to day

| The consultant asks | Do |
|---|---|
| Is everything working? | `doctor.sh`, then explain each warn or fail with its fix |
| Back up now, or before a refresh | `backup-orgs.sh "<project>" "<org>"` (or a project, or nothing for all). Run it in the background; it can take several minutes |
| Status or history | `backup-orgs.sh --status`; `run-history.csv` in the backup folder; `git log` in the org's folder |
| What changed in an org | `git -C "<org folder>" log --format='%h %cd %s' --date=format:'%Y-%m-%d %H:%M'` then `git show --stat <snapshot>`; each snapshot's message lists the changed components |
| Add an org | Step 3 above for one org, then step 4 if the project is new |
| Remove an org | `remove-org.sh "<project>" "<org>"`. Its history stays; say so |
| Turn Drive off for a project | Set `drive=off` in `<Project>/project.conf`. Copies already in Drive stay until removed: ask the consultant before deleting `<Drive folder>/<Project>/` and `<Drive folder>/_setup/<Project> objects.txt`, then have them confirm in Drive. The next run takes the project out of `_setup/orgs.csv` |
| Change the times | `schedule.sh install --times HH:MM,HH:MM` |
| Why did a backup fail? | `references/troubleshooting.md`, the day's log in `logs/`, and `doctor.sh` |
| Restore | `references/restore.md` |
| What's in the backup? | `references/what-is-backed-up.md` |
| Update Save Point | `git -C "$KIT" pull`. The schedule uses the kit's script, so the next run uses the update |

The backup folder is in `~/.config/org-backups/backup-dir`. Every script also takes `--dir "<folder>"`.
