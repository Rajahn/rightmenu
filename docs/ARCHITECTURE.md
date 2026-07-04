# Architecture

## Design Principle

The Finder extension should stay thin. It reads Finder selection context, renders menu items, and forwards action requests. The main app and core library own configuration, execution, logging, and safety rules.

## Layers

- `RightMenuCore`
  - Action definitions
  - Context matching
  - Built-in action execution
  - Shell script execution contract
  - Testable file and clipboard operations

- `RightMenuApp`
  - SwiftUI menu-bar app
  - Action settings
  - Template management
  - Favorite directories
  - Permission onboarding
  - Execution history

- `RightMenuFinderExtension`
  - Finder Sync extension
  - Contextual menu generation
  - Selected file and target folder capture
  - Delegation to the main app or shared action runner

- `native/RightMenuFinderSync.swift`
  - Current self-use Finder Sync implementation built without a full Xcode project
  - Prominent Finder context-menu actions with SF Symbols
  - Direct execution for the first local MVP
  - File copy/cut state capture and `rightmenu://paste-items` delegation for paste execution
  - Should be folded back into the shared action catalog/execution bridge as the product app matures

- `native/RightMenuNativeApp.swift`
  - Current AppKit menu-bar control panel
  - Reads the same native action manifest packaged into the app bundle
  - Writes per-action visibility config into the Finder extension container
  - Executes paste copy/move requests from the Finder extension in the current self-use build
  - Restarts Finder after applying changes

## Action Contract

Each action has:

- Stable `id`
- Localized title
- Category
- Supported Finder contexts
- Destructive/confirmation flags
- Timeout
- Built-in handler or shell script handler

Product-level action metadata lives in `actions/rightmenu-actions.json`. Current native menu metadata lives in `native/rightmenu-native-actions.json` because the command-line-buildable Finder Sync extension is still a self-use bridge. These manifests should converge once the product app owns settings and execution dispatch. Swift implementation details still live in `ActionCatalog`, but actions that overlap should declare `coreActionID` in the manifest to prevent product surface drift.

Shell actions receive:

- `$1 ... $n`: selected item paths, or target directory for empty-area actions
- `RIGHTMENU_PATHS`: newline-separated paths
- `RIGHTMENU_TARGET_DIR`: best known target directory

## Product Boundary

The first product-quality boundary is not "all Super Right Click features." It is a reliable action platform with a small set of daily-use built-ins.

For self-use, the primary Finder surface is now the native Finder Sync extension installed by `scripts/build-native-finder-sync.py`. Automator Quick Actions remain as a compatibility fallback and as a low-friction way to validate action ideas, but they are not installed by default because they duplicate native actions under Finder's `服务` menu.

The current copy/cut/paste implementation is intentionally split: the Finder Sync extension is sandboxed and owns menu/context capture, while the unsandboxed local host app executes the actual file copy/move through a `rightmenu://` URL request. This is acceptable for the self-use build; product packaging should replace it with a formal app-extension-to-main-app execution channel and security-scoped file access.
