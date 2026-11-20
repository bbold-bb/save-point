import os
import subprocess
import sys
import tempfile
import unittest

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(KIT, "lib")

MANIFEST = """<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Account</members>
        <members>Case</members>
        <members>acme__Widget__c</members>
        <name>CustomObject</name>
    </types>
    <version>67.0</version>
</Package>
"""

EMPTY_OBJECT = '<?xml version="1.0" encoding="UTF-8"?>\n<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata"/>\n'
FULL_OBJECT = '<?xml version="1.0" encoding="UTF-8"?>\n<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata"><label>X</label></CustomObject>\n'


def run(script, args, stdin=""):
    return subprocess.run([sys.executable, "-I", os.path.join(LIB, script)] + args,
                          input=stdin, capture_output=True, text=True)


class ObjectSettingsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.org = os.path.join(self.tmp.name, "Client A", "Partial")
        objects = os.path.join(self.org, "force-app", "main", "default", "objects")
        os.makedirs(os.path.join(self.org, "manifest"))
        with open(os.path.join(self.org, "manifest", "package-all-org-items.xml"), "w") as f:
            f.write(MANIFEST)
        for name, body in (("Account", EMPTY_OBJECT), ("Contact", EMPTY_OBJECT), ("Lead", FULL_OBJECT)):
            os.makedirs(os.path.join(objects, name))
            with open(os.path.join(objects, name, name + ".object-meta.xml"), "w") as f:
                f.write(body)
        self.listfile = os.path.join(self.tmp.name, "Client A", "objects.txt")
        with open(self.listfile, "w") as f:
            f.write("# comment\nCase  # inline comment\n\nacme__Widget__c\n")

    def tearDown(self):
        self.tmp.cleanup()

    def test_empty_placeholders_and_listed_objects_that_the_org_has(self):
        # Account: empty placeholder, in the org. Contact: empty but not in the org's manifest. Lead: full file.
        # Case: listed. acme__Widget__c: listed but managed.
        r = run("object_settings.py", [self.org, self.listfile])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), "Account Case")

    def test_missing_objects_txt_is_fine(self):
        r = run("object_settings.py", [self.org, os.path.join(self.tmp.name, "none.txt")])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), "Account")

    def test_missing_manifest_fails(self):
        os.remove(os.path.join(self.org, "manifest", "package-all-org-items.xml"))
        r = run("object_settings.py", [self.org, self.listfile])
        self.assertNotEqual(r.returncode, 0)


class ChangeSummaryTest(unittest.TestCase):
    def test_summary_lists_each_component_once_sorted_by_type(self):
        diff = ("M\tforce-app/main/default/objects/Case/fields/Status__c.field-meta.xml\n"
                "A\tforce-app/main/default/flexipages/Case_Record_Page.flexipage-meta.xml\n"
                "M\tforce-app/main/default/lwc/myCard/myCard.js\n"
                "M\tforce-app/main/default/lwc/myCard/myCard.html\n"
                "M\tmanifest/package-all-org-items.xml\n")
        r = run("change_summary.py", [], diff)
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = r.stdout.splitlines()
        self.assertEqual(lines[0], "3 component(s) changed:")
        self.assertEqual(lines[1], "  Modified  CustomField Case.Status__c")
        self.assertEqual(lines[2], "  Added     FlexiPage Case_Record_Page")
        self.assertEqual(lines[3], "  Modified  LightningComponentBundle myCard")

    def test_two_changes(self):
        diff = ("M\tforce-app/main/default/objects/Case/fields/Status__c.field-meta.xml\n"
                "A\tforce-app/main/default/flexipages/Case_Record_Page.flexipage-meta.xml\n")
        r = run("change_summary.py", [], diff)
        self.assertEqual(r.stdout.splitlines(), [
            "2 component(s) changed:",
            "  Modified  CustomField Case.Status__c",
            "  Added     FlexiPage Case_Record_Page",
        ])


if __name__ == "__main__":
    unittest.main()
