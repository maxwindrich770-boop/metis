#!/usr/bin/env python3
"""Prepare an isolated Personal Team iPhone project, optionally with its Watch companion."""

import argparse
import json
import plistlib
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree as ET


def load_project(source):
    result = subprocess.run(
        ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(source / "project.pbxproj")],
        check=True, capture_output=True, text=True,
    )
    project = json.loads(result.stdout)
    objects = project["objects"]
    root = objects[project["rootObject"]]
    scheme = ET.parse(source / "xcshareddata/xcschemes/Metis.xcscheme")
    reference = scheme.find("./LaunchAction/BuildableProductRunnable/BuildableReference")
    if reference is None:
        raise ValueError("The original Metis scheme has no runnable application.")
    target_id = reference.get("BlueprintIdentifier")
    target = objects.get(target_id, {})
    if (target_id not in root["targets"] or target.get("isa") != "PBXNativeTarget"
            or target.get("productType") != "com.apple.product-type.application"):
        raise ValueError("The Metis scheme must refer to a native application in this project.")
    return project, objects, root, target_id, target


def remove_references(value, removed):
    if isinstance(value, dict):
        return {
            key: remove_references(item, removed)
            for key, item in value.items()
            if key not in removed and not (isinstance(item, str) and item in removed)
        }
    if isinstance(value, list):
        return [
            remove_references(item, removed) for item in value
            if not (isinstance(item, str) and item in removed)
        ]
    return value


def referenced_objects(value, objects):
    if isinstance(value, str):
        if value in objects:
            yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            if key in objects:
                yield key
            yield from referenced_objects(item, objects)
    elif isinstance(value, list):
        for item in value:
            yield from referenced_objects(item, objects)


def prepare(project, objects, root, target_id, target, source_root, team, bundle_id, include_watch=False):
    kept = {target_id}
    if include_watch:
        kept.update(key for key in root["targets"]
                    if objects[key].get("name") in {"MetisWatch", "MetisWatchExtension"})
        if len(kept) != 3:
            raise ValueError("Expected the watchOS 8 app and WatchKit extension targets.")
    root["targets"] = [key for key in root["targets"] if key in kept]
    root["projectDirPath"] = str(source_root)
    root["projectRoot"] = ""
    main_group = objects[root["mainGroup"]]
    main_group["sourceTree"] = "<absolute>"
    main_group["path"] = str(source_root)
    objects[root["productRefGroup"]]["children"] = [objects[key]["productReference"] for key in root["targets"]]
    allowed_dependencies = {key for key, value in objects.items()
                            if value.get("isa") == "PBXTargetDependency" and value.get("target") in kept}
    allowed_copy_phases = {key for key, value in objects.items()
                           if include_watch and value.get("isa") == "PBXCopyFilesBuildPhase"
                           and value.get("name") in {"Embed Watch Content", "Embed Watch Extension"}}
    for key in kept:
        objects[key]["dependencies"] = [dep for dep in objects[key].get("dependencies", [])
                                        if dep in allowed_dependencies]
    attributes = root.setdefault("attributes", {})
    attributes.pop("SystemCapabilities", None)
    own_attributes = attributes.get("TargetAttributes", {}).get(target_id, {})
    own_attributes.pop("SystemCapabilities", None)
    own_attributes.update({"ProvisioningStyle": "Automatic", "DevelopmentTeam": team})
    attributes["TargetAttributes"] = {target_id: own_attributes}
    removed = {
        key for key, value in objects.items()
        if ((value.get("isa") == "PBXNativeTarget" and key not in kept)
            or (value.get("isa") == "PBXTargetDependency" and key not in allowed_dependencies)
            or (value.get("isa") == "PBXContainerItemProxy" and value.get("remoteGlobalIDString") not in kept)
            or (value.get("isa") == "PBXCopyFilesBuildPhase" and key not in allowed_copy_phases))
    }
    objects = {
        key: remove_references(value, removed)
        for key, value in objects.items() if key not in removed
    }
    reachable = set()
    pending = [project["rootObject"]]
    while pending:
        key = pending.pop()
        if key not in reachable:
            reachable.add(key)
            pending.extend(referenced_objects(objects[key], objects))
    objects = {key: value for key, value in objects.items() if key in reachable}
    project["objects"] = objects
    for value in objects.values():
        if value.get("isa") != "XCBuildConfiguration":
            continue
        settings = value.setdefault("buildSettings", {})
        signing_keys = {
            "CODE_SIGN_ENTITLEMENTS", "CODE_SIGN_IDENTITY", "CODE_SIGN_STYLE",
            "DEVELOPMENT_TEAM", "PROVISIONING_PROFILE", "PROVISIONING_PROFILE_SPECIFIER",
        }
        for key in list(settings):
            if key.split("[", 1)[0] in signing_keys:
                del settings[key]
        settings.update({
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": team,
            "CODE_SIGN_IDENTITY": "Apple Development",
            "CODE_SIGN_IDENTITY[sdk=iphonesimulator*]": "-",
            "CODE_SIGN_ENTITLEMENTS": "",
            "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": "",
            "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": "",
            "PROVISIONING_PROFILE": "",
            "PROVISIONING_PROFILE_SPECIFIER": "",
            "METIS_PHONE_BUNDLE_ID": bundle_id,
            "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
            "INFOPLIST_KEY_CFBundleDisplayName": "Metis Test",
            # Generated from this variant's cleared entitlements, not a Team ID guess.
            "METIS_PUSH_UNAVAILABLE_REASON": "personal-team",
            "INFOPLIST_FILE": str(source_root / "MetisiOS/Info.plist"),
        })
    if include_watch:
        for key in kept - {target_id}:
            watch_target = objects[key]
            extension = watch_target["name"] == "MetisWatchExtension"
            for config_id in objects[watch_target["buildConfigurationList"]]["buildConfigurations"]:
                settings = objects[config_id]["buildSettings"]
                settings.update({
                    "PRODUCT_BUNDLE_IDENTIFIER": bundle_id + ".watchkitapp" + (".watchkitextension" if extension else ""),
                    "PRODUCT_NAME": watch_target["name"],
                    "INFOPLIST_FILE": str(source_root / ("MetisWatch/ExtensionInfo.plist" if extension else "MetisWatch/Info.plist")),
                    "INFOPLIST_KEY_CFBundleDisplayName": "Metis",
                    "CODE_SIGN_IDENTITY[sdk=watchsimulator*]": "-",
                })
    return project


def make_scheme(target_id, target, product, project_path):
    scheme = ET.Element("Scheme", {"LastUpgradeVersion": "2720", "version": "1.3"})

    def reference(parent):
        ET.SubElement(parent, "BuildableReference", {
            "BuildableIdentifier": "primary", "BlueprintIdentifier": target_id,
            "BuildableName": product["path"], "BlueprintName": target["name"],
            # PROJECT_DIR points at the original sources, so this must be absolute.
            "ReferencedContainer": "container:" + str(project_path),
        })

    build = ET.SubElement(scheme, "BuildAction", {
        "parallelizeBuildables": "YES", "buildImplicitDependencies": "NO",
    })
    entries = ET.SubElement(build, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", {
        "buildForTesting": "NO", "buildForRunning": "YES", "buildForProfiling": "YES",
        "buildForArchiving": "YES", "buildForAnalyzing": "YES",
    })
    reference(entry)
    launch = ET.SubElement(scheme, "LaunchAction", {
        "buildConfiguration": "Debug",
        "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
        "selectedLauncherIdentifier": "Xcode.DebuggerFoundation.Launcher.LLDB",
        "launchStyle": "0", "useCustomWorkingDirectory": "NO",
        "ignoresPersistentStateOnLaunch": "NO", "debugDocumentVersioning": "YES",
        "debugServiceExtension": "internal", "allowLocationSimulation": "YES",
    })
    reference(ET.SubElement(launch, "BuildableProductRunnable", {"runnableDebuggingMode": "0"}))
    ET.SubElement(scheme, "AnalyzeAction", {"buildConfiguration": "Debug"})
    ET.SubElement(scheme, "ArchiveAction", {
        "buildConfiguration": "Release", "revealArchiveInOrganizer": "YES",
    })
    ET.indent(scheme)
    return ET.tostring(scheme, encoding="utf-8", xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--team", required=True, help="Personal Team ID from Xcode")
    parser.add_argument("--bundle-id", required=True, help="Unique iPhone bundle identifier")
    parser.add_argument("--output", required=True, type=Path, help="New directory outside the checkout")
    parser.add_argument(
        "--project", type=Path,
        default=Path(__file__).resolve().parents[1] / "MetisApple.xcodeproj",
        help="Original Xcode project (default: clients/apple/MetisApple.xcodeproj)",
    )
    parser.add_argument("--include-watch", action="store_true", help="Keep the watchOS 8 companion; Push and Share remain omitted")
    args = parser.parse_args()
    if (len(args.team) != 10 or not args.team.isascii()
            or not args.team.isalnum() or args.team != args.team.upper()):
        parser.error("--team must be the 10-character Team ID shown by Xcode.")
    parts = args.bundle_id.split(".")
    if (len(parts) < 2 or any(not part for part in parts)
            or any(not (char.isascii() and (char.isalnum() or char in ".-"))
                   for char in args.bundle_id)):
        parser.error("--bundle-id must be a concrete reverse-DNS identifier without wildcards.")
    source = args.project.expanduser().resolve(strict=True)
    source_root = source.parent
    output = args.output.expanduser().absolute()
    if output.exists() or output.is_symlink():
        parser.error("--output already exists; choose a new directory.")
    output = output.resolve()
    for ancestor in (source_root, *source_root.parents):
        if (ancestor / ".git").exists():
            if output.is_relative_to(ancestor):
                parser.error("--output must be outside the source checkout.")
            break
    if output.is_relative_to(source_root):
        parser.error("--output must be outside the original Apple source directory.")
    if not output.parent.is_dir():
        parser.error("The parent of --output must already exist.")
    project, objects, root, target_id, target = load_project(source)
    product = objects[target["productReference"]]
    project = prepare(
        project, objects, root, target_id, target, source_root, args.team, args.bundle_id, args.include_watch,
    )
    project_name = "MetisPersonalTeam.xcodeproj"
    scheme = make_scheme(target_id, target, product, output / project_name)
    encoded_project = plistlib.dumps(project, fmt=plistlib.FMT_XML, sort_keys=False)
    output.mkdir(mode=0o700)
    generated = output / project_name
    scheme_folder = generated / "xcshareddata/xcschemes"
    scheme_folder.mkdir(parents=True)
    (generated / "project.pbxproj").write_bytes(encoded_project)
    (scheme_folder / "Metis Test.xcscheme").write_bytes(scheme)
    print("Project:", generated)
    print("Scheme: Metis Test")
    print("Display name: Metis Test")
    print("Personal Team variant: iPhone + watchOS 8 companion; Push and Share unavailable." if args.include_watch else "Personal Team variant: iPhone only; Push, Share and Watch companion unavailable.")
    print("Original project and HTTPS/session behavior unchanged. No build or provisioning performed.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, ET.ParseError) as error:
        print("Could not prepare Personal Team project: " + str(error), file=sys.stderr)
        sys.exit(1)
