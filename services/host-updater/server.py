#!/usr/bin/python3
"""A local, fixed-operation update broker. No caller-supplied command or paths."""
import argparse
import json
import os
from pathlib import Path
import pwd
import re
import signal
import socket
import socketserver
import stat
import struct
import subprocess
import sys
import time
import uuid


MAX_REQUEST = 4096
SAFE_ENV = {"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "LANG": "C.UTF-8"}


def trusted_path(value, directory=False):
    path = Path(value)
    if not path.is_absolute() or str(path.resolve(strict=True)) != str(path):
        raise ValueError("Updater paths must be absolute and contain no symlinks")
    for item in [path, *path.parents]:
        info = item.stat()
        if info.st_uid != 0 or info.st_mode & 0o022:
            raise ValueError("Updater policy, code and state must be root-owned and not group/world-writable")
    if directory and not path.is_dir():
        raise ValueError("Updater directory is missing")
    return path


def load_policy(filename):
    policy = json.loads(trusted_path(filename).read_text())
    required = {"serviceName", "allowedUser", "socketPath", "stateDir", "dataDir", "command", "environment"}
    if not isinstance(policy, dict) or set(policy) != required:
        raise ValueError("Invalid updater policy fields")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,100}", policy["serviceName"]):
        raise ValueError("Invalid updater service name")
    policy["allowedUid"] = pwd.getpwnam(policy["allowedUser"]).pw_uid
    trusted_path(policy["stateDir"], directory=True)
    socket_path = Path(policy["socketPath"])
    trusted_path(str(socket_path.parent), directory=True)
    if not socket_path.is_absolute() or len(str(socket_path).encode()) >= 104:
        raise ValueError("Invalid updater socket path")
    # The final data directory may belong to the app. Its parent must remain
    # root-controlled so the app cannot replace it with a different directory.
    data = Path(policy["dataDir"])
    trusted_path(str(data.parent), directory=True)
    info = data.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid not in {0, policy["allowedUid"]} or info.st_mode & 0o002:
        raise ValueError("Invalid updater data directory")
    command = policy["command"]
    if not isinstance(command, list) or not command or len(command) > 64 or any(not isinstance(v, str) or not v or "\0" in v for v in command):
        raise ValueError("Invalid fixed update command")
    trusted_path(command[0])
    if not os.access(command[0], os.X_OK):
        raise ValueError("Update command is not executable")
    # An interpreter must not elevate a script writable by the web process.
    for value in command[1:]:
        if value.startswith("/") and Path(value).is_file():
            trusted_path(value)
    environment = policy["environment"]
    if not isinstance(environment, dict) or not {"HOME", "USER", "PATH"} <= set(environment) or any(
        not re.fullmatch(r"[A-Z][A-Z0-9_]*", k) or not isinstance(v, str) or "\0" in v
        for k, v in environment.items()
    ):
        raise ValueError("Invalid updater environment")
    return policy


def validate_request(request):
    if not isinstance(request, dict):
        raise ValueError("Invalid update request")
    action = request.get("action")
    keys = {"action", "jobId", "channel", "ref"} if action == "start" else {"action", "jobId"}
    if action not in {"start", "status"} or set(request) - keys:
        raise ValueError("Invalid update request fields")
    job_id = request.get("jobId")
    if job_id is not None and (not isinstance(job_id, str) or str(uuid.UUID(job_id)) != job_id):
        raise ValueError("Invalid update job ID")
    if action == "start":
        ref, channel = request.get("ref"), request.get("channel")
        if not job_id or not isinstance(ref, str) or not (
            (channel == "releases" and re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?", ref))
            or (channel == "commits" and re.fullmatch(r"[0-9a-fA-F]{40}", ref))
        ):
            raise ValueError("Choose a verified release tag or full commit SHA")
    return request


def snapshot(policy, job):
    destination = Path(policy["stateDir"]) / "current.json"
    temporary = destination.with_suffix(".tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(job, handle)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, destination)


def current_job(policy):
    try:
        return json.loads((Path(policy["stateDir"]) / "current.json").read_text())
    except FileNotFoundError:
        return None


def open_log(policy):
    directory = os.open(policy["dataDir"], os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        flags = os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW | os.O_NONBLOCK
        created = False
        try:
            fd = os.open("metis-installer-update.log", flags | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=directory)
            created = True
        except FileExistsError:
            fd = os.open("metis-installer-update.log", flags, dir_fd=directory)
    finally:
        os.close(directory)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or (not created and info.st_uid != policy["allowedUid"]):
        os.close(fd)
        raise ValueError("Unsafe update log")
    os.fchown(fd, policy["allowedUid"], -1)
    os.fchmod(fd, 0o600)
    return os.fdopen(fd, "a", buffering=1)


class Updater:
    def __init__(self, policy, policy_file, runner_file, execute=subprocess.run):
        self.policy, self.policy_file, self.runner_file, self.execute = policy, policy_file, runner_file, execute

    def status(self, job_id=None):
        job = current_job(self.policy)
        if not job:
            if job_id:
                raise ValueError("Update job not found")
            return {"ok": True, "running": False}
        if job_id and job["jobId"] != job_id:
            raise ValueError("Update job not found")
        code = job.get("exitCode")
        running = code is None
        if running:
            result = self.execute(["/usr/bin/systemctl", "show", "--property=ActiveState", "--value",
                                   self.policy["serviceName"] + "-self-update.service"],
                                  capture_output=True, text=True, timeout=5, env=SAFE_ENV)
            state = result.stdout.strip()
            if result.returncode != 0:
                raise ValueError("Cannot read host updater service state")
            running = state in {"active", "activating", "deactivating"} or (job["phase"] == "queued" and time.time() - job["createdAt"] < 30)
            if not running:
                # A killed runner cannot write its final marker. Never report
                # success merely because the transient unit disappeared.
                code = 1
        return {"ok": True, "jobId": job["jobId"], "running": running, **({"exitCode": code} if code is not None else {})}

    def dispatch(self, request, peer_uid):
        if peer_uid != self.policy["allowedUid"]:
            raise ValueError("Host updater access denied")
        request = validate_request(request)
        if request["action"] == "status":
            return self.status(request.get("jobId"))
        previous = current_job(self.policy)
        if previous and previous["jobId"] == request["jobId"]:
            if any(previous[k] != request[k] for k in ("channel", "ref")):
                raise ValueError("Update job target cannot change")
            return self.status(previous["jobId"])
        if self.status()["running"]:
            raise ValueError("An installer update is already running")
        # Check the log before accepting a privileged job, without following any
        # app-controlled link or inheriting its environment.
        with open_log(self.policy):
            pass
        job = {k: request[k] for k in ("jobId", "channel", "ref")}
        job.update(phase="queued", createdAt=time.time())
        snapshot(self.policy, job)
        unit = self.policy["serviceName"] + "-self-update"
        try:
            self.execute(["/usr/bin/systemctl", "reset-failed", unit], capture_output=True, timeout=5, env=SAFE_ENV)
            result = self.execute([
                "/usr/bin/systemd-run", "--unit=" + unit, "--no-block", "--collect",
                "--description=Metis AI host update", "--property=UMask=0077", "--property=RuntimeMaxSec=51min",
                "--property=StandardOutput=null", "--property=StandardError=journal",
                "--", "/usr/bin/python3", self.runner_file, "--config", self.policy_file,
                "--run-job", job["jobId"],
            ], capture_output=True, text=True, timeout=30, env=SAFE_ENV)
            if result.returncode != 0:
                raise ValueError("The host updater could not start its systemd job")
        except Exception:
            job.update(phase="finished", exitCode=1)
            snapshot(self.policy, job)
            with open_log(self.policy) as handle:
                handle.write("[metis-update-job:" + job["jobId"] + "]\nHost updater failed to start.\n[metis-update-exit:1]\n")
            raise
        return {"ok": True, "jobId": job["jobId"], "running": True}


def run_job(policy, job_id):
    job = current_job(policy)
    if not job or job["jobId"] != job_id or job["phase"] != "queued":
        raise ValueError("Update job is not queued")
    validate_request({"action": "start", **{k: job[k] for k in ("jobId", "channel", "ref")}})
    with open_log(policy) as handle:
        job.update(phase="running")
        snapshot(policy, job)
        handle.write("[metis-update-job:" + job_id + "]\n[metis-update-pid:" + str(os.getpid()) + "]\n")
        command = [*policy["command"], "--version" if job["channel"] == "releases" else "--commit", job["ref"]]
        code = 1
        try:
            with subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=handle, stderr=handle,
                                  cwd="/", env={**SAFE_ENV, **policy["environment"]}, start_new_session=True) as child:
                try:
                    result = child.wait(timeout=50 * 60)
                    code = result if result >= 0 else 128 - result
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
                    handle.write("Host update timed out after 50 minutes.\n")
        except Exception:
            handle.write("Host update command failed.\n")
        finally:
            handle.write("\n[metis-update-exit:" + str(code) + "]\n")
            job.update(phase="finished", exitCode=code)
            snapshot(policy, job)
    return code


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        try:
            self.connection.settimeout(5)
            _, uid, _ = struct.unpack("3i", self.connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
            raw = self.rfile.readline(MAX_REQUEST + 1)
            if len(raw) > MAX_REQUEST or not raw.endswith(b"\n"):
                raise ValueError("Invalid update request size")
            response = self.server.updater.dispatch(json.loads(raw), uid)
        except Exception as error:
            response = {"ok": False, "error": str(error) if isinstance(error, ValueError) else "Host updater request failed"}
        self.wfile.write((json.dumps(response) + "\n").encode())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--run-job")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if os.getuid() != 0:
        raise SystemExit("The host updater must run under the operator's root service")
    policy = load_policy(args.config)
    runner = str(trusted_path(str(Path(__file__).resolve())))
    if args.check:
        print("Host updater policy validated.")
        return
    if args.run_job:
        raise SystemExit(run_job(policy, args.run_job))
    target = Path(policy["socketPath"])
    if target.exists():
        if not stat.S_ISSOCK(target.lstat().st_mode):
            raise ValueError("Updater socket path is occupied")
        target.unlink()
    with socketserver.UnixStreamServer(str(target), Handler) as server:
        server.updater = Updater(policy, str(Path(args.config).resolve()), runner)
        os.chown(target, policy["allowedUid"], -1)
        os.chmod(target, 0o600)
        server.serve_forever()


if __name__ == "__main__":
    main()
