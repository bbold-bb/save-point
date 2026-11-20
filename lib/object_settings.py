"""Prints the standard objects whose full settings the backup should retrieve, space-separated.

    python3 -I object_settings.py <org folder> <objects.txt>

An object is listed when the org has it (manifest/package-all-org-items.xml) and either Hardis left an empty
placeholder file for it or the project's objects.txt names it. Managed package objects are left out.
Moved unchanged from the inline Python in the original backup-orgs.sh.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

backup, listfile = sys.argv[1], sys.argv[2]
ns = {"m": "http://soap.sforce.com/2006/04/metadata"}
root = ET.parse(os.path.join(backup, "manifest", "package-all-org-items.xml")).getroot()
in_org = set()
for t in root.findall("m:types", ns):
    if t.find("m:name", ns).text == "CustomObject":
        in_org = {m.text for m in t.findall("m:members", ns)}
wanted = set()
objects_dir = os.path.join(backup, "force-app", "main", "default", "objects")
if os.path.isdir(objects_dir):
    for name in os.listdir(objects_dir):
        f = os.path.join(objects_dir, name, name + ".object-meta.xml")
        if os.path.isfile(f):
            body = ET.parse(f).getroot()
            if len(body) == 0:          # Hardis wrote an empty placeholder
                wanted.add(name)
if os.path.isfile(listfile):
    for line in open(listfile, encoding="utf-8"):
        line = line.split("#")[0].strip()
        if line:
            wanted.add(line)
managed = re.compile(r"^[A-Za-z0-9]+__[A-Za-z0-9_]+__[a-z]+$")   # a namespaced (managed package) object
print(" ".join(sorted(o for o in wanted if o in in_org and not managed.match(o))))
