#!/usr/bin/python3
"""Operator-managed immutable releases; build unprivileged, restart only the app."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import sqlite3
import stat
import subprocess
import sys
import time
import urllib.request
import uuid

from server import SAFE_ENV, trusted_path, validate_request


def run(command, **options):
    return subprocess.run(command, check=True, env=options.pop("env", SAFE_ENV), **options)


def git(source, *args):
    return subprocess.check_output(
        ["/usr/bin/git", "-c", "safe.directory=" + str(source), "-C", str(source), *args],
        text=True, env=SAFE_ENV).strip()


def load_config(filename):
    config = json.loads(trusted_path(filename).read_text())
    fields = {"repository", "releasesDir", "currentLink", "previousLink", "buildDir",
              "stateDir", "dataDir", "buildUser", "nodePath", "corepackPath",
              "overlayPatch", "appService", "preservedServices", "appUrl", "statusUrl",
              "protectedPaths"}
    if not isinstance(config, dict) or set(config) != fields:
        raise ValueError("Invalid immutable-release policy fields")
    if not re.fullmatch(r"https://[A-Za-z0-9./_-]+\.git", config["repository"]):
        raise ValueError("Use a public HTTPS source repository without credentials")
    user = pwd.getpwnam(config["buildUser"])
    if user.pw_uid == 0:
        raise ValueError("Release builds must use an unprivileged account")
    for field in ("releasesDir", "buildDir", "stateDir"):
        trusted_path(config[field], directory=True)
    for field in ("currentLink", "previousLink"):
        link = Path(config[field])
        trusted_path(str(link.parent), directory=True)
        if not link.is_symlink() or link.lstat().st_uid != 0:
            raise ValueError("Release pointers must be operator-owned symlinks")
        if link.resolve().parent != Path(config["releasesDir"]):
            raise ValueError("Release pointer escapes the configured release directory")
    for field in ("nodePath", "corepackPath", "overlayPatch"):
        trusted_path(config[field])
    trusted_path(str(Path(config["dataDir"]).parent), directory=True)
    if not Path(config["dataDir"]).is_dir() or Path(config["dataDir"]).is_symlink():
        raise ValueError("Invalid data directory")
    services = [config["appService"], *config["preservedServices"]]
    if len(set(services)) != len(services) or any(
            not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.@-]*\.service", name) for name in services):
        raise ValueError("Invalid or overlapping release services")
    if not config["preservedServices"]:
        raise ValueError("Declare the worker and gateway services to preserve")
    for url in (config["appUrl"], config["statusUrl"]):
        if not re.fullmatch(r"http://127\.0\.0\.1:[0-9]+/[^\s]*", url):
            raise ValueError("Release health checks must use the local app")
    for value in config["protectedPaths"]:
        if not isinstance(value, str) or not value.startswith("/") or any(c.isspace() for c in value):
            raise ValueError("Invalid protected build path")
    return config


def unit_pid(service):
    value = subprocess.check_output(
        ["/usr/bin/systemctl", "show", "--value", "--property=MainPID", service],
        text=True, env=SAFE_ENV).strip()
    if not value.isdigit() or int(value) == 0:
        raise ValueError("Required runtime service is not running: " + service)
    run(["/usr/bin/systemctl", "is-active", "--quiet", service])
    return int(value)


def health(config):
    try:
        with urllib.request.urlopen(config["appUrl"], timeout=3) as response:
            if response.status != 200:
                return False
        with urllib.request.urlopen(config["statusUrl"], timeout=3) as response:
            status = json.load(response)
            return response.status == 200 and status.get("worker", {}).get("ok") is True and status.get("mcp", {}).get("ok") is True
    except (OSError, ValueError):
        return False


def wait_healthy(config, attempts=60):
    for _ in range(attempts):
        if health(config):
            return True
        time.sleep(1)
    return False


def atomic_link(link, target):
    temporary = Path(str(link) + ".new")
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    os.replace(temporary, link)


def validate_release(release, releases_dir):
    release = Path(release)
    if release.resolve() != release or release.parent != Path(releases_dir):
        raise ValueError("Release escapes its configured directory")
    for entry in [release, *release.rglob("*")]:
        info = entry.lstat()
        if info.st_uid != 0 or (not entry.is_symlink() and info.st_mode & 0o022):
            raise ValueError("Release contains writable or non-operator-owned entries")
        if entry.is_symlink() and not entry.resolve().is_relative_to(release):
            raise ValueError("Release contains an external symlink")
    if not (release / ".next/BUILD_ID").read_text().strip():
        raise ValueError("Release has no build ID")
    return release


def activate(config, release, commit):
    release = validate_release(release, config["releasesDir"])
    current, previous = Path(config["currentLink"]), Path(config["previousLink"])
    old = current.resolve()
    preserved = {name: unit_pid(name) for name in config["preservedServices"]}
    # SQLite's online backup includes committed WAL contents without stopping a run.
    backup = Path(config["stateDir"]) / ("before-" + uuid.uuid4().hex + ".sqlite")
    with sqlite3.connect("file:" + str(Path(config["dataDir"]) / "chat.sqlite") + "?mode=ro", uri=True) as source:
        with sqlite3.connect(backup) as destination:
            source.backup(destination)
            if destination.execute("pragma integrity_check").fetchone()[0] != "ok":
                raise ValueError("Pre-update database backup failed")
    atomic_link(previous, old)
    atomic_link(current, release)
    try:
        run(["/usr/bin/systemctl", "restart", config["appService"]])
        if not wait_healthy(config):
            raise ValueError("New app release failed HTTP/worker/gateway health checks")
        if {name: unit_pid(name) for name in preserved} != preserved:
            raise ValueError("A preserved runtime service changed during activation")
    except BaseException:
        atomic_link(current, old)
        run(["/usr/bin/systemctl", "restart", config["appService"]])
        restored = wait_healthy(config)
        raise RuntimeError("Activation failed; previous app restored; health=" + str(restored))
    receipt = {"commit": commit, "release": str(release), "previous": str(old),
               "buildId": (release / ".next/BUILD_ID").read_text().strip(),
               "preservedPids": preserved, "backup": str(backup), "time": time.time()}
    with (Path(config["stateDir"]) / "releases.jsonl").open("a") as handle:
        handle.write(json.dumps(receipt) + "\n")
    print(json.dumps(receipt), flush=True)
    print("Metis AI installed successfully.", flush=True)
    return receipt


def copy_release(config, source, commit, overlay_hash):
    source = Path(source)
    manifest = json.loads((source / ".next/release-manifest.json").read_text())
    if manifest.get("commit") != commit or not (source / ".next/BUILD_ID").read_text().strip():
        raise ValueError("Built artifact does not match the approved source commit")
    destination = Path(config["releasesDir"]) / (commit + "-native-" + overlay_hash[:12])
    if destination.exists():
        raise ValueError("Release already exists; immutable releases are never overwritten")
    destination.mkdir(mode=0o700)
    # Copy only tracked source, never a checkout's .env, data, uploads, or logs.
    tracked = subprocess.check_output(
        ["/usr/bin/git", "-c", "safe.directory=" + str(source), "-C", str(source), "ls-files", "-z"], env=SAFE_ENV)
    for name in tracked.decode().split("\0"):
        if not name:
            continue
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts or relative.parts[0] in {".git", ".env", "node_modules", ".next", ".next-a", ".next-b"}:
            raise ValueError("Unsafe tracked source path")
        origin, target = source / relative, destination / relative
        if not origin.resolve().is_relative_to(source):
            raise ValueError("Source symlink escapes its checkout")
        target.parent.mkdir(parents=True, exist_ok=True)
        if origin.is_symlink():
            target.symlink_to(os.readlink(origin))
        else:
            shutil.copy2(origin, target)
    shutil.copytree((source / "node_modules").resolve(), destination / "node_modules", symlinks=True)
    shutil.copytree(source / ".next", destination / ".next", symlinks=True,
                    ignore=lambda directory, names: ["cache"] if Path(directory) == source / ".next" else [])
    (destination / ".next/cache").mkdir(exist_ok=True)
    (destination / ".release-source.json").write_text(json.dumps({"commit": commit, "overlaySha256": overlay_hash}) + "\n")
    for entry in [destination, *destination.rglob("*")]:
        os.chown(entry, 0, 0, follow_symlinks=False)
        if not entry.is_symlink():
            mode = entry.stat().st_mode
            os.chmod(entry, 0o755 if entry.is_dir() or mode & 0o111 else 0o644)
    return validate_release(destination, config["releasesDir"])


def build_source(filename):
    if os.geteuid() == 0:
        raise ValueError("Build subprocess must not run as root")
    config = json.loads(Path(filename).read_text())
    stage = Path(filename).parent
    source = stage / "source"
    environment = {**SAFE_ENV, "HOME": str(stage / "home"), "COREPACK_HOME": str(stage / "home/corepack"),
                   "PATH": str(stage / "bin") + ":" + str(Path(config["nodePath"]).parent) + ":" + SAFE_ENV["PATH"]}
    (stage / "home").mkdir(exist_ok=True)
    (stage / "bin").mkdir(exist_ok=True)
    run(["/usr/bin/git", "clone", "--filter=blob:none", "--no-checkout", config["repository"], str(source)], env=environment)
    run(["/usr/bin/git", "-C", str(source), "fetch", "origin", config["ref"]], env=environment)
    run(["/usr/bin/git", "-C", str(source), "checkout", "--detach", "FETCH_HEAD"], env=environment)
    commit = git(source, "rev-parse", "HEAD")
    if config["channel"] == "commits" and commit.lower() != config["ref"].lower():
        raise ValueError("Fetched commit differs from the approved target")
    patch = stage / "native.patch"
    if hashlib.sha256(patch.read_bytes()).hexdigest() != config["overlayHash"]:
        raise ValueError("Compatibility overlay changed")
    reverse = subprocess.run(["/usr/bin/git", "-C", str(source), "apply", "--reverse", "--check", str(patch)],
                             env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if reverse.returncode != 0:
        run(["/usr/bin/git", "-C", str(source), "apply", "--3way", "--index", str(patch)], env=environment)
    environment["METIS_RELEASE_COMMIT"] = commit
    if config["channel"] == "releases":
        environment["METIS_RELEASE_TAG"] = config["ref"]
    run([config["corepackPath"], "enable", "pnpm", "--install-directory", str(stage / "bin")], env=environment)
    pnpm = [config["corepackPath"], "pnpm"]
    run([*pnpm, "install", "--frozen-lockfile"], cwd=source, env=environment)
    run([*pnpm, "exec", "tsx", "--test", "tests/host-updater.test.ts", "tests/installer-update.test.ts",
         "tests/updater-stability.test.ts", "tests/update-job.test.ts"], cwd=source, env=environment)
    run(["/bin/bash", "scripts/build-production-slot.sh", ".next-a"], cwd=source,
        env={**environment, "AI_CHAT_ROOT": str(source), "PNPM_BIN": str(stage / "bin/pnpm")})
    os.replace(source / ".next-a", source / ".next")
    run([*pnpm, "typecheck"], cwd=source, env=environment)
    (stage / "result.json").write_text(json.dumps({"commit": commit, "overlayHash": config["overlayHash"]}) + "\n")


def prepare_build(config, request, overlay_hash):
    stage = Path(config["buildDir"]) / uuid.uuid4().hex
    stage.mkdir(mode=0o700)
    user = pwd.getpwnam(config["buildUser"])
    os.chown(stage, user.pw_uid, user.pw_gid)
    payload = {key: config[key] for key in ("repository", "nodePath", "corepackPath")}
    payload.update(channel=request["channel"], ref=request["ref"], overlayHash=overlay_hash)
    for name, data in (("build.json", json.dumps(payload).encode()),
                       ("native.patch", Path(config["overlayPatch"]).read_bytes())):
        target = stage / name
        target.write_bytes(data)
        os.chown(target, user.pw_uid, user.pw_gid)
        target.chmod(0o600)
    command = ["/usr/bin/systemd-run", "--unit=metis-release-build-" + uuid.uuid4().hex,
               "--wait", "--pipe", "--collect", "--property=User=" + config["buildUser"],
               "--property=WorkingDirectory=" + str(stage), "--property=UMask=0077",
               "--property=RuntimeMaxSec=45min", "--property=NoNewPrivileges=yes",
               "--property=PrivateTmp=yes", "--property=PrivateDevices=yes",
               "--property=ProtectSystem=strict", "--property=ProtectHome=yes",
               "--property=ReadWritePaths=" + str(stage)]
    if config["protectedPaths"]:
        command.append("--property=InaccessiblePaths=" + " ".join(config["protectedPaths"]))
    command += ["--", "/usr/bin/python3", str(Path(__file__).resolve()), "--build", str(stage / "build.json")]
    try:
        run(command)
        result = json.loads((stage / "result.json").read_text())
        if result["overlayHash"] != overlay_hash:
            raise ValueError("Built release used a different compatibility overlay")
        return stage / "source", result["commit"]
    except BaseException:
        shutil.rmtree(stage)
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--build")
    parser.add_argument("--prepared-source")
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--version")
    target.add_argument("--commit")
    args = parser.parse_args()
    if args.build:
        build_source(args.build)
        return
    if os.geteuid() != 0 or not args.config:
        raise SystemExit("An operator must invoke this fixed release command with its policy")
    os.umask(0o077)
    config = load_config(args.config)
    if args.check:
        print("Immutable release updater policy validated.")
        return
    request = validate_request({"action": "start", "jobId": str(uuid.uuid4()),
                                "channel": "releases" if args.version else "commits",
                                "ref": args.version or args.commit})
    with open("/run/lock/metis-release.lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        overlay_hash = hashlib.sha256(Path(config["overlayPatch"]).read_bytes()).hexdigest()
        if args.prepared_source:
            source = Path(args.prepared_source).resolve()
            commit = git(source, "rev-parse", "HEAD")
            if args.version or commit != args.commit or git(source, "status", "--porcelain"):
                raise ValueError("Prepared source must be clean at the exact approved commit")
        else:
            source, commit = prepare_build(config, request, overlay_hash)
        try:
            release = copy_release(config, source, commit, overlay_hash)
        finally:
            if not args.prepared_source:
                shutil.rmtree(source.parent)
        activate(config, release, commit)


if __name__ == "__main__":
    main()
