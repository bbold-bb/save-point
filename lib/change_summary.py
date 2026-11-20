"""Turns `git diff --name-status` on stdin into a readable list of changed components for a snapshot's
description, for example "Modified  FlexiPage Case_Record_Page". A component with several files is listed once.
Moved unchanged from the inline Python in the original backup-orgs.sh.
"""
import sys
TYPES = {"applications": "CustomApplication", "approvalProcesses": "ApprovalProcess", "aura": "AuraDefinitionBundle",
  "classes": "ApexClass", "customMetadata": "CustomMetadata", "customPermissions": "CustomPermission",
  "email": "EmailTemplate", "flexipages": "FlexiPage", "flows": "Flow", "flowDefinitions": "FlowDefinition",
  "globalValueSets": "GlobalValueSet", "groups": "Group", "labels": "CustomLabels", "layouts": "Layout",
  "lwc": "LightningComponentBundle", "pages": "ApexPage", "permissionsetgroups": "PermissionSetGroup",
  "permissionsets": "PermissionSet", "profiles": "Profile", "queues": "Queue", "quickActions": "QuickAction",
  "reports": "Report", "reportTypes": "ReportType", "settings": "Settings", "sharingRules": "SharingRules",
  "standardValueSets": "StandardValueSet", "staticresources": "StaticResource", "tabs": "CustomTab",
  "triggers": "ApexTrigger", "workflows": "Workflow", "dashboards": "Dashboard",
  "cleanDataServices": "CleanDataService", "siteDotComSites": "SiteDotCom", "experiences": "ExperienceBundle",
  "messagingChannels": "MessagingChannel", "queueRoutingConfigs": "QueueRoutingConfig",
  "serviceChannels": "ServiceChannel", "entitlementProcesses": "EntitlementProcess", "objectTranslations":
  "CustomObjectTranslation", "documents": "Document", "networks": "Network", "notificationtypes":
  "CustomNotificationType", "assignmentRules": "AssignmentRules", "escalationRules": "EscalationRules",
  "autoResponseRules": "AutoResponseRules", "duplicateRules": "DuplicateRule", "matchingRules": "MatchingRules",
  "namedCredentials": "NamedCredential", "externalCredentials": "ExternalCredential",
  "EmbeddedServiceConfig": "EmbeddedServiceConfig", "presenceUserConfigs": "PresenceUserConfig"}
OBJECT_PARTS = {"fields": "CustomField", "listViews": "ListView", "recordTypes": "RecordType",
  "validationRules": "ValidationRule", "compactLayouts": "CompactLayout", "businessProcesses": "BusinessProcess",
  "webLinks": "WebLink", "fieldSets": "FieldSet"}
WORD = {"A": "Added", "M": "Modified", "D": "Deleted"}
seen, rows = set(), []
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 2:
        continue
    status, path = parts[0][0], parts[-1]
    prefix = "force-app/main/default/"
    if not path.startswith(prefix):
        continue
    bits = path[len(prefix):].split("/")
    folder = bits[0]
    if folder == "objects" and len(bits) >= 3:
        obj = bits[1]
        if len(bits) >= 4 and bits[2] in OBJECT_PARTS:
            kind, name = OBJECT_PARTS[bits[2]], obj + "." + bits[3].split(".")[0]
        else:
            kind, name = "CustomObject", obj
    elif folder in ("aura", "lwc") and len(bits) >= 2:
        kind, name = TYPES[folder], bits[1]
    else:
        kind = TYPES.get(folder, folder)
        name = "/".join(bits[1:]).replace("-meta.xml", "")
        if "." in name.split("/")[-1]:
            name = name.rsplit(".", 1)[0]
    key = (kind, name)
    if key in seen:
        continue
    seen.add(key)
    rows.append((WORD.get(status, status), kind, name))
rows.sort(key=lambda r: (r[1], r[2]))
print(f"{len(rows)} component(s) changed:")
for word, kind, name in rows[:300]:
    print(f"  {word:<9} {kind} {name}")
if len(rows) > 300:
    print(f"  ...and {len(rows) - 300} more (git show --stat lists every file)")
