import importlib.util
import json
import os
from pathlib import Path
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("host_updater", Path(__file__).parents[1] / "services/host-updater/server.py")
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class HostUpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="metis-host-update-")
        self.root = Path(self.temp.name)
        self.data = self.root / "data"
        self.state = self.root / "state"
        self.data.mkdir()
        self.state.mkdir()
        self.policy = {"allowedUid": os.getuid(), "serviceName": "isolated-test", "dataDir": str(self.data),
                       "stateDir": str(self.state), "command": ["/usr/bin/python3", "-c", "import sys; print('Metis AI installed successfully.'); print(repr(sys.argv))"],
                       "environment": {"HOME": self.temp.name, "USER": "test", "PATH": "/usr/bin:/bin"}}
        self.commands = []
        self.active = "active"
        self.fail_start = False
        def execute(args, **kwargs):
            self.commands.append((args, kwargs))
            output = self.active + "\n" if "show" in args else ""
            code = 1 if self.fail_start and args[0].endswith("systemd-run") else 0
            return subprocess.CompletedProcess(args, code, stdout=output, stderr="")
        self.broker = updater.Updater(self.policy, "/etc/test-policy.json", "/usr/local/libexec/test-updater.py", execute)
        self.request = {"action": "start", "jobId": str(uuid.uuid4()), "channel": "releases", "ref": "v1.2.3"}

    def tearDown(self):
        self.temp.cleanup()

    def start(self):
        return self.broker.dispatch(self.request, os.getuid())

    def test_peer_and_payload_cannot_inject_command_paths_environment_or_flags(self):
        for payload in [
            {**self.request, "command": "/bin/sh"}, {**self.request, "root": "/"},
            {**self.request, "environment": {"LD_PRELOAD": "/tmp/a"}},
            {**self.request, "ref": "v1.2.3; touch /tmp/unwanted"},
            {**self.request, "ref": "--help"}, {**self.request, "jobId": "../escape"},
            {**self.request, "channel": "commits", "ref": "abcdef1"},
            {"action": "exec"}, [], None,
        ]:
            with self.subTest(payload=payload), self.assertRaises((ValueError, AttributeError)):
                self.broker.dispatch(payload, os.getuid())
        with self.assertRaisesRegex(ValueError, "access denied"):
            self.broker.dispatch(self.request, os.getuid() + 1)
        self.assertEqual(self.commands, [])
        self.assertFalse((self.state / "current.json").exists())

    def test_accepts_full_commit_and_only_starts_fixed_transient_runner(self):
        self.request.update(channel="commits", ref="a" * 40)
        result = self.start()
        self.assertTrue(result["running"])
        args, options = self.commands[-1]
        self.assertEqual(args[:2], ["/usr/bin/systemd-run", "--unit=isolated-test-self-update"])
        self.assertEqual(args[-3:], ["/etc/test-policy.json", "--run-job", self.request["jobId"]])
        self.assertNotIn(self.request["ref"], args)
        self.assertEqual(options["env"], updater.SAFE_ENV)
        self.assertEqual(updater.current_job(self.policy)["ref"], "a" * 40)

    def test_duplicate_start_is_idempotent_and_new_jobs_are_blocked(self):
        self.start()
        self.start()
        with self.assertRaisesRegex(ValueError, "already running"):
            self.broker.dispatch({**self.request, "jobId": str(uuid.uuid4())}, os.getuid())
        with self.assertRaisesRegex(ValueError, "cannot change"):
            self.broker.dispatch({**self.request, "ref": "v2.0.0"}, os.getuid())
        starts = [args for args, _ in self.commands if args[0].endswith("systemd-run")]
        self.assertEqual(len(starts), 1)

    def test_failed_launch_is_durable_and_can_be_retried_with_a_new_job(self):
        self.fail_start = True
        with self.assertRaisesRegex(ValueError, "could not start"):
            self.start()
        self.assertEqual(self.broker.status()["exitCode"], 1)
        self.assertIn("[metis-update-exit:1]", (self.data / "metis-installer-update.log").read_text())
        self.fail_start = False
        self.request["jobId"] = str(uuid.uuid4())
        self.assertTrue(self.start()["running"])

    def test_runner_records_exact_exit_and_status_survives_broker_recreation(self):
        self.start()
        code = updater.run_job(self.policy, self.request["jobId"])
        self.assertEqual(code, 0)
        status = self.broker.status(self.request["jobId"])
        self.assertFalse(status["running"])
        self.assertEqual(status["exitCode"], 0)
        log = (self.data / "metis-installer-update.log").read_text()
        self.assertIn("[metis-update-job:" + self.request["jobId"] + "]", log)
        self.assertIn("Metis AI installed successfully.", log)
        self.assertIn("'--version', 'v1.2.3'", log)
        self.assertIn("[metis-update-exit:0]", log)
        recreated = updater.Updater(self.policy, "policy", "runner", lambda *_a, **_kw: self.fail("Completed jobs must not query systemd"))
        self.assertEqual(recreated.status()["exitCode"], 0)

    def test_runner_failure_and_dead_unit_never_become_success(self):
        self.policy["command"] = ["/usr/bin/python3", "-c", "import sys; print('compiler error'); sys.exit(23)"]
        self.start()
        self.assertEqual(updater.run_job(self.policy, self.request["jobId"]), 23)
        self.assertEqual(self.broker.status()["exitCode"], 23)
        self.assertIn("[metis-update-exit:23]", (self.data / "metis-installer-update.log").read_text())
        job = updater.current_job(self.policy)
        job.pop("exitCode")
        job.update(phase="running", createdAt=time.time() - 60)
        updater.snapshot(self.policy, job)
        self.active = "inactive"
        self.assertEqual(self.broker.status()["exitCode"], 1)

    def test_log_rejects_symlinks_hardlinks_and_special_files(self):
        target = self.root / "unrelated"
        target.write_text("preserve")
        log = self.data / "metis-installer-update.log"
        log.symlink_to(target)
        with self.assertRaises(OSError):
            self.start()
        log.unlink()
        os.link(target, log)
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            self.start()
        log.unlink()
        os.mkfifo(log)
        with self.assertRaises((OSError, ValueError)):
            self.start()
        self.assertEqual(target.read_text(), "preserve")
        self.assertEqual(self.commands, [])

    def test_existing_root_owned_file_cannot_be_relabelled_as_an_app_log(self):
        log = self.data / "metis-installer-update.log"
        log.write_text("private")
        self.policy["allowedUid"] = os.getuid() + 1
        info = type("Info", (), {"st_mode": 0o100600, "st_nlink": 1, "st_uid": 0})()
        with patch.object(updater.os, "fstat", return_value=info), patch.object(updater.os, "fchown") as chown:
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                updater.open_log(self.policy)
            chown.assert_not_called()
        self.assertEqual(log.read_text(), "private")

    def test_untrusted_policy_parent_is_rejected(self):
        policy = self.root / "policy.json"
        policy.write_text("{}")
        with self.assertRaises(ValueError):
            updater.load_policy(str(policy))
        alias = self.root / "alias"
        alias.symlink_to(policy)
        with self.assertRaises(ValueError):
            updater.load_policy(str(alias))

    def test_real_unix_socket_uses_peer_identity_and_bounded_protocol(self):
        target = self.root / "test.sock"
        with socketserver.UnixStreamServer(str(target), updater.Handler) as server:
            server.updater = self.broker
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            def call(raw):
                with socket.socket(socket.AF_UNIX) as connection:
                    connection.settimeout(3)
                    connection.connect(str(target))
                    connection.sendall(raw)
                    return json.loads(connection.recv(4096))
            try:
                result = call((json.dumps(self.request) + "\n").encode())
                self.assertTrue(result["ok"])
                self.policy["allowedUid"] += 1
                denied = call(b'{"action":"status"}\n')
                self.assertFalse(denied["ok"])
                self.policy["allowedUid"] -= 1
                invalid = call(b"x" * 4100 + b"\n")
                self.assertFalse(invalid["ok"])
            finally:
                server.shutdown()
                thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
