import Cocoa
import FinderSync
import RightMenuCore

final class FinderSync: FIFinderSync {
    override init() {
        super.init()

        // Broad monitoring is acceptable for the first self-use build. Later product builds
        // should make monitored roots configurable and explain Finder Sync limitations.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: NSHomeDirectory())
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "RightMenu")

        for action in ActionCatalog.builtIns {
            let item = NSMenuItem(
                title: action.title,
                action: #selector(runAction(_:)),
                keyEquivalent: ""
            )
            item.representedObject = action.id
            item.target = self
            menu.addItem(item)
        }

        return menu
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let actionID = sender.representedObject as? String else {
            return
        }

        // The extension should forward this request to the main app execution bridge.
        // Direct execution from the extension is intentionally avoided for maintainability.
        NSLog("RightMenu action requested: \(actionID)")
    }
}

