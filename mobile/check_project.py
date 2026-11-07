"""Portable project-wiring checks only; not a substitute for an iOS build."""

import pathlib
import plistlib
import re
import unittest
import xml.etree.ElementTree as ElementTree


MOBILE_DIRECTORY = pathlib.Path(__file__).resolve().parent
PROJECT_FILE = MOBILE_DIRECTORY / "ClickyMobile.xcodeproj/project.pbxproj"
PROJECT_TEXT = PROJECT_FILE.read_text()


class MobileProjectChecks(unittest.TestCase):
    def test_property_list_and_privacy_permissions(self):
        with (MOBILE_DIRECTORY / "ClickyMobile/Info.plist").open("rb") as plist_file:
            properties = plistlib.load(plist_file)
        for permission in ("NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"):
            self.assertTrue(properties[permission])
        self.assertNotIn("NSAllowsArbitraryLoads", properties)

    def test_every_swift_source_is_in_the_build_phase(self):
        source_files = sorted((MOBILE_DIRECTORY / "ClickyMobile").glob("*.swift"))
        self.assertEqual(len(source_files), 5)
        for source_file in source_files:
            reference_match = re.search(
                r"([A-F0-9]{24}) = \{isa = PBXFileReference;[^}]*path = "
                + re.escape(source_file.name)
                + r";",
                PROJECT_TEXT,
            )
            self.assertIsNotNone(reference_match, source_file.name)
            build_match = re.search(
                r"([A-F0-9]{24}) = \{isa = PBXBuildFile; fileRef = "
                + reference_match.group(1),
                PROJECT_TEXT,
            )
            self.assertIsNotNone(build_match, source_file.name)
            sources_phase = re.search(
                r"isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);",
                PROJECT_TEXT,
                re.DOTALL,
            ).group(1)
            self.assertIn(build_match.group(1), sources_phase)

    def test_project_object_references_are_defined(self):
        definitions = re.findall(r"^\s*([A-F0-9]{24}) = \{", PROJECT_TEXT, re.MULTILINE)
        # The target attributes dictionary repeats the target ID as a key.
        defined_identifiers = set(definitions)
        referenced_identifiers = set(re.findall(r"\b[A-F0-9]{24}\b", PROJECT_TEXT))
        self.assertEqual(defined_identifiers, referenced_identifiers)
        self.assertIn("IPHONEOS_DEPLOYMENT_TARGET = 17.0", PROJECT_TEXT)

    def test_shared_scheme_points_at_application_target(self):
        scheme = ElementTree.parse(
            MOBILE_DIRECTORY / "ClickyMobile.xcodeproj/xcshareddata/xcschemes/ClickyMobile.xcscheme"
        )
        references = scheme.findall(".//BuildableReference")
        self.assertEqual(len(references), 3)
        for reference in references:
            self.assertEqual(reference.attrib["BlueprintIdentifier"], "E00000000000000000000001")
            self.assertEqual(reference.attrib["BuildableName"], "ClickyMobile.app")


if __name__ == "__main__":
    unittest.main()
