# Troubleshooting

Start with `doctor.sh`. It checks everything below and gives a fix for each problem. Then read the day's log: `<backup folder>/logs/<date>.log` for the run, and `<backup folder>/logs/<date> <Project> <Org>.log` for one org's detail. Read the log's last lines and lines with `Error` first. Don't read whole logs into the conversation unless needed.

`run-history.csv` has one line per org per run: `started,finished,project,org,result,change,files,drive`.

| What you see | Why | Fix |
|---|---|---|
| `FAILED` for one org, `Hardis backup failed`, and the org's log says expired, refresh token, or `INVALID_SESSION_ID` | The org's login expired | The consultant runs `sf org login web --alias <alias>` (with `--instance-url` if it needs one). Then `backup-orgs.sh "<project>" "<org>"` |
| `FAILED` and `DomainNotFoundError` or the org can't be found | The sandbox was deleted, or refreshed and the login is stale | After a refresh, log in again with the same alias; the history carries on, and the first snapshot after the refresh shows how the refreshed org differs. If the org is gone, `remove-org.sh`; its history stays |
| Scheduled runs never start, or `schedule.sh show` says last exit code 126, or `launchd.log` says `Operation not permitted` | `/bin/bash` lacks Full Disk Access | System Settings, Privacy & Security, Full Disk Access: add `/bin/bash` (Cmd+Shift+G, type `/bin/bash`) and switch it on. Then `launchctl kickstart "gui/$(id -u)/com.kicksaw.org-backups"` and `schedule.sh show` |
| `partial` with drive `blocked`, and `macOS blocked this run from the Drive folder` in the log | The program that ran the backup lacks Full Disk Access (on the schedule, `/bin/bash`) | Add `/bin/bash` to Full Disk Access as above. For a run started by hand, the app that started it (Terminal, or the agent's app) needs it too |
| `partial` with drive `refused` | `settings.env` names a Drive folder that isn't in the consultant's Kicksaw My Drive (edited by hand, copied from another Mac, or a link leading elsewhere) | `set-drive.sh "<a folder in your Kicksaw My Drive>"` |
| `partial` with drive `failed`, and `Drive folder not found` in the log | Google Drive for desktop isn't running or isn't signed in | Open Google Drive. The bundle is written on the next run; nothing is lost, the Mac's copy is complete |
| `partial` with drive `up to date` or `written`, and `object settings: retrieve failed` | The org didn't return a standard object's full settings (often an object named in `objects.txt` that the org's API can't retrieve) | Read the org's log for the object named in the error. Remove it from `objects.txt` if it isn't needed. The rest of the backup is saved |
| `Another backup run is in progress` | A run is going | Wait for it. A lock left by a run that never finished (power loss, crash) is cleared by the next run, which logs `Clearing a lock`. `doctor.sh` shows a leftover lock |
| `skipped` for an org, with a name problem | The project or org name in `orgs.csv` can't be used as a folder (for example a project named `logs`, or a name with `/` or `"`) | Rename it in `orgs.csv` |
| `doctor.sh` warns a last run is more than 26 hours old | The Mac was off or asleep through both times, or the schedule isn't loaded | `schedule.sh show`. If it's not loaded, `schedule.sh install`. A missed run happens when the Mac wakes |
| `sfdx-hardis` missing or old after a CLI update | The Salesforce CLI was reinstalled without its plugins | `setup.sh --install sfdx-hardis` |
| A backup takes much longer than usual | A large org, or Salesforce is slow | Nothing to do. The Mac stays awake until the run ends |
| A change made in the org isn't in a snapshot | The backup ran before the change, or the component is a type the backup leaves out | Check the snapshot's time. See `what-is-backed-up.md` and the org's `manifest/package-all-org-items.xml` |
| `No backup folder set` | Setup hasn't been run, or the pointer file is gone | Run the setup wizard, or `init.sh "<existing backup folder>"`; it changes nothing in an existing folder |

## The agent's own shell and Google Drive

The agent's shell may be blocked from `~/Library/CloudStorage` even when the schedule isn't. Then `doctor.sh` warns it can't look in the Drive folder. Trust `run-history.csv`: a drive value of `written` or `up to date` means the scheduled runs reach Drive.
