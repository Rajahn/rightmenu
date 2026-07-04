from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


REPO_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = REPO_ROOT / "actions" / "rightmenu-actions.json"
APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "RightMenu"
QUICK_ACTION_CONFIG_PATH = APP_SUPPORT_DIR / "quick-actions-config.json"


@dataclass(frozen=True)
class QuickActionMeta:
    id: str
    title: str
    category: str
    input: str
    script_key: str
    send_file_types: Optional[list[str]]
    core_action_id: Optional[str]

    @property
    def workflow_name(self) -> str:
        return f"{self.title}.workflow"


def load_manifest(path: Path = MANIFEST_PATH) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    validate_manifest(manifest)
    return manifest


def validate_manifest(manifest: dict, known_script_keys: Optional[set[str]] = None) -> None:
    if manifest.get("schemaVersion") != 1:
        raise ValueError(f"Unsupported action manifest schema: {manifest.get('schemaVersion')}")

    ids = set()
    titles = set()
    for action in manifest.get("actions", []):
        action_id = action["id"]
        title = action["title"]
        if action_id in ids:
            raise ValueError(f"Duplicate action id in manifest: {action_id}")
        if title in titles:
            raise ValueError(f"Duplicate action title in manifest: {title}")
        ids.add(action_id)
        titles.add(title)

        quick_action = action.get("quickAction")
        if "quickAction" in action.get("surfaces", []) and not quick_action:
            raise ValueError(f"{action_id} declares quickAction surface but has no quickAction block")

        if quick_action:
            input_kind = quick_action.get("input")
            if input_kind not in {"selected", "finder"}:
                raise ValueError(f"{action_id} has unsupported quickAction input: {input_kind}")

            script_key = quick_action["scriptKey"]
            if known_script_keys is not None and script_key not in known_script_keys:
                raise ValueError(f"{action_id} references unknown scriptKey: {script_key}")


def quick_action_metas(manifest: Optional[dict] = None) -> list[QuickActionMeta]:
    manifest = manifest or load_manifest()
    metas = []
    for action in manifest["actions"]:
        quick_action = action.get("quickAction")
        if not quick_action:
            continue

        metas.append(
            QuickActionMeta(
                id=action["id"],
                title=action["title"],
                category=action["category"],
                input=quick_action["input"],
                script_key=quick_action["scriptKey"],
                send_file_types=quick_action.get("sendFileTypes"),
                core_action_id=action.get("coreActionID"),
            )
        )
    return metas


def default_config() -> dict:
    return {
        "schemaVersion": 1,
        "disabledActionIDs": [],
    }


def load_config(path: Path = QUICK_ACTION_CONFIG_PATH) -> dict:
    if not path.exists():
        return default_config()

    with path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)

    if config.get("schemaVersion") != 1:
        raise ValueError(f"Unsupported quick action config schema: {config.get('schemaVersion')}")

    disabled = config.get("disabledActionIDs", [])
    if not isinstance(disabled, list):
        raise ValueError("quick action config disabledActionIDs must be a list")

    return {
        "schemaVersion": 1,
        "disabledActionIDs": sorted(set(disabled)),
    }


def save_config(config: dict, path: Path = QUICK_ACTION_CONFIG_PATH) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = {
        "schemaVersion": 1,
        "disabledActionIDs": sorted(set(config.get("disabledActionIDs", []))),
    }
    with path.open("w", encoding="utf-8") as handle:
        json.dump(normalized, handle, indent=2, sort_keys=True)
        handle.write("\n")


def disabled_action_ids(config: Optional[dict] = None) -> set[str]:
    config = config or load_config()
    return set(config.get("disabledActionIDs", []))


def enabled_quick_actions(
    manifest: Optional[dict] = None,
    config: Optional[dict] = None,
) -> list[QuickActionMeta]:
    disabled = disabled_action_ids(config)
    return [action for action in quick_action_metas(manifest) if action.id not in disabled]


def find_quick_action(identifier: str, manifest: Optional[dict] = None) -> QuickActionMeta:
    candidates = quick_action_metas(manifest)
    normalized = identifier.casefold()
    for action in candidates:
        if action.id == identifier or action.title == identifier or action.title.casefold() == normalized:
            return action
    raise KeyError(f"Unknown quick action: {identifier}")


def set_action_enabled(identifier: str, enabled: bool) -> QuickActionMeta:
    manifest = load_manifest()
    action = find_quick_action(identifier, manifest)
    config = load_config()
    disabled = disabled_action_ids(config)
    if enabled:
        disabled.discard(action.id)
    else:
        disabled.add(action.id)
    save_config({"schemaVersion": 1, "disabledActionIDs": sorted(disabled)})
    return action


def set_all_actions_enabled(enabled: bool) -> None:
    if enabled:
        save_config(default_config())
        return

    disabled = [action.id for action in quick_action_metas()]
    save_config({"schemaVersion": 1, "disabledActionIDs": disabled})

