#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import json
import plistlib
import platform
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
NATIVE_DIR = REPO_ROOT / "native"
BUILD_ROOT = REPO_ROOT / ".build" / "native"
NATIVE_ACTION_MANIFEST = NATIVE_DIR / "rightmenu-native-actions.json"
APP_NAME = "RightMenuNative"
EXTENSION_NAME = "RightMenuFinderExtension"
APP_BUNDLE_ID = "com.huoran.rightmenu.native"
EXTENSION_BUNDLE_ID = "com.huoran.rightmenu.findersync"
APP_BUNDLE = BUILD_ROOT / f"{APP_NAME}.app"
EXTENSION_BUNDLE = APP_BUNDLE / "Contents" / "PlugIns" / f"{EXTENSION_NAME}.appex"
SYSTEM_INSTALL_PATH = Path("/Applications") / f"{APP_NAME}.app"
USER_INSTALL_PATH = Path.home() / "Applications" / f"{APP_NAME}.app"
EXTENSION_ENTITLEMENTS = BUILD_ROOT / "RightMenuFinderExtension.entitlements"
NATIVE_CONFIG_PATH = (
    Path.home()
    / "Library"
    / "Containers"
    / EXTENSION_BUNDLE_ID
    / "Data"
    / "Library"
    / "Application Support"
    / "RightMenu"
    / "native-actions-config.json"
)
NATIVE_HANDLER_NAMES = {
    "copyPath",
    "copyShellPath",
    "copyName",
    "copyParentPath",
    "copyGitRelativePath",
    "copyItems",
    "cutItems",
    "pasteItems",
    "openTerminal",
    "openVSCode",
    "openCursor",
    "newTextFile",
    "newMarkdownFile",
    "zipSelectedItems",
}


def run(args: list[str], *, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        cwd=REPO_ROOT,
        check=check,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )


def sdk_path() -> str:
    return run(["/usr/bin/xcrun", "--show-sdk-path"], capture=True).stdout.strip()


def target_triple() -> str:
    arch = platform.machine() or "arm64"
    if arch not in {"arm64", "x86_64"}:
        arch = "arm64"
    return f"{arch}-apple-macosx13.0"


def write_plist(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        plistlib.dump(value, handle)


def load_native_manifest() -> dict:
    with NATIVE_ACTION_MANIFEST.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    validate_native_manifest(manifest)
    return manifest


def native_actions(manifest: dict | None = None) -> list[dict]:
    manifest = manifest or load_native_manifest()
    return [action for group in manifest["groups"] for action in group]


def validate_native_manifest(manifest: dict) -> None:
    if manifest.get("schemaVersion") != 1:
        raise ValueError(f"Unsupported native action manifest schema: {manifest.get('schemaVersion')}")

    ids = set()
    for group in manifest.get("groups", []):
        if not isinstance(group, list):
            raise ValueError("native action manifest groups must be arrays")
        for action in group:
            action_id = action["id"]
            if action_id in ids:
                raise ValueError(f"Duplicate native action id: {action_id}")
            ids.add(action_id)

            if action.get("visibility") not in {"always", "selectionOnly", "emptyOnly"}:
                raise ValueError(f"{action_id} has unsupported visibility: {action.get('visibility')}")
            if action.get("handler") not in NATIVE_HANDLER_NAMES:
                raise ValueError(f"{action_id} references unknown handler: {action.get('handler')}")
            for field in ["title", "symbol"]:
                if not action.get(field):
                    raise ValueError(f"{action_id} is missing {field}")


def load_native_config() -> dict:
    if not NATIVE_CONFIG_PATH.exists():
        return {"schemaVersion": 1, "disabledActionIDs": []}
    with NATIVE_CONFIG_PATH.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    if config.get("schemaVersion") != 1:
        raise ValueError(f"Unsupported native action config schema: {config.get('schemaVersion')}")
    disabled = config.get("disabledActionIDs", [])
    if not isinstance(disabled, list):
        raise ValueError("native action config disabledActionIDs must be a list")
    return {"schemaVersion": 1, "disabledActionIDs": sorted(set(disabled))}


def save_native_config(config: dict) -> None:
    NATIVE_CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    normalized = {
        "schemaVersion": 1,
        "disabledActionIDs": sorted(set(config.get("disabledActionIDs", []))),
    }
    with NATIVE_CONFIG_PATH.open("w", encoding="utf-8") as handle:
        json.dump(normalized, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def find_native_action(identifier: str) -> dict:
    normalized = identifier.casefold()
    for action in native_actions():
        if action["id"] == identifier or action["title"] == identifier or action["title"].casefold() == normalized:
            return action
    raise KeyError(f"Unknown native action: {identifier}")


def set_native_action_enabled(identifier: str, enabled: bool) -> dict:
    action = find_native_action(identifier)
    config = load_native_config()
    disabled = set(config["disabledActionIDs"])
    if enabled:
        disabled.discard(action["id"])
    else:
        disabled.add(action["id"])
    save_native_config({"schemaVersion": 1, "disabledActionIDs": sorted(disabled)})
    return action


def restart_finder() -> None:
    run(["/usr/bin/killall", "Finder"], check=False)


def stop_host_app() -> None:
    run(["/usr/bin/killall", APP_NAME], check=False)


def preferred_install_path() -> Path:
    return SYSTEM_INSTALL_PATH if os.access(SYSTEM_INSTALL_PATH.parent, os.W_OK) else USER_INSTALL_PATH


def installed_paths() -> list[Path]:
    return [SYSTEM_INSTALL_PATH, USER_INSTALL_PATH]


def app_info_plist() -> dict:
    return {
        "CFBundleDevelopmentRegion": "zh_CN",
        "CFBundleExecutable": APP_NAME,
        "CFBundleIdentifier": APP_BUNDLE_ID,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": APP_NAME,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleSupportedPlatforms": ["MacOSX"],
        "CFBundleURLTypes": [
            {
                "CFBundleURLName": APP_BUNDLE_ID,
                "CFBundleURLSchemes": ["rightmenu"],
            }
        ],
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "13.0",
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
    }


def extension_info_plist() -> dict:
    return {
        "CFBundleDevelopmentRegion": "zh_CN",
        "CFBundleDisplayName": EXTENSION_NAME,
        "CFBundleExecutable": EXTENSION_NAME,
        "CFBundleIdentifier": EXTENSION_BUNDLE_ID,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": EXTENSION_NAME,
        "CFBundlePackageType": "XPC!",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleSupportedPlatforms": ["MacOSX"],
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "13.0",
        "LSUIElement": True,
        "NSExtension": {
            "NSExtensionAttributes": {},
            "NSExtensionPointIdentifier": "com.apple.FinderSync",
            "NSExtensionPrincipalClass": f"{EXTENSION_NAME}.FinderSync",
        },
        "NSPrincipalClass": "NSApplication",
    }


def extension_entitlements() -> dict:
    return {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.files.user-selected.read-write": True,
    }


def prepare_bundle() -> None:
    if APP_BUNDLE.exists():
        shutil.rmtree(APP_BUNDLE)

    (APP_BUNDLE / "Contents" / "MacOS").mkdir(parents=True)
    (APP_BUNDLE / "Contents" / "PlugIns").mkdir(parents=True)
    (APP_BUNDLE / "Contents" / "Resources").mkdir(parents=True)
    (EXTENSION_BUNDLE / "Contents" / "MacOS").mkdir(parents=True)
    (EXTENSION_BUNDLE / "Contents" / "Resources").mkdir(parents=True)
    write_plist(APP_BUNDLE / "Contents" / "Info.plist", app_info_plist())
    write_plist(EXTENSION_BUNDLE / "Contents" / "Info.plist", extension_info_plist())
    write_plist(EXTENSION_ENTITLEMENTS, extension_entitlements())
    shutil.copy2(NATIVE_ACTION_MANIFEST, APP_BUNDLE / "Contents" / "Resources" / NATIVE_ACTION_MANIFEST.name)
    shutil.copy2(NATIVE_ACTION_MANIFEST, EXTENSION_BUNDLE / "Contents" / "Resources" / NATIVE_ACTION_MANIFEST.name)


def compile_swift() -> None:
    sdk = sdk_path()
    target = target_triple()
    run([
        "/usr/bin/swiftc",
        str(NATIVE_DIR / "RightMenuNativeApp.swift"),
        "-sdk",
        sdk,
        "-target",
        target,
        "-framework",
        "Cocoa",
        "-o",
        str(APP_BUNDLE / "Contents" / "MacOS" / APP_NAME),
    ])
    run([
        "/usr/bin/swiftc",
        str(NATIVE_DIR / "RightMenuFinderExtensionMain" / "main.swift"),
        str(NATIVE_DIR / "RightMenuFinderSync.swift"),
        "-sdk",
        sdk,
        "-target",
        target,
        "-module-name",
        EXTENSION_NAME,
        "-framework",
        "Cocoa",
        "-framework",
        "FinderSync",
        "-o",
        str(EXTENSION_BUNDLE / "Contents" / "MacOS" / EXTENSION_NAME),
    ])


def lint_plists() -> None:
    run(["/usr/bin/plutil", "-lint", str(APP_BUNDLE / "Contents" / "Info.plist")])
    run(["/usr/bin/plutil", "-lint", str(EXTENSION_BUNDLE / "Contents" / "Info.plist")])


def codesign() -> None:
    run([
        "/usr/bin/codesign",
        "--force",
        "--sign",
        "-",
        "--timestamp=none",
        "--entitlements",
        str(EXTENSION_ENTITLEMENTS),
        str(EXTENSION_BUNDLE),
    ])
    run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(APP_BUNDLE)])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(APP_BUNDLE)])


def build() -> Path:
    load_native_manifest()
    prepare_bundle()
    compile_swift()
    lint_plists()
    codesign()
    print(f"Built {APP_BUNDLE}")
    return APP_BUNDLE


def install() -> None:
    build()
    install_path = preferred_install_path()
    install_path.parent.mkdir(parents=True, exist_ok=True)
    stop_host_app()

    for stale_path in installed_paths():
        if stale_path.exists():
            shutil.rmtree(stale_path)

    shutil.copytree(APP_BUNDLE, install_path, symlinks=True)

    installed_extension = install_path / "Contents" / "PlugIns" / f"{EXTENSION_NAME}.appex"
    run(["/usr/bin/pluginkit", "-a", str(installed_extension)], check=False)
    run(["/usr/bin/pluginkit", "-e", "use", "-i", EXTENSION_BUNDLE_ID], check=False)
    run(["/usr/bin/open", str(install_path)], check=False)
    restart_finder()
    print(f"Installed {install_path}")
    print(f"Enabled Finder Sync extension {EXTENSION_BUNDLE_ID}")


def status() -> int:
    for path in installed_paths():
        print(f"App: {path}")
        print(f"Installed: {path.exists()}")
    result = run(["/usr/bin/pluginkit", "-m", "-i", EXTENSION_BUNDLE_ID, "-v"], check=False, capture=True)
    output = result.stdout.strip()
    print(output or "Finder Sync extension is not registered.")
    return 0 if EXTENSION_BUNDLE_ID in output else 1


def list_actions() -> int:
    disabled = set(load_native_config()["disabledActionIDs"])
    for action in native_actions():
        state = "disabled" if action["id"] in disabled else "enabled"
        print(f"{state:8} {action['id']:38} {action['title']}")
    return 0


def uninstall() -> None:
    run(["/usr/bin/pluginkit", "-e", "ignore", "-i", EXTENSION_BUNDLE_ID], check=False)
    for path in installed_paths():
        run(["/usr/bin/pluginkit", "-r", str(path / "Contents" / "PlugIns" / f"{EXTENSION_NAME}.appex")], check=False)
        if path.exists():
            shutil.rmtree(path)
            print(f"Removed {path}")
    restart_finder()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build and install the native RightMenu Finder Sync extension.")
    parser.add_argument(
        "command",
        nargs="?",
        default="install",
        choices=[
            "build",
            "install",
            "status",
            "list-actions",
            "enable",
            "disable",
            "enable-all",
            "disable-all",
            "config-path",
            "uninstall",
        ],
    )
    parser.add_argument("identifier", nargs="?", help="Native action id or title for enable/disable.")
    return parser.parse_args()


def main() -> int:
    if sys.platform != "darwin":
        raise SystemExit("Native Finder Sync can only be built on macOS.")

    args = parse_args()
    if args.command == "build":
        build()
        return 0
    if args.command == "install":
        install()
        return 0
    if args.command == "status":
        return status()
    if args.command == "config-path":
        print(NATIVE_CONFIG_PATH)
        return 0
    if args.command == "list-actions":
        return list_actions()
    if args.command in {"enable", "disable"}:
        if not args.identifier:
            raise SystemExit(f"{args.command} requires a native action id or title")
        action = set_native_action_enabled(args.identifier, enabled=args.command == "enable")
        restart_finder()
        print(f"{args.command}d {action['title']}")
        return 0
    if args.command == "enable-all":
        save_native_config({"schemaVersion": 1, "disabledActionIDs": []})
        restart_finder()
        print("Enabled all native Finder actions")
        return 0
    if args.command == "disable-all":
        disabled = [action["id"] for action in native_actions()]
        save_native_config({"schemaVersion": 1, "disabledActionIDs": disabled})
        restart_finder()
        print("Disabled all native Finder actions")
        return 0
    if args.command == "uninstall":
        uninstall()
        return 0
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
