#!/usr/bin/env python3
from __future__ import annotations

import argparse
import plistlib
import shutil
import subprocess
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from rightmenu_manifest import (
    QUICK_ACTION_CONFIG_PATH,
    QuickActionMeta,
    disabled_action_ids,
    enabled_quick_actions,
    load_config,
    load_manifest,
    quick_action_metas,
    set_action_enabled,
    set_all_actions_enabled,
    validate_manifest,
)


REPO_ROOT = Path(__file__).resolve().parents[1]
QUICK_ACTIONS_DIR = REPO_ROOT / "quick-actions"
SERVICES_DIR = Path.home() / "Library" / "Services"
PBS = Path("/System/Library/CoreServices/pbs")


HELPERS = r'''finder_path() {
    /usr/bin/osascript <<'APPLESCRIPT'
tell application "Finder"
    if (count of Finder windows) > 0 then
        set targetPath to POSIX path of (target of front Finder window as alias)
    else
        set targetPath to POSIX path of (desktop as alias)
    end if
end tell
APPLESCRIPT
}

absolute_path() {
    local item="$1"
    case "$item" in
        /*) printf '%s\n' "$item" ;;
        *) printf '%s\n' "$PWD/$item" ;;
    esac
}

target_dir_from_item_or_finder() {
    local item="${1:-}"
    if [ -z "$item" ]; then
        finder_path
        return
    fi

    item="$(absolute_path "$item")"
    if [ -f "$item" ]; then
        dirname "$item"
    else
        printf '%s\n' "$item"
    fi
}

shell_quote() {
    printf '%q' "$1"
}

open_terminal_at() {
    local target="$1"
    local escaped
    escaped="$(shell_quote "$target")"
    /usr/bin/osascript <<APPLESCRIPT
tell application "Terminal"
    activate
    do script "cd ${escaped}"
end tell
APPLESCRIPT
}

unique_file_path() {
    local dir="$1"
    local base="$2"
    local ext="$3"
    local candidate="$dir/$base.$ext"
    local index=2
    while [ -e "$candidate" ]; do
        candidate="$dir/$base $index.$ext"
        index=$((index + 1))
    done
    printf '%s\n' "$candidate"
}

open_editor_at() {
    local app_name="$1"
    local cli_name="$2"
    local target="$3"

    if command -v "$cli_name" >/dev/null 2>&1; then
        "$cli_name" "$target" >/dev/null 2>&1 &
    else
        /usr/bin/open -a "$app_name" "$target"
    fi
}

git_root_for_path() {
    local item="$1"
    local dir
    item="$(absolute_path "$item")"
    if [ -d "$item" ]; then
        dir="$item"
    else
        dir="$(dirname "$item")"
    fi

    while [ "$dir" != "/" ]; do
        if [ -e "$dir/.git" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}
'''


SCRIPT_COMMANDS = {
    "copy_selected_path": rf'''{HELPERS}
for item in "$@"; do
    absolute_path "$item"
done | /usr/bin/pbcopy''',
    "copy_selected_name": r'''for item in "$@"; do
    basename "$item"
done | /usr/bin/pbcopy''',
    "copy_parent_path": rf'''{HELPERS}
for item in "$@"; do
    item="$(absolute_path "$item")"
    if [ -d "$item" ]; then
        printf '%s\n' "$item"
    else
        dirname "$item"
    fi
done | /usr/bin/pbcopy''',
    "copy_shell_path": rf'''{HELPERS}
for item in "$@"; do
    shell_quote "$(absolute_path "$item")"
done | /usr/bin/pbcopy''',
    "copy_git_relative_path": rf'''{HELPERS}
for item in "$@"; do
    abs="$(absolute_path "$item")"
    root="$(git_root_for_path "$abs")" || exit 1
    rel="${{abs#"$root/"}}"
    printf '%s\n' "$rel"
done | /usr/bin/pbcopy''',
    "copy_current_finder_path": rf'''{HELPERS}
finder_path | /usr/bin/pbcopy''',
    "open_terminal_selected": rf'''{HELPERS}
target="$(target_dir_from_item_or_finder "${{1:-}}")"
open_terminal_at "$target"''',
    "open_terminal_here": rf'''{HELPERS}
target="$(finder_path)"
open_terminal_at "$target"''',
    "open_vscode_selected": rf'''{HELPERS}
target="$(target_dir_from_item_or_finder "${{1:-}}")"
open_editor_at "Visual Studio Code" "code" "$target"''',
    "open_vscode_here": rf'''{HELPERS}
target="$(finder_path)"
open_editor_at "Visual Studio Code" "code" "$target"''',
    "open_cursor_selected": rf'''{HELPERS}
target="$(target_dir_from_item_or_finder "${{1:-}}")"
open_editor_at "Cursor" "cursor" "$target"''',
    "open_cursor_here": rf'''{HELPERS}
target="$(finder_path)"
open_editor_at "Cursor" "cursor" "$target"''',
    "new_text_file_here": rf'''{HELPERS}
target_dir="$(finder_path)"
new_file="$(unique_file_path "$target_dir" "Untitled" "txt")"
touch "$new_file"
/usr/bin/open -R "$new_file"''',
    "new_markdown_file_here": rf'''{HELPERS}
target_dir="$(finder_path)"
new_file="$(unique_file_path "$target_dir" "Untitled" "md")"
touch "$new_file"
/usr/bin/open -R "$new_file"''',
    "new_json_file_here": rf'''{HELPERS}
target_dir="$(finder_path)"
new_file="$(unique_file_path "$target_dir" "Untitled" "json")"
printf '{{\n  \n}}\n' > "$new_file"
/usr/bin/open -R "$new_file"''',
    "zip_selected_items": rf'''{HELPERS}
if [ "$#" -eq 0 ]; then
    exit 1
fi

first="$(absolute_path "$1")"
parent="$(dirname "$first")"
archive="$parent/Archive.zip"
index=2
while [ -e "$archive" ]; do
    archive="$parent/Archive $index.zip"
    index=$((index + 1))
done

names=()
for item in "$@"; do
    abs="$(absolute_path "$item")"
    if [ "$(dirname "$abs")" != "$parent" ]; then
        exit 1
    fi
    names+=("$(basename "$abs")")
done

(
    cd "$parent" || exit 1
    /usr/bin/zip -qry "$archive" "${{names[@]}}"
)
/usr/bin/open -R "$archive"''',
}


@dataclass(frozen=True)
class QuickAction:
    id: str
    title: str
    command: str
    input_type: str
    input_method: int
    send_file_types: Optional[list[str]] = None

    @property
    def workflow_name(self) -> str:
        return f"{self.title}.workflow"


def quick_action_from_meta(meta: QuickActionMeta) -> QuickAction:
    if meta.script_key not in SCRIPT_COMMANDS:
        raise ValueError(f"{meta.id} references unknown scriptKey: {meta.script_key}")

    if meta.input == "selected":
        input_type = "com.apple.Automator.fileSystemObject"
        input_method = 1
        send_file_types = meta.send_file_types or ["public.item"]
    elif meta.input == "finder":
        input_type = "com.apple.Automator.nothing"
        input_method = 0
        send_file_types = None
    else:
        raise ValueError(f"{meta.id} has unsupported quickAction input: {meta.input}")

    return QuickAction(
        id=meta.id,
        title=meta.title,
        command=SCRIPT_COMMANDS[meta.script_key],
        input_type=input_type,
        input_method=input_method,
        send_file_types=send_file_types,
    )


def validate_action_manifest() -> None:
    validate_manifest(load_manifest(), known_script_keys=set(SCRIPT_COMMANDS))


def quick_actions() -> list[QuickAction]:
    validate_action_manifest()
    return [quick_action_from_meta(meta) for meta in enabled_quick_actions()]


def all_quick_actions() -> list[QuickAction]:
    validate_action_manifest()
    return [quick_action_from_meta(meta) for meta in quick_action_metas()]


def action_plist(spec: QuickAction) -> dict:
    action_uuid = str(uuid.uuid4()).upper()
    return {
        "AMApplicationBuild": "521.1",
        "AMApplicationVersion": "2.10",
        "AMDocumentVersion": "2",
        "actions": [
            {
                "action": {
                    "AMAccepts": {
                        "Container": "List",
                        "Optional": True,
                        "Types": ["com.apple.cocoa.path"],
                    },
                    "AMActionVersion": "2.0.3",
                    "AMApplication": ["Automator"],
                    "AMCategory": ["AMCategoryUtilities"],
                    "AMIconName": "Terminal",
                    "AMName": "Run Shell Script",
                    "AMProvides": {
                        "Container": "List",
                        "Types": ["com.apple.cocoa.string"],
                    },
                    "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
                    "ActionName": "Run Shell Script",
                    "ActionParameters": {
                        "COMMAND_STRING": spec.command,
                        "CheckedForUserDefaultShell": True,
                        "inputMethod": spec.input_method,
                        "shell": "/bin/zsh",
                        "source": "",
                    },
                    "BundleIdentifier": "com.apple.RunShellScript",
                    "CFBundleVersion": "2.0.3",
                    "CanShowSelectedItemsWhenRun": False,
                    "CanShowWhenRun": True,
                    "Class Name": "RunShellScriptAction",
                    "InputUUID": str(uuid.uuid4()).upper(),
                    "OutputUUID": str(uuid.uuid4()).upper(),
                    "UUID": action_uuid,
                    "UnlockPlugin": False,
                    "arguments": {},
                    "isViewVisible": 1,
                    "location": "309.500000:253.000000",
                    "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/English.lproj/main.nib",
                },
                "isViewVisible": 1,
            }
        ],
        "connectors": {},
        "workflowMetaData": {
            "serviceApplicationBundleID": "com.apple.finder",
            "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
            "serviceInputTypeIdentifier": spec.input_type,
            "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
            "serviceProcessesInput": 0,
            "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
        },
    }


def info_plist(spec: QuickAction) -> dict:
    service = {
        "NSMenuItem": {"default": spec.title},
        "NSMessage": "runWorkflowAsService",
        "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
    }
    if spec.send_file_types:
        service["NSSendFileTypes"] = spec.send_file_types
    return {"NSServices": [service]}


def write_plist(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        plistlib.dump(value, handle)


def build_workflows() -> list[Path]:
    QUICK_ACTIONS_DIR.mkdir(parents=True, exist_ok=True)
    built_paths = []
    for spec in quick_actions():
        workflow = QUICK_ACTIONS_DIR / spec.workflow_name
        if workflow.exists():
            shutil.rmtree(workflow)
        contents = workflow / "Contents"
        write_plist(contents / "Info.plist", info_plist(spec))
        write_plist(contents / "document.wflow", action_plist(spec))
        built_paths.append(workflow)
    return built_paths


def remove_disabled_installed_workflows(enabled_workflows: set[str]) -> None:
    for spec in all_quick_actions():
        if spec.workflow_name in enabled_workflows:
            continue
        destination = SERVICES_DIR / spec.workflow_name
        if destination.exists():
            shutil.rmtree(destination)
            print(f"Removed disabled {destination}")


def install_workflows(workflows: list[Path]) -> None:
    SERVICES_DIR.mkdir(parents=True, exist_ok=True)
    enabled_workflows = {workflow.name for workflow in workflows}
    remove_disabled_installed_workflows(enabled_workflows)
    for workflow in workflows:
        destination = SERVICES_DIR / workflow.name
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(workflow, destination)
        print(f"Installed {destination}")


def uninstall_workflows() -> None:
    for spec in all_quick_actions():
        destination = SERVICES_DIR / spec.workflow_name
        if destination.exists():
            shutil.rmtree(destination)
            print(f"Removed {destination}")


def refresh_services() -> None:
    if PBS.exists():
        subprocess.run([str(PBS), "-update"], check=False)
    subprocess.run(["/usr/bin/killall", "Finder"], check=False)


def list_actions() -> int:
    disabled = disabled_action_ids(load_config())
    for meta in quick_action_metas():
        state = "disabled" if meta.id in disabled else "enabled"
        print(f"{state:8} {meta.id:36} {meta.title}")
    return 0


def status() -> int:
    disabled = disabled_action_ids(load_config())
    mismatches = []
    for spec in all_quick_actions():
        destination = SERVICES_DIR / spec.workflow_name
        expected = spec.id not in disabled
        installed = destination.exists()
        if expected and installed:
            state = "installed"
        elif expected and not installed:
            state = "missing"
            mismatches.append(spec.title)
        elif (not expected) and installed:
            state = "disabled-installed"
            mismatches.append(spec.title)
        else:
            state = "disabled"
        print(f"{state:18} {spec.title}")
    return 1 if mismatches else 0


def validate_workflows(paths: list[Path]) -> None:
    for workflow in paths:
        for plist_path in [
            workflow / "Contents" / "Info.plist",
            workflow / "Contents" / "document.wflow",
        ]:
            subprocess.run(["/usr/bin/plutil", "-lint", str(plist_path)], check=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build and install RightMenu Finder Quick Actions.")
    parser.add_argument(
        "command",
        nargs="?",
        default="install",
        choices=[
            "install",
            "build",
            "status",
            "list",
            "enable",
            "disable",
            "enable-all",
            "disable-all",
            "config-path",
            "uninstall",
        ],
        help="Action to perform. Defaults to install.",
    )
    parser.add_argument("identifier", nargs="?", help="Action id or title for enable/disable.")
    parser.add_argument(
        "--no-refresh",
        action="store_true",
        help="Do not refresh macOS Services or restart Finder after install/uninstall.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.command == "config-path":
        print(QUICK_ACTION_CONFIG_PATH)
        return 0

    if args.command == "list":
        return list_actions()

    if args.command == "status":
        return status()

    if args.command in {"enable", "disable"}:
        if not args.identifier:
            raise SystemExit(f"{args.command} requires an action id or title")
        action = set_action_enabled(args.identifier, enabled=args.command == "enable")
        print(f"{args.command}d {action.title}")
        return 0

    if args.command == "enable-all":
        set_all_actions_enabled(True)
        print("Enabled all Quick Actions")
        return 0

    if args.command == "disable-all":
        set_all_actions_enabled(False)
        print("Disabled all Quick Actions")
        return 0

    if args.command == "uninstall":
        uninstall_workflows()
        if not args.no_refresh:
            refresh_services()
        return 0

    workflows = build_workflows()
    validate_workflows(workflows)

    if args.command == "build":
        for workflow in workflows:
            print(f"Built {workflow}")
        return 0

    install_workflows(workflows)
    if not args.no_refresh:
        refresh_services()
    print("Quick Actions installed. Check System Settings > Keyboard > Keyboard Shortcuts > Services > Files and Folders if they do not appear.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

