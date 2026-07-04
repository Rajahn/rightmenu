#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SERVICES_DIR = Path.home() / "Library" / "Services"
INSTALLER = REPO_ROOT / "scripts" / "install-quick-actions.py"
NATIVE_INSTALLER = REPO_ROOT / "scripts" / "build-native-finder-sync.py"
PBS = Path("/System/Library/CoreServices/pbs")

from rightmenu_manifest import enabled_quick_actions, load_manifest as load_action_manifest, quick_action_metas


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str = ""


def run_command(
    args: list[str],
    cwd: Path = REPO_ROOT,
    timeout: int = 60,
    check: bool = False,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        cwd=cwd,
        timeout=timeout,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=check,
    )


def add_result(results: list[CheckResult], name: str, passed: bool, detail: str = "") -> None:
    results.append(CheckResult(name=name, passed=passed, detail=detail.strip()))


def workflow_path(action_name: str) -> Path:
    return SERVICES_DIR / f"{action_name}.workflow"


def quick_action_titles() -> list[str]:
    return [action.title for action in enabled_quick_actions()]


def is_action_enabled(title: str) -> bool:
    return title in set(quick_action_titles())


def pbpaste() -> str:
    return run_command(["/usr/bin/pbpaste"]).stdout


def run_workflow(action_name: str, inputs: list[Path] | None = None, timeout: int = 30) -> subprocess.CompletedProcess:
    args = ["/usr/bin/automator"]
    for item in inputs or []:
        args.extend(["-i", str(item)])
    args.append(str(workflow_path(action_name)))
    return run_command(args, timeout=timeout)


def open_finder_window(path: Path) -> None:
    run_command(["/usr/bin/open", str(path)], timeout=10)
    time.sleep(1)


def close_front_finder_window() -> None:
    run_command([
        "/usr/bin/osascript",
        "-e",
        'tell application "Finder" to if (count of Finder windows) > 0 then close front Finder window',
    ], timeout=10)


def check_swift(results: list[CheckResult]) -> None:
    build = run_command(["/usr/bin/swift", "build"], timeout=120)
    add_result(results, "swift build", build.returncode == 0, build.stdout[-800:])

    smoke = run_command(["/usr/bin/swift", "run", "rightmenu-smoke-tests"], timeout=120)
    add_result(results, "rightmenu smoke tests", smoke.returncode == 0, smoke.stdout[-800:])


def check_workflow_generation(results: list[CheckResult]) -> None:
    compile_result = run_command([sys.executable, "-m", "py_compile", str(INSTALLER), str(NATIVE_INSTALLER)])
    add_result(results, "installer Python syntax", compile_result.returncode == 0, compile_result.stdout)

    build = run_command([sys.executable, str(INSTALLER), "build"], timeout=120)
    add_result(results, "workflow generation and plist lint", build.returncode == 0, build.stdout[-1200:])


def check_native_finder_sync_build(results: list[CheckResult]) -> None:
    build = run_command([sys.executable, str(NATIVE_INSTALLER), "build"], timeout=120)
    add_result(results, "native Finder Sync build", build.returncode == 0, build.stdout[-1600:])


def check_native_install_status(results: list[CheckResult]) -> None:
    status = run_command([sys.executable, str(NATIVE_INSTALLER), "status"], timeout=30)
    add_result(results, "native Finder Sync installed", status.returncode == 0, status.stdout[-1200:])

    list_actions = run_command([sys.executable, str(NATIVE_INSTALLER), "list-actions"], timeout=30)
    expected = [
        "native.copy.path",
        "native.copy.shell-path",
        "native.file.copy-items",
        "native.file.cut-items",
        "native.file.paste-items",
        "native.open.terminal",
        "native.open.cursor",
    ]
    missing = [action_id for action_id in expected if action_id not in list_actions.stdout]
    add_result(
        results,
        "native action list",
        list_actions.returncode == 0 and not missing,
        "missing: " + ", ".join(missing) if missing else list_actions.stdout[-1200:],
    )


def check_native_action_config(results: list[CheckResult]) -> None:
    config_path = run_command([sys.executable, str(NATIVE_INSTALLER), "config-path"], timeout=30)
    path = Path(config_path.stdout.strip())
    if not path.exists():
        add_result(results, "native action config", True, "no config file yet; defaults to all actions enabled")
        return

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        disabled = data.get("disabledActionIDs", [])
        passed = data.get("schemaVersion") == 1 and isinstance(disabled, list)
        detail = f"{len(disabled)} disabled actions at {path}"
    except Exception as error:
        passed = False
        detail = str(error)
    add_result(results, "native action config", passed, detail)


def check_quick_actions_absent(results: list[CheckResult]) -> None:
    installed = sorted(path.name for path in SERVICES_DIR.glob("RightMenu*.workflow"))
    add_result(
        results,
        "fallback Quick Actions cleaned",
        not installed,
        "still installed: " + ", ".join(installed) if installed else "no RightMenu Services workflows installed",
    )


def check_manifest(results: list[CheckResult]) -> None:
    try:
        manifest = load_action_manifest()
        ids = [action["id"] for action in manifest.get("actions", [])]
        titles = [action["title"] for action in manifest.get("actions", [])]
        script_keys = [
            action["quickAction"]["scriptKey"]
            for action in manifest.get("actions", [])
            if action.get("quickAction")
        ]
        passed = (
            manifest.get("schemaVersion") == 1
            and len(ids) == len(set(ids))
            and len(titles) == len(set(titles))
            and len(script_keys) == len(quick_action_metas(manifest))
        )
        detail = f"{len(ids)} manifest actions, {len(script_keys)} quick actions"
    except Exception as error:
        passed = False
        detail = str(error)
    add_result(results, "action manifest", passed, detail)


def check_installed_files(results: list[CheckResult]) -> None:
    installed_actions = quick_action_titles()
    missing = [name for name in installed_actions if not workflow_path(name).exists()]
    add_result(
        results,
        "installed workflow files",
        not missing,
        "missing: " + ", ".join(missing) if missing else f"{len(installed_actions)} installed",
    )

    invalid = []
    for name in installed_actions:
        for relative in ["Contents/Info.plist", "Contents/document.wflow"]:
            plist_path = workflow_path(name) / relative
            if not plist_path.exists():
                invalid.append(str(plist_path))
                continue
            lint = run_command(["/usr/bin/plutil", "-lint", str(plist_path)])
            if lint.returncode != 0:
                invalid.append(f"{plist_path}: {lint.stdout}")

    add_result(
        results,
        "installed workflow plist lint",
        not invalid,
        "\n".join(invalid[:8]) if invalid else "OK",
    )


def check_services_registration(results: list[CheckResult]) -> None:
    if not PBS.exists():
        add_result(results, "macOS Services registration", False, f"{PBS} missing")
        return

    dump = run_command([str(PBS), "-dump"], timeout=30)
    installed_actions = quick_action_titles()
    missing = [name for name in installed_actions if name not in dump.stdout]
    add_result(
        results,
        "macOS Services registration",
        dump.returncode == 0 and not missing,
        "missing: " + ", ".join(missing) if missing else "all RightMenu services registered",
    )


def check_selected_workflows(results: list[CheckResult]) -> None:
    readme = REPO_ROOT / "README.md"

    path_result = run_workflow("RightMenu Copy Selected Path", [readme])
    add_result(
        results,
        "workflow: copy selected path",
        path_result.returncode == 0 and pbpaste().strip() == str(readme),
        path_result.stdout or f"clipboard={pbpaste()}",
    )

    name_result = run_workflow("RightMenu Copy Selected Name", [readme])
    add_result(
        results,
        "workflow: copy selected name",
        name_result.returncode == 0 and pbpaste().strip() == "README.md",
        name_result.stdout or f"clipboard={pbpaste()}",
    )

    parent_result = run_workflow("RightMenu Copy Parent Path", [readme])
    add_result(
        results,
        "workflow: copy parent path",
        parent_result.returncode == 0 and pbpaste().strip() == str(REPO_ROOT),
        parent_result.stdout or f"clipboard={pbpaste()}",
    )

    git_result = run_workflow("RightMenu Copy Git Relative Path", [readme])
    add_result(
        results,
        "workflow: copy Git-relative path",
        git_result.returncode == 0 and pbpaste().strip() == "README.md",
        git_result.stdout or f"clipboard={pbpaste()}",
    )


def check_temp_workflows(results: list[CheckResult]) -> None:
    with tempfile.TemporaryDirectory(prefix="rightmenu-doctor-") as tmp:
        tmpdir = Path(tmp)
        spaced = tmpdir / "a file.txt"
        spaced.write_text("hello", encoding="utf-8")

        shell_result = run_workflow("RightMenu Copy Shell Path", [spaced])
        add_result(
            results,
            "workflow: copy shell path",
            shell_result.returncode == 0 and "a\\ file.txt" in pbpaste(),
            shell_result.stdout or f"clipboard={pbpaste()}",
        )

        a = tmpdir / "a.txt"
        b = tmpdir / "b.txt"
        a.write_text("a", encoding="utf-8")
        b.write_text("b", encoding="utf-8")
        zip_result = run_workflow("RightMenu Zip Selected Items", [a, b], timeout=60)
        archive = tmpdir / "Archive.zip"
        add_result(
            results,
            "workflow: zip selected items",
            zip_result.returncode == 0 and archive.exists(),
            zip_result.stdout or f"archive_exists={archive.exists()}",
        )

    with tempfile.TemporaryDirectory(prefix="rightmenu-finder-") as tmp:
        tmpdir = Path(tmp)
        open_finder_window(tmpdir)
        try:
            current_result = run_workflow("RightMenu Copy Current Finder Path", timeout=60)
            current = pbpaste().strip()
            expected_suffix = tmpdir.name + "/"
            add_result(
                results,
                "workflow: copy current Finder path",
                current_result.returncode == 0 and current.endswith(expected_suffix),
                current_result.stdout or f"clipboard={current}",
            )

            new_text = run_workflow("RightMenu New Text File Here", timeout=60)
            created = tmpdir / "Untitled.txt"
            add_result(
                results,
                "workflow: new text file here",
                new_text.returncode == 0 and created.exists(),
                new_text.stdout or f"created={created.exists()}",
            )
        finally:
            close_front_finder_window()


def print_results(results: list[CheckResult]) -> int:
    failed = [result for result in results if not result.passed]
    for result in results:
        prefix = "PASS" if result.passed else "FAIL"
        print(f"[{prefix}] {result.name}")
        if result.detail and (not result.passed):
            print(result.detail)
    print(f"\n{len(results) - len(failed)}/{len(results)} checks passed.")
    return 1 if failed else 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate RightMenu local development and installed native Finder integration.")
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Deprecated alias for --quick-actions.",
    )
    parser.add_argument(
        "--quick-actions",
        action="store_true",
        help="Validate installed Automator Quick Actions fallback instead of the native Finder Sync setup.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    results: list[CheckResult] = []

    if args.quick or args.quick_actions:
        check_workflow_generation(results)
        check_installed_files(results)
        check_services_registration(results)
        check_selected_workflows(results)
        check_temp_workflows(results)
        return print_results(results)

    if not args.quick:
        check_swift(results)
        check_manifest(results)
        check_workflow_generation(results)
        check_native_finder_sync_build(results)

    check_native_install_status(results)
    check_native_action_config(results)
    check_quick_actions_absent(results)

    return print_results(results)


if __name__ == "__main__":
    raise SystemExit(main())
