# Restore

A restore ends on the Mac. You find the snapshot, copy the files out into a separate folder, and give the consultant the exact deploy command. **You never deploy, validate, or run any `sf project deploy` command yourself**, not even a dry run. The consultant runs it, the same way they'd make any other deploy.

Each org's backups are a Git repo at `<backup folder>/<Project>/<Org>/`. Each commit is one snapshot. Below, `ORG` is that folder.

## 1. Find the snapshot

List the snapshots, newest first:

```bash
git -C "$ORG" log --format='%h  %cd  %s' --date=format:'%Y-%m-%d %H:%M'
```

Each snapshot's message lists the components that changed in it. Show one:

```bash
git -C "$ORG" show --stat <snapshot>
```

Find when one component changed:

```bash
git -C "$ORG" log --format='%h  %cd' --date=format:'%Y-%m-%d %H:%M' -- "force-app/main/default/flows/My_Flow.flow-meta.xml"
```

A snapshot is the org's state when that backup ran, not who made a change or when during the day. Before saying a component exists or was deleted, check `manifest/package-all-org-items.xml` at that snapshot: it lists everything the org had (`git -C "$ORG" show <snapshot>:manifest/package-all-org-items.xml`). A file can stay in `force-app/` after its component is gone.

## 2. Look at a file in a snapshot

```bash
git -C "$ORG" show <snapshot>:force-app/main/default/flows/My_Flow.flow-meta.xml
git -C "$ORG" diff <older> <newer> -- force-app/main/default/flows/My_Flow.flow-meta.xml
```

## 3. Copy it out into a separate folder

Never change files in the backup folder. The next backup would commit the change. Make a separate copy at the snapshot. Pick a folder outside the backup folder, for example `~/Desktop/Restore <Org> <date>`:

```bash
git clone --quiet "$ORG" "<restore folder>"
git -C "<restore folder>" checkout --quiet <snapshot>
```

If the Mac's copy is gone (a new Mac, or a deleted folder), use the Drive copy instead. The bundle holds the org's whole history:

```bash
git clone --quiet "<Drive folder>/<Project>/<Org>.bundle" "<restore folder>"
git -C "<restore folder>" checkout --quiet <snapshot>
```

The restore folder is a Salesforce DX project (it has `sfdx-project.json`), so the consultant can deploy from it.

## 4. Give the consultant the deploy command

Name exactly the components to put back. Prefer a few files over a whole folder. Write the commands for them to run themselves, a validation first:

```bash
cd "<restore folder>"
sf project deploy start --source-dir "force-app/main/default/flows/My_Flow.flow-meta.xml" --target-org <alias> --dry-run
```

Then, when the validation is clean:

```bash
sf project deploy start --source-dir "force-app/main/default/flows/My_Flow.flow-meta.xml" --target-org <alias>
```

Tell them, in plain words:

- **Check the target org.** `--target-org` decides where it goes. A wrong alias overwrites another org.
- **Profiles are saved whole.** Deploying a profile file sets every permission in it. Put back the specific permission set or profile only when that's the intent.
- **Dependencies.** A component that references fields, objects or classes the org no longer has fails the validation. Restore those too, or remove the reference.
- **Deletions aren't undone by a deploy** of these files. A component created after the snapshot stays in the org.
- **Managed package components** aren't in the backup; reinstall the package. `installedPackages/` lists each package's name and version at that snapshot.
- **Records** (users, data, business hours, and so on) aren't in the backup at all.

## A whole snapshot

The same steps, with the whole `force-app` folder: `--source-dir force-app`. A whole-org deploy is large and risky. Recommend the consultant validate first, review the validation's errors, and deploy in parts.
