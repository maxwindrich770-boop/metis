import importlib.util
import json
import os
import pwd
import subprocess
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

directory = Path(__file__).parents[1] / "services/host-updater"
sys.path.insert(0, str(directory))
spec = importlib.util.spec_from_file_location("immutable_release", directory / "release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="metis-release-")
        self.root = Path(self.temp.name)
        for name in ("releases/old/.next", "releases/new/.next", "state", "data"):
            (self.root / name).mkdir(parents=True)
        for name in ("old", "new"):
            (self.root / "releases" / name / ".next/BUILD_ID").write_text(name)
        self.old = self.root / "releases/old"
        self.new = self.root / "releases/new"
        (self.root / "current").symlink_to(self.old)
        (self.root / "previous").symlink_to(self.old)
        with sqlite3.connect(self.root / "data/chat.sqlite") as connection:
            connection.execute("create table preserved(value text)")
            connection.execute("insert into preserved values ('owner-data')")
        self.config = {"releasesDir": str(self.root / "releases"),
                       "currentLink": str(self.root / "current"), "previousLink": str(self.root / "previous"),
                       "stateDir": str(self.root / "state"), "dataDir": str(self.root / "data"),
                       "appService": "isolated-app.service",
                       "preservedServices": ["isolated-worker.service", "isolated-mcp.service"]}
        self.commands = []
        self.validate = patch.object(release, "validate_release", side_effect=lambda path, *_: path)
        self.validate.start()
        self.runner = patch.object(release, "run", side_effect=lambda command, **_: self.commands.append(command))
        self.run_mock = self.runner.start()
        self.pid = patch.object(release, "unit_pid", side_effect=lambda service: 101 if "worker" in service else 102)
        self.pid_mock = self.pid.start()

    def tearDown(self):
        patch.stopall()
        self.temp.cleanup()

    def test_success_preserves_worker_and_gateway_and_makes_consistent_database_backup(self):
        with patch.object(release, "wait_healthy", return_value=True):
            receipt = release.activate(self.config, self.new, "a" * 40)
        self.assertEqual((self.root / "current").resolve(), self.new)
        self.assertEqual((self.root / "previous").resolve(), self.old)
        self.assertEqual(self.commands, [["/usr/bin/systemctl", "restart", "isolated-app.service"]])
        self.assertEqual(receipt["preservedPids"], {"isolated-worker.service": 101, "isolated-mcp.service": 102})
        with sqlite3.connect(receipt["backup"]) as connection:
            self.assertEqual(connection.execute("select value from preserved").fetchone()[0], "owner-data")
        self.assertEqual(json.loads((self.root / "state/releases.jsonl").read_text())["release"], str(self.new))

    def test_failed_health_restores_previous_app_without_restarting_the_agent_runtime(self):
        with patch.object(release, "wait_healthy", side_effect=[False, True]):
            with self.assertRaisesRegex(RuntimeError, "previous app restored; health=True"):
                release.activate(self.config, self.new, "a" * 40)
        self.assertEqual((self.root / "current").resolve(), self.old)
        self.assertEqual(len(self.commands), 2)
        self.assertTrue(all(command == ["/usr/bin/systemctl", "restart", "isolated-app.service"] for command in self.commands))
        self.assertFalse((self.root / "state/releases.jsonl").exists())
        with sqlite3.connect(self.root / "data/chat.sqlite") as connection:
            self.assertEqual(connection.execute("select count(*) from preserved").fetchone()[0], 1)

    def test_runtime_pid_change_fails_and_restores_old_code(self):
        self.pid_mock.side_effect = [101, 102, 999, 102]
        with patch.object(release, "wait_healthy", return_value=True):
            with self.assertRaisesRegex(RuntimeError, "previous app restored"):
                release.activate(self.config, self.new, "a" * 40)
        self.assertEqual((self.root / "current").resolve(), self.old)

    def test_copy_refuses_build_manifest_for_another_commit_before_creating_a_release(self):
        (self.new / ".next/release-manifest.json").write_text(json.dumps({"commit": "b" * 40}))
        with self.assertRaisesRegex(ValueError, "does not match"):
            release.copy_release(self.config, self.new, "a" * 40, "c" * 64)
        self.assertEqual(sorted(p.name for p in (self.root / "releases").iterdir()), ["new", "old"])

    def test_existing_release_is_not_overwritten(self):
        (self.new / ".next/release-manifest.json").write_text(json.dumps({"commit": "a" * 40}))
        existing = self.root / "releases" / ("a" * 40 + "-native-" + "c" * 12)
        existing.mkdir()
        marker = existing / "keep"
        marker.write_text("immutable")
        with self.assertRaisesRegex(ValueError, "never overwritten"):
            release.copy_release(self.config, self.new, "a" * 40, "c" * 64)
        self.assertEqual(marker.read_text(), "immutable")

    def test_policy_rejects_root_builds_and_overlapping_service_identity(self):
        value = {key: "" for key in ("repository", "releasesDir", "currentLink", "previousLink",
                 "buildDir", "stateDir", "dataDir", "buildUser", "nodePath", "corepackPath",
                 "overlayPatch", "appService", "preservedServices", "appUrl", "statusUrl", "protectedPaths")}
        value.update(repository="https://example.org/metis.git", buildUser="root")
        filename = self.root / "policy"
        filename.write_text(json.dumps(value))
        with patch.object(release, "trusted_path", side_effect=lambda path, **_: Path(path)):
            with self.assertRaisesRegex(ValueError, "unprivileged"):
                release.load_config(str(filename))

    def test_real_release_validation_rejects_external_links_and_untrusted_entries(self):
        self.validate.stop()
        (self.new / "escape").symlink_to(self.root / "data")
        with self.assertRaises(ValueError):
            release.validate_release(self.new, self.config["releasesDir"])

    def test_failed_build_removes_only_its_temporary_source_tree(self):
        build_dir = self.root / "builds"
        build_dir.mkdir()
        overlay = self.root / "overlay.patch"
        overlay.write_text("reviewed patch")
        config = {"buildDir": str(build_dir), "buildUser": pwd.getpwuid(os.getuid()).pw_name,
                  "repository": "https://example.org/metis.git", "nodePath": "/usr/bin/node",
                  "corepackPath": "/usr/bin/corepack", "overlayPatch": str(overlay),
                  "protectedPaths": [str(self.root / "data")]}
        self.run_mock.side_effect = subprocess.CalledProcessError(1, ["isolated-build"])
        with self.assertRaises(subprocess.CalledProcessError):
            release.prepare_build(config, {"channel": "commits", "ref": "a" * 40}, "b" * 64)
        self.assertEqual(list(build_dir.iterdir()), [])
        self.assertTrue((self.root / "data/chat.sqlite").exists())

    def test_sandboxed_build_failure_cannot_reach_activation(self):
        with patch.object(release.os, "geteuid", return_value=0):
            with self.assertRaisesRegex(ValueError, "must not run as root"):
                release.build_source("unused")


if __name__ == "__main__":
    unittest.main()
