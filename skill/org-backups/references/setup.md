# Setup wizard: detail for each step

Work through the steps in order. Say what each step is for in one sentence before running it. After each script, read its output and exit code. Exit 0 means the step worked. Anything else means stop and explain.

## 1. Dependencies

Run `setup.sh --check --json`. Each item has `status` (`ok`, `old`, `missing`, or for Homebrew `not needed`) and a `fix`.

| Item | What it is | How it's installed |
|---|---|---|
| `xcode-clt` | Apple's Command Line Tools: Git and Python | `setup.sh --install xcode-clt` opens a macOS dialog. The consultant clicks Install and waits. Check again after |
| `homebrew` | Installs Node | Its installer asks for the Mac password, so the consultant runs it in Terminal themselves. `setup.sh --install homebrew` prints the command. Not needed when Node is already ok |
| `node` | Runs the Salesforce CLI (version 20 or later) | `setup.sh --install node` (Homebrew) |
| `sf` | The Salesforce CLI | `setup.sh --install sf` (npm) |
| `sfdx-hardis` | The plugin that does the backup (8.24.0 or later) | `setup.sh --install sfdx-hardis`. It isn't signed by Salesforce, so the script first adds it to the CLI's allowlist of unsigned plugins; that's expected |
| `google-drive` | Google Drive for desktop, signed in as the consultant's kicksaw.com account | The consultant downloads it from https://www.google.com/drive/download/ |

Ask before each install. Install in the table's order, since each needs the one above. When the check shows every item `ok` (or Homebrew `not needed`), move on.

## 2. Folders

**Backup folder.** Suggest `~/Org Backups`. Any folder works. One on the Desktop or in Documents also needs Full Disk Access (step 5), which is set up anyway. Run `init.sh "<folder>"`. It's safe to run on an existing folder: it only adds what's missing.

**Drive folder.** List the signed-in Drive accounts with `ls ~/Library/CloudStorage/`. Use the `GoogleDrive-<name>@kicksaw.com` one. Suggest `~/Library/CloudStorage/GoogleDrive-<name>@kicksaw.com/My Drive/Org Backups`. Run `set-drive.sh "<folder>"`. It refuses a personal account (client metadata stays in Kicksaw's Google Workspace) and shared drives (two consultants backing up the same org would overwrite each other's copy). If there's no kicksaw.com Drive account, go back to step 1's Drive item. If the consultant doesn't want a Drive copy at all, run `set-drive.sh off`. Their backups then stay on the Mac only, so say so.

If `ls` is refused with "Operation not permitted", this agent's shell isn't allowed in `~/Library/CloudStorage`. Ask the consultant for the exact folder path (Finder: right-click the folder, hold Option, choose Copy as Pathname).

## 3. Orgs

Run `list-orgs.sh`. It shows each login's alias, username, kind (production or sandbox), whether it's connected, and whether it's already backed up. Ask which to back up and the project name for each (the client's name, for example `Client A`). The org name is the folder for that org, for example `Partial`, `Full`, `Production`.

For an org that isn't logged in, or shows `expired`, run:

```bash
sf org login web --alias <alias>
```

Add `--instance-url https://<domain>.my.salesforce.com` (or the sandbox's URL) when the consultant says the org is on Government Cloud or uses a custom login domain, and `--instance-url https://test.salesforce.com` for a sandbox without one. The browser opens and the consultant signs in. Don't type anything into the browser. `connected: error` usually means a sandbox was deleted or refreshed away. Ask the consultant.

For each project, ask: "Can this client's metadata be copied to your Kicksaw Google Drive, or does the contract keep it off?" Then for each org:

```bash
add-org.sh "<project>" "<org>" "<alias>"            # Drive copy on
add-org.sh "<project>" "<org>" "<alias>" --no-drive # this project's backups stay on the Mac
```

## 4. Standard objects

Hardis backs up a standard object's full settings only when the object has a custom field. `objects.txt` names the standard objects whose settings are saved anyway. The default is Account, Contact, Case, Opportunity, Lead, Task, Event, User. Show the file and ask which standard objects the project uses (for example EmailMessage or CaseComment for Service Cloud). Edit `<backup folder>/<Project>/objects.txt`, one API name per line.

## 5. Schedule and Full Disk Access

Ask for the times. The default is 03:00 and 18:00, in the Mac's time zone. A run missed while the Mac is asleep happens when it wakes. Run `schedule.sh install --times 03:00,18:00`.

The schedule starts `/bin/bash`, and macOS blocks it from the Desktop, Documents and Google Drive until it has Full Disk Access. No script can grant it. Walk the consultant through it:

1. Open System Settings, then Privacy & Security, then Full Disk Access.
2. Click the + button at the bottom of the list. Touch ID or the Mac password may be asked for.
3. In the file window, press Cmd+Shift+G, type `/bin/bash`, press Return, then click Open.
4. Make sure the switch next to `bash` is on.

## 6. First backup

Start the first run the way the schedule does, so it also checks Full Disk Access:

```bash
launchctl kickstart "gui/$(id -u)/com.kicksaw.org-backups"
```

It runs in the background, a few minutes per org. The run is going while the folder `.lock` exists in the backup folder. When it's gone:

- `schedule.sh show`: `Full Disk Access: ok`. If it says missing, repeat step 5 and start the run again.
- The last lines of `run-history.csv`: drive `written` (or `up to date`) means the run reached Google Drive, which is the protected folder that proves Full Disk Access works. Drive `blocked` means it doesn't yet. Drive `off` (no Drive folder) can't prove it either way; then Full Disk Access matters only if the kit or the backup folder is on the Desktop or in Documents.
- `backup-orgs.sh --status`: each org `ok`. `partial` means the backup worked but a later step didn't (see `troubleshooting.md`).
- `doctor.sh`: everything ok.

Finish by telling the consultant: where the backups are, when they run, that they can ask for status, a backup now, or a restore at any time, and that the Drive copy is in the folder from step 2.
