"""Packaging invariants for generated Personal Team projects (run on macOS)."""
import copy
import importlib.util
import unittest
from pathlib import Path

APPLE = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("personal_team", APPLE / "scripts/prepare-personal-team.py")
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


class PersonalTeamTests(unittest.TestCase):
    def generated(self, watch):
        project, objects, root, target_id, target = helper.load_project(APPLE / "MetisApple.xcodeproj")
        return helper.prepare(project, objects, root, target_id, target, APPLE,
                              "TESTTEAM00", "test.metis.phone", include_watch=watch)

    def test_default_remains_iphone_only(self):
        project = self.generated(False)
        objects = project["objects"]
        root = objects[project["rootObject"]]
        self.assertEqual([objects[key]["name"] for key in root["targets"]], ["Metis"])
        self.assertFalse(any(obj.get("isa") == "PBXCopyFilesBuildPhase" for obj in objects.values()))

    def test_watch_companion_preserves_embed_graph_and_distinct_identifiers(self):
        project = self.generated(True)
        objects = project["objects"]
        targets = {objects[key]["name"]: objects[key] for key in objects[project["rootObject"]]["targets"]}
        self.assertEqual(set(targets), {"Metis", "MetisWatch", "MetisWatchExtension"})
        identifiers = set()
        for name, target in targets.items():
            configs = objects[target["buildConfigurationList"]]["buildConfigurations"]
            for key in configs:
                settings = objects[key]["buildSettings"]
                self.assertEqual(settings["CODE_SIGN_ENTITLEMENTS"], "")
                identifiers.add(settings["PRODUCT_BUNDLE_IDENTIFIER"])
            for key in target["dependencies"]:
                self.assertIn(objects[key]["target"], objects)
        self.assertEqual(identifiers, {"test.metis.phone", "test.metis.phone.watchkitapp",
                                      "test.metis.phone.watchkitapp.watchkitextension"})
        copies = [obj["name"] for obj in objects.values() if obj.get("isa") == "PBXCopyFilesBuildPhase"]
        self.assertCountEqual(copies, ["Embed Watch Content", "Embed Watch Extension"])
        self.assertEqual(targets["MetisWatch"]["productType"], "com.apple.product-type.application.watchapp2")
        self.assertEqual(targets["MetisWatchExtension"]["productType"], "com.apple.product-type.watchkit2-extension")


if __name__ == "__main__":
    unittest.main()
