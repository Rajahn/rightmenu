# Native Finder Sync

The native Finder Sync integration is the primary self-use surface for RightMenu. It puts common actions directly in Finder's context menu with SF Symbol icons, instead of hiding them under Services or Quick Actions.

## Install

```sh
python3 scripts/build-native-finder-sync.py install
```

The installer:

- Builds `RightMenuNative.app` and `RightMenuFinderExtension.appex` with Swift Command Line Tools.
- Signs the Finder extension with the required sandbox and user-selected file entitlements.
- Installs the app into `/Applications/RightMenuNative.app`.
- Registers and enables `com.huoran.rightmenu.findersync` with `pluginkit`.
- Restarts Finder.
- Opens the menu-bar control panel.

Check status with:

```sh
python3 scripts/build-native-finder-sync.py status
/usr/bin/pluginkit -m -v -A -D -p com.apple.FinderSync
```

The expected state is a `+` next to `com.huoran.rightmenu.findersync`.

## Current Actions

The native menu is declared in `native/rightmenu-native-actions.json` and packaged into the Finder extension during build.

- Copy path or current folder path
- Copy shell-escaped path
- Copy name
- Copy parent path
- Copy Git-relative path
- Copy selected items
- Cut selected items
- Paste copied or cut items here
- Open in Terminal
- Open in VS Code
- Open in Cursor
- New text file
- New Markdown file
- Zip selected items

## Configure Visible Actions

Open the native control panel:

```sh
open /Applications/RightMenuNative.app
```

The control panel shows every native Finder action with a checkbox. Toggle actions, then click `应用到 Finder` to restart Finder and refresh the right-click menu. The app also exposes a menu-bar icon with:

- `打开控制面板`
- `应用到 Finder`
- `扩展设置`
- `退出 RightMenu`

List native actions:

```sh
python3 scripts/build-native-finder-sync.py list-actions
```

Disable or enable one action:

```sh
python3 scripts/build-native-finder-sync.py disable native.open.cursor
python3 scripts/build-native-finder-sync.py enable native.open.cursor
```

Reset all actions:

```sh
python3 scripts/build-native-finder-sync.py enable-all
```

The config file lives in the Finder extension sandbox container:

```sh
python3 scripts/build-native-finder-sync.py config-path
```

The script restarts Finder after changes so the context menu refreshes.

## File Copy / Cut / Paste

The native menu includes Windows-style file operations:

- `复制项目`: stores the selected files or folders in RightMenu's file operation buffer.
- `剪切项目`: stores the selected files or folders as a move operation.
- `粘贴到这里` / `粘贴到当前文件夹`: copies or moves buffered items into the selected folder, selected file's parent folder, or empty-area target folder.

Copy operations keep the buffer so the same items can be pasted again. Cut operations clear the buffer after a successful paste. Name conflicts are resolved with `copy`, `copy 2`, and later suffixes.

The Finder Sync extension remains sandboxed so Finder loads it reliably. For the current self-use build, paste execution is delegated through the `rightmenu://paste-items` URL scheme to the unsandboxed `RightMenuNative.app` host. The product version should replace this with a signed main-app execution bridge and security-scoped access.

## Remove Quick Actions Fallback

The native Finder menu is now the main self-use surface. If old Automator fallback actions were installed, remove them to avoid duplicate `服务` entries:

```sh
python3 scripts/install-quick-actions.py uninstall
```

## Disable iRightMouse Finder Extension

RightMenu can coexist with other Finder Sync providers, but for replacement testing the old iRightMouse extension can be disabled without uninstalling its app:

```sh
/usr/bin/pluginkit -e ignore -i cn.better365.iRightMouse.Extension
/usr/bin/killall Finder
```

Re-enable it with:

```sh
/usr/bin/pluginkit -e use -i cn.better365.iRightMouse.Extension
/usr/bin/killall Finder
```

## Maintainability Notes

The current native extension executes actions directly because that gets the local machine usable without a full Xcode project. The product direction is:

- Keep Finder Sync as a thin context reader and menu renderer.
- Move execution to `RightMenuCore` or a main-app bridge.
- Keep visible native menu metadata in `native/rightmenu-native-actions.json`, then consolidate it with `actions/rightmenu-actions.json` once the settings UI exists.
- Keep the current AppKit control panel as the self-use configuration surface until the product SwiftUI app replaces it.
- Package with a Developer ID certificate and notarization for distribution.
