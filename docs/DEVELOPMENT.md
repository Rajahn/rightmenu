# Development

## Current Toolchain State

This machine currently has Apple Swift Command Line Tools, but not a full active Xcode installation:

- `swift build` works.
- `swift run rightmenu-smoke-tests` works.
- `python3 scripts/build-native-finder-sync.py install` builds and installs the current local Finder Sync MVP.
- `swift test` is not used yet because the current Command Line Tools environment does not provide the usual test modules.
- `xcodebuild` cannot build a product-grade Xcode app-extension target until full Xcode is installed or selected.

## Validation Commands

```sh
swift build
swift run rightmenu-smoke-tests
swift run rightmenu-cli list
python3 scripts/install-quick-actions.py build
python3 scripts/build-native-finder-sync.py build
python3 scripts/doctor.py
```

For fallback Automator workflow checks:

```sh
python3 scripts/doctor.py --quick-actions
```

By default, the doctor script validates Swift build/smoke tests, generated manifests, native Finder Sync build, the installed native extension, native action config, and that old fallback Quick Actions are not installed. The `--quick-actions` mode validates generated workflow plists, installed workflow files, macOS Services registration, and safe workflow behavior through `automator`.

When adding or renaming a user-facing action, update the relevant manifest first. Current native menu entries live in `native/rightmenu-native-actions.json`; shared product action metadata lives in `actions/rightmenu-actions.json`.

## Native Finder Integration

The local native integration is built manually with Swift Command Line Tools:

```sh
python3 scripts/build-native-finder-sync.py install
python3 scripts/build-native-finder-sync.py status
python3 scripts/build-native-finder-sync.py list-actions
open /Applications/RightMenuNative.app
```

The script creates a signed app-extension bundle, preserves the required app-extension entitlements, installs it into `/Applications`, enables it through `pluginkit`, opens the control panel, and restarts Finder.

Native Finder menu metadata lives in `native/rightmenu-native-actions.json`. The build script validates handler names and copies this manifest into both the app bundle and extension bundle so the control panel and Finder extension read the same action list.

The Finder Sync extension is sandboxed. File copy/cut/paste uses a shared buffer in the extension container; paste execution is delegated to the unsandboxed local host app through the registered `rightmenu://paste-items` URL scheme.

## Smart Clipboard History

Clipboard history lives in the native host app:

- UI and monitoring: `native/RightMenuClipboardHistory.swift`
- Persistence: `~/Library/Application Support/RightMenu/clipboard-history.json`
- Entry point: menu-bar item `剪贴板历史`

The monitor polls `NSPasteboard.general.changeCount`, classifies supported content locally, and keeps at most 100 unpinned records plus pinned records.

For long-term product packaging, install Xcode and run:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

After that, replace the manual bundle build with normal app and Finder Sync extension targets around the existing `RightMenuCore` package, then sign and notarize the distributed app.
