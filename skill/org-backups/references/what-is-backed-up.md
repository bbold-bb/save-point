# What is and isn't backed up

## Backed up

- **The org's metadata**, retrieved by sfdx-hardis (`sf hardis org monitor backup`) into `force-app/main/default/` in Salesforce DX source format: objects and fields, flows, Apex, Lightning components, layouts, pages, permission sets, profiles, reports, dashboards, email templates, settings, and the other types the Metadata API returns.
- **Profiles whole.** Hardis rereads each profile after the retrieve, so the file holds every permission the profile grants, not only the ones tied to retrieved components.
- **Standard objects' full settings** for every standard object listed in the project's `objects.txt`, and for any standard object Hardis left as an empty placeholder. Without this step, Hardis keeps a standard object's own settings only when it has a custom field.
- **The list of everything the org has**: `manifest/package-all-org-items.xml`, including what the backup leaves out. `manifest/package-backup-items.xml` is what was actually retrieved.
- **Installed packages**: `installedPackages/` has one file per package with its name, namespace and version.

Each backup that finds a change becomes a snapshot (a Git commit). Its message lists the changed components.

## Not backed up

- **Records**: no data at all. Users, permission set assignments, business hours, holidays, queues' members, Knowledge articles and other records aren't in the backup.
- **Managed package components**: anything with an installed package's namespace is left out. Reinstall the package to get them back; `installedPackages/` shows which version.
- **Some sensitive types** that Hardis skips by default. Compare the two manifests to see exactly what an org's backup left out.
- **Changes that are only noise**: a site's `.site` file and the data cleaning rules change on every retrieve with no change in the org. A snapshot isn't made for them alone; they're saved when anything else changes.

## Checking one component

To know whether an org has a component, look in `manifest/package-all-org-items.xml`, not in `force-app/`. A file can stay in `force-app/` after its component is deleted, and a component skipped by the backup has no file.

## Where the copies are

- **On the Mac**: `<backup folder>/<Project>/<Org>/`, the full history.
- **In Google Drive**: `<Drive folder>/<Project>/<Org>.bundle`, the same history in one file, rewritten only when the org changed. `<Drive folder>/_setup/` holds `orgs.csv`, `settings.env` and each project's objects list, enough to rebuild the backup folder on another Mac. A project with `drive=off` gets no new copy in Drive and is left out of `_setup/orgs.csv`. Copies made before it was turned off stay in Drive until they're removed.
- **Nowhere else.** No Git remote, no GitHub.
