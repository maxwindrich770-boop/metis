#!/usr/bin/env python3
"""Reject signed iPhone/Watch bundles not provisioned for their actual devices."""
import argparse
import datetime as dt
import fnmatch
import json
import plistlib
import subprocess
from pathlib import Path


def profile_errors(profile, identifier, device, team, now):
    errors = []
    if not profile.get("ProvisionsAllDevices") and device not in profile.get("ProvisionedDevices", []):
        errors.append("PROFILE_MISSING_DEVICE")
    expires = profile.get("ExpirationDate")
    if expires is None or expires.replace(tzinfo=dt.timezone.utc) <= now:
        errors.append("PROFILE_EXPIRED")
    entitlements = profile.get("Entitlements", {})
    pattern = entitlements.get("application-identifier", "")
    if not fnmatch.fnmatchcase(team + "." + identifier, pattern):
        errors.append("PROFILE_WRONG_APP")
    if entitlements.get("com.apple.developer.team-identifier") != team:
        errors.append("PROFILE_WRONG_TEAM")
    return errors


def inspect(app, phone_device, watch_device):
    errors = []
    info = lambda bundle: plistlib.loads((bundle / "Info.plist").read_bytes())
    phone = info(app)
    watch = app / "Watch/MetisWatch.app"
    wi = info(watch)
    extensions = list((watch / "PlugIns").glob("*.appex"))
    if len(extensions) != 1:
        return ["WATCH_EXTENSION_COUNT"]
    extension = extensions[0]
    ei = info(extension)
    if wi.get("WKCompanionAppBundleIdentifier") != phone["CFBundleIdentifier"]:
        errors.append("WATCH_COMPANION_MISMATCH")
    if ei.get("NSExtension", {}).get("NSExtensionAttributes", {}).get("WKAppBundleIdentifier") != wi["CFBundleIdentifier"]:
        errors.append("WATCH_EXTENSION_APP_MISMATCH")
    if any(value.get("CFBundleVersion") != phone["CFBundleVersion"] for value in (wi, ei)):
        errors.append("WATCH_BUILD_VERSION_MISMATCH")
    signature = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], capture_output=True)
    if signature.returncode:
        errors.append("INVALID_SIGNATURE")
    team = None
    for label, bundle, metadata, device in [
        ("PHONE", app, phone, phone_device),
        ("WATCH", watch, wi, watch_device),
        ("EXTENSION", extension, ei, watch_device),
    ]:
        result = subprocess.run(["security", "cms", "-D", "-i", str(bundle / "embedded.mobileprovision")],
                                capture_output=True)
        if result.returncode:
            errors.append(label + "_PROFILE_UNREADABLE")
            continue
        profile = plistlib.loads(result.stdout)
        if team is None:
            team = profile.get("Entitlements", {}).get("com.apple.developer.team-identifier", "")
        errors.extend(label + "_" + error for error in profile_errors(
            profile, metadata["CFBundleIdentifier"], device, team, dt.datetime.now(dt.timezone.utc)))
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--phone-udid", required=True)
    parser.add_argument("--watch-udid", required=True)
    args = parser.parse_args()
    try:
        errors = inspect(args.app, args.phone_udid, args.watch_udid)
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        errors = ["BUNDLE_INSPECTION_FAILED:" + type(error).__name__]
    print(json.dumps({"ok": not errors, "errors": errors}))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
