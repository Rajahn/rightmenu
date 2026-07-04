# RightMenu

RightMenu is a macOS Finder right-click enhancement tool for self-use first, with a product-grade foundation.

The project goal is to cover the common daily value of tools like iRightMouse: copy paths, create files, open tools, move files, run utilities, and eventually support custom action packs.

## Built-In Actions So Far

- Copy absolute paths, file URLs, file names, parent directories, Markdown links, and shell-escaped paths.
- Windows-style file copy / cut / paste in Finder.
- Smart clipboard history with automatic categories.
- Create text, Markdown, JSON, and YAML files with conflict-safe names.
- Open the current directory in Terminal, VS Code, or Cursor through shell actions.

## Current Shape

- `RightMenuCore`: Swift package with the action model, built-in actions, script runner, and tests.
- `rightmenu-cli`: local command-line harness for validating actions before Finder integration exists.
- `native/`: command-line-buildable macOS app plus Finder Sync extension for prominent Finder context-menu items.
- `RightMenuNative.app`: installed local menu-bar app for clipboard history and Finder action settings.
- `macos/RightMenuApp`: future SwiftUI product app shell.
- `macos/RightMenuFinderExtension`: future Xcode Finder Sync extension shell.
- `docs/`: product and architecture notes.

## Local Development

```sh
swift run rightmenu-smoke-tests
swift run rightmenu-cli list
swift run rightmenu-cli run copy.absolute-paths README.md
swift run rightmenu-cli run create.markdown-file .
python3 scripts/doctor.py
```

## Install Native Finder Context Menu

```sh
python3 scripts/build-native-finder-sync.py install
python3 scripts/build-native-finder-sync.py status
python3 scripts/build-native-finder-sync.py list-actions
```

This installs `/Applications/RightMenuNative.app`, registers `com.huoran.rightmenu.findersync`, and restarts Finder. The native Finder Sync menu is the primary self-use surface because it appears in Finder's normal right-click menu instead of being buried under Services.

Open the control panel from the menu-bar icon or with:

```sh
open /Applications/RightMenuNative.app
```

The control panel can enable or hide individual native right-click actions and then apply changes to Finder.

The menu-bar app also exposes `剪贴板历史`, which records recent clipboard content and classifies it as text, links, files/paths, code, images, or pinned items.

## Optional Finder Quick Actions Fallback

```sh
python3 scripts/install-quick-actions.py install
python3 scripts/install-quick-actions.py uninstall
```

Quick Actions install fallback Finder Services. They are useful for compatibility testing, but the current daily-driver install keeps them uninstalled to avoid duplicate `服务` menu entries.

See [docs/NATIVE_FINDER_SYNC.md](docs/NATIVE_FINDER_SYNC.md) for the primary native Finder integration.
See [docs/CLIPBOARD_HISTORY.md](docs/CLIPBOARD_HISTORY.md) for the smart clipboard history.
See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the current toolchain constraint.
See [docs/QUICK_ACTIONS.md](docs/QUICK_ACTIONS.md) for the optional fallback integration.
See [docs/ACTION_MANIFEST.md](docs/ACTION_MANIFEST.md) for the shared action metadata contract.
