# MVP Scope

## Phase 1: Useful Self-Use Core

- Copy absolute paths
- Copy file URLs
- Copy file names
- Copy parent directories
- Copy Markdown links
- Copy shell-escaped paths
- Copy Git-relative paths
- New text file
- New Markdown file
- New JSON / YAML file
- Cut / Paste Here
- MD5 / SHA-256
- Zip selected items
- Execution log and JSON config store
- CLI harness for local action testing
- Smoke-test executable for current no-Xcode environment
- Native Finder Sync MVP with prominent right-click menu actions
- Native Finder action manifest and per-action enable/disable config
- AppKit menu-bar control panel for enabling or hiding native Finder actions
- Native Windows-style file copy / cut / paste, with Finder Sync delegating paste execution to the host app
- Smart clipboard history with local classification, search, re-copy, pin, and delete
- Optional Automator Quick Actions fallback, kept uninstalled by default to avoid duplicate Services entries

## Phase 2: Finder Integration

- Product-grade SwiftUI menu-bar app replacing the temporary AppKit control panel
- Xcode-managed Finder Sync extension
- Finder extension enablement guide
- Context menu generation from `ActionCatalog`
- Main app action execution bridge

## Phase 3: Daily Driver Coverage

- Configurable Finder Sync menu for Open in Terminal / VS Code / Cursor
- Favorite directories
- Copy To / Move To favorite directory
- Image conversion shell action pack

## Phase 4: Productization

- Configurable action editor
- Script action packs
- Execution log
- Permission health screen
- Signed and notarized DMG
- Auto-update channel
