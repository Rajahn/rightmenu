# Quick Actions

Quick Actions are the optional Automator fallback integration. They still work without a full Xcode/Finder Sync build, but the current daily-driver install uses the native Finder Sync extension instead so actions appear directly in Finder's main right-click menu.

## Installed Actions

- `RightMenu Copy Selected Path`
- `RightMenu Copy Selected Name`
- `RightMenu Copy Parent Path`
- `RightMenu Copy Shell Path`
- `RightMenu Copy Git Relative Path`
- `RightMenu Copy Current Finder Path`
- `RightMenu Open Terminal at Selected`
- `RightMenu Open Terminal Here`
- `RightMenu Open VS Code at Selected`
- `RightMenu Open VS Code Here`
- `RightMenu Open Cursor at Selected`
- `RightMenu Open Cursor Here`
- `RightMenu New Text File Here`
- `RightMenu New Markdown File Here`
- `RightMenu New JSON File Here`
- `RightMenu Zip Selected Items`

## Install

```sh
python3 scripts/install-quick-actions.py install
```

Useful lifecycle commands:

```sh
python3 scripts/install-quick-actions.py build
python3 scripts/install-quick-actions.py status
python3 scripts/install-quick-actions.py uninstall
python3 scripts/doctor.py --quick-actions
```

The installer writes generated `.workflow` packages to `quick-actions/` and installs copies into:

```text
~/Library/Services
```

It then refreshes the macOS services cache and restarts Finder.

For the native daily-driver setup, keep these workflows uninstalled:

```sh
python3 scripts/install-quick-actions.py uninstall
```

## Usage

In Finder:

- Right-click selected files or folders, then choose `Quick Actions` or `Services`.
- For current-folder actions, use the Finder window that is currently frontmost.

If items do not appear, enable them under:

```text
System Settings > Keyboard > Keyboard Shortcuts > Services > Files and Folders
```

The current-folder actions use AppleScript to read the front Finder window, so macOS may ask for Automation permission the first time.

## Verified Locally

- Selected path, selected name, parent path, Git-relative path, shell path, zip selected items.
- Current Finder path using a temporary Finder window.
- New text file creation using a temporary Finder window.
- Terminal open action through Automator.

Re-run fallback verification any time with:

```sh
python3 scripts/doctor.py --quick-actions
```
