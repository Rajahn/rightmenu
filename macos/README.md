# macOS Targets

This directory holds source intended for the native macOS app and Finder Sync extension.

The current machine has Swift Command Line Tools but not a full active Xcode installation. The local self-use native build lives in `native/` and is installed with `scripts/build-native-finder-sync.py`.

Once Xcode is available, this directory should become the product-grade app project:

1. Create a macOS SwiftUI app target named `RightMenuApp`.
2. Add a Finder Sync Extension target named `RightMenuFinderExtension`.
3. Link both targets to `RightMenuCore`.
4. Enable App Sandbox for the Finder extension and keep its responsibilities minimal.
5. Move the current `native/RightMenuFinderSync.swift` behavior behind the shared `RightMenuCore` action execution bridge.
