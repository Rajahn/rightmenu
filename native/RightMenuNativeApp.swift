import Cocoa
import Carbon

private let finderExtensionBundleID = "com.huoran.rightmenu.findersync"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var controller: ControlPanelController?
    private var clipboardHotKey: GlobalHotKey?
    private let fileOperationService = NativeFileOperationService()
    private let clipboardHistory = ClipboardHistoryCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerURLHandler()
        clipboardHistory.start()
        configureStatusItem()
        registerClipboardHistoryHotKey()
    }

    private func registerURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.toolTip = "RightMenu · 剪贴板历史 ⌃⌥V"
            if #available(macOS 11.0, *) {
                button.image = NSImage(
                    systemSymbolName: "contextualmenu.and.cursorarrow",
                    accessibilityDescription: "RightMenu"
                )
            } else {
                button.title = "RM"
            }
        }

        let menu = NSMenu()
        let historyItem = NSMenuItem(title: "打开剪贴板历史", action: #selector(showClipboardHistory(_:)), keyEquivalent: "v")
        historyItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(historyItem)
        menu.addItem(NSMenuItem(title: "右键配置面板", action: #selector(showControlPanel(_:)), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "应用到 Finder", action: #selector(restartFinder), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "扩展设置", action: #selector(openExtensionSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 RightMenu", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil {
            item.target = self
        }

        item.menu = menu
        statusItem = item
    }

    @objc private func showClipboardHistory(_ sender: Any?) {
        clipboardHistory.showWindow()
    }

    private func registerClipboardHistoryHotKey() {
        clipboardHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(controlKey | optionKey),
            signature: fourCharCode("RMCH"),
            id: 1
        ) { [weak self] in
            self?.clipboardHistory.toggleQuickWindow()
        }
        clipboardHotKey?.register()
    }

    @objc private func showControlPanel(_ sender: Any?) {
        if controller == nil {
            controller = ControlPanelController()
        }
        controller?.showPanel()
    }

    @objc private func restartFinder() {
        FinderReloader.restart()
        controller?.markApplied()
    }

    @objc private func openExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func handleGetURLEvent(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: rawURL),
              url.scheme == "rightmenu" else {
            return
        }

        if url.host == "paste-items" {
            handlePasteItems(url)
        } else if url.host == "clipboard-history" {
            clipboardHistory.showWindow()
        } else if url.host == "control-panel" {
            showControlPanel(nil)
        }
    }

    private func handlePasteItems(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let destination = components.queryItems?.first(where: { $0.name == "destination" })?.value,
              !destination.isEmpty else {
            return fail(RightMenuAppError("缺少粘贴目标目录"))
        }

        do {
            let pasted = try fileOperationService.pasteItems(into: URL(fileURLWithPath: destination))
            if !pasted.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(pasted)
            }
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        NSLog("RightMenu app error: %@", String(describing: error))
        NSSound.beep()
    }
}

final class ControlPanelController: NSWindowController {
    private let manifest = NativeActionManifest.load()
    private let configStore = NativeActionConfigStore()
    private let statusLabel = NSTextField(labelWithString: "")
    private let rowsStack = FlippedStackView()
    private var checkboxes: [String: NSButton] = [:]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RightMenu"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        super.init(window: window)
        buildContent()
        reloadRows()
        centerOnMainScreen()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        root.addArrangedSubview(headerView())
        root.addArrangedSubview(separator())
        root.addArrangedSubview(scrollView())
        root.addArrangedSubview(separator())
        root.addArrangedSubview(footerView())
    }

    private func headerView() -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        if #available(macOS 11.0, *) {
            imageView.image = NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: "RightMenu")
        }
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.widthAnchor.constraint(equalToConstant: 34).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 34).isActive = true
        container.addArrangedSubview(imageView)

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3

        let title = NSTextField(labelWithString: "RightMenu 控制面板")
        title.font = .systemFont(ofSize: 19, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Finder 右键主菜单动作")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        labels.addArrangedSubview(title)
        labels.addArrangedSubview(subtitle)
        container.addArrangedSubview(labels)
        return container
    }

    private func scrollView() -> NSScrollView {
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 10
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = rowsStack
        scroll.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),
            rowsStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        return scroll
    }

    private func footerView() -> NSView {
        let footer = NSStackView()
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 12

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let enableAll = NSButton(title: "全部启用", target: self, action: #selector(enableAllActions))
        let disableAll = NSButton(title: "全部隐藏", target: self, action: #selector(disableAllActions))
        let apply = NSButton(title: "应用到 Finder", target: self, action: #selector(applyToFinder))
        apply.bezelStyle = .rounded
        if #available(macOS 11.0, *) {
            apply.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "应用到 Finder")
            apply.imagePosition = .imageLeading
        }

        buttons.addArrangedSubview(enableAll)
        buttons.addArrangedSubview(disableAll)
        buttons.addArrangedSubview(NSView())
        buttons.addArrangedSubview(apply)
        buttons.distribution = .fill
        buttons.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "更改会立即保存；应用到 Finder 后右键菜单刷新。"

        footer.addArrangedSubview(buttons)
        footer.addArrangedSubview(statusLabel)
        NSLayoutConstraint.activate([
            buttons.widthAnchor.constraint(equalToConstant: 512)
        ])
        return footer
    }

    private func reloadRows() {
        rowsStack.arrangedSubviews.forEach { view in
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        checkboxes.removeAll()

        let disabled = configStore.disabledActionIDs()
        for (groupIndex, group) in manifest.groups.enumerated() {
            if groupIndex > 0 {
                rowsStack.addArrangedSubview(groupSeparator())
            }
            for action in group {
                rowsStack.addArrangedSubview(rowView(for: action, enabled: !disabled.contains(action.id)))
            }
        }
    }

    func showPanel() {
        centerOnMainScreen()
        window?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private func centerOnMainScreen() {
        guard let window,
              let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let visibleFrame = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = visibleFrame.midX - frame.width / 2
        frame.origin.y = visibleFrame.midY - frame.height / 2
        window.setFrame(frame, display: true)
    }

    private func rowView(for action: NativeActionSpec, enabled: Bool) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let checkbox = ActionCheckbox(checkboxWithTitle: "", target: self, action: #selector(toggleAction(_:)))
        checkbox.state = enabled ? .on : .off
        checkbox.actionID = action.id
        checkbox.toolTip = action.title
        checkbox.setAccessibilityLabel(action.title)
        checkbox.setContentHuggingPriority(.required, for: .horizontal)
        checkboxes[action.id] = checkbox
        row.addArrangedSubview(checkbox)

        let symbol = NSImageView()
        if #available(macOS 11.0, *) {
            symbol.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.title)
            symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        }
        symbol.contentTintColor = .secondaryLabelColor
        symbol.widthAnchor.constraint(equalToConstant: 22).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(symbol)

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        let title = NSTextField(labelWithString: action.title)
        title.font = .systemFont(ofSize: 14, weight: .medium)

        let detail = NSTextField(labelWithString: action.detailText)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor

        labels.addArrangedSubview(title)
        labels.addArrangedSubview(detail)
        row.addArrangedSubview(labels)

        row.widthAnchor.constraint(equalToConstant: 512).isActive = true
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func groupSeparator() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 6).isActive = true
        return view
    }

    @objc private func toggleAction(_ sender: NSButton) {
        guard let checkbox = sender as? ActionCheckbox else {
            return
        }
        configStore.setAction(checkbox.actionID, enabled: sender.state == .on, allActions: manifest.allActionIDs)
        markPending()
    }

    @objc private func enableAllActions() {
        configStore.saveDisabledActionIDs([])
        reloadRows()
        markPending()
    }

    @objc private func disableAllActions() {
        configStore.saveDisabledActionIDs(manifest.allActionIDs)
        reloadRows()
        markPending()
    }

    @objc private func applyToFinder() {
        FinderReloader.restart()
        markApplied()
    }

    func markApplied() {
        statusLabel.stringValue = "已应用到 Finder。"
    }

    private func markPending() {
        statusLabel.stringValue = "已保存，等待应用到 Finder。"
    }
}

private final class ActionCheckbox: NSButton {
    var actionID = ""
}

private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool {
        true
    }
}

private enum FinderReloader {
    static func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
    }
}

private struct NativeActionManifest: Decodable {
    let schemaVersion: Int
    let groups: [[NativeActionSpec]]

    var allActionIDs: [String] {
        groups.flatMap { $0.map(\.id) }
    }

    static func load() -> NativeActionManifest {
        guard let url = Bundle.main.url(forResource: "rightmenu-native-actions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(NativeActionManifest.self, from: data),
              manifest.schemaVersion == 1 else {
            return NativeActionManifest(schemaVersion: 1, groups: [])
        }
        return manifest
    }
}

private struct NativeActionSpec: Decodable {
    enum Visibility: String, Decodable {
        case always
        case selectionOnly
        case emptyOnly
    }

    let id: String
    let title: String
    let emptyTitle: String?
    let symbol: String
    let visibility: Visibility
    let handler: String

    var detailText: String {
        switch visibility {
        case .always:
            return emptyTitle == nil ? "选中文件和当前文件夹" : "选中文件 / 当前文件夹"
        case .selectionOnly:
            return "仅选中文件或文件夹"
        case .emptyOnly:
            return "仅当前文件夹"
        }
    }
}

private enum RightMenuSharedPaths {
    static var extensionAppSupportURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/\(finderExtensionBundleID)/Data/Library/Application Support/RightMenu", isDirectory: true)
    }
}

private enum NativeFileOperation: String, Codable {
    case copy
    case cut
}

private struct NativeFileOperationBuffer: Codable {
    let schemaVersion: Int
    let operation: NativeFileOperation
    let paths: [String]

    var urls: [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }
}

private final class NativeFileOperationStore {
    private var fileURL: URL {
        RightMenuSharedPaths.extensionAppSupportURL.appendingPathComponent("file-operation-buffer.json")
    }

    func loadRequired() throws -> NativeFileOperationBuffer {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RightMenuAppError("没有可粘贴的项目")
        }
        let data = try Data(contentsOf: fileURL)
        let buffer = try JSONDecoder().decode(NativeFileOperationBuffer.self, from: data)
        guard buffer.schemaVersion == 1, !buffer.paths.isEmpty else {
            throw RightMenuAppError("粘贴缓冲区无效")
        }
        return buffer
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }
}

private final class NativeFileOperationService {
    private let store = NativeFileOperationStore()
    private let fileManager = FileManager.default

    func pasteItems(into directory: URL) throws -> [URL] {
        let buffer = try store.loadRequired()
        let destinationDirectory = normalized(directory)
        var pasted: [URL] = []

        for source in buffer.urls {
            let sourceURL = normalized(source)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw RightMenuAppError("源项目不存在: \(source.path)")
            }
            if isDirectory(sourceURL), isDescendant(destinationDirectory, of: sourceURL) {
                throw RightMenuAppError("不能把文件夹粘贴到它自己的子目录: \(source.path)")
            }

            if buffer.operation == .cut,
               normalized(sourceURL.deletingLastPathComponent()) == destinationDirectory {
                pasted.append(sourceURL)
                continue
            }

            let destinationURL = nextAvailableURL(in: destinationDirectory, preservingNameOf: sourceURL)
            do {
                switch buffer.operation {
                case .copy:
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                case .cut:
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                }
            } catch {
                throw RightMenuAppError("粘贴失败: \(sourceURL.path) -> \(destinationURL.path), \(error.localizedDescription)")
            }
            pasted.append(destinationURL)
        }

        if buffer.operation == .cut {
            try store.clear()
        }
        return pasted
    }

    private func nextAvailableURL(in directory: URL, preservingNameOf sourceURL: URL) -> URL {
        let originalName = sourceURL.lastPathComponent
        let baseName = (originalName as NSString).deletingPathExtension
        let pathExtension = (originalName as NSString).pathExtension
        var index = 1

        while true {
            let name: String
            if index == 1 {
                name = originalName
            } else {
                let suffix = index == 2 ? " copy" : " copy \(index)"
                name = pathExtension.isEmpty ? "\(baseName)\(suffix)" : "\(baseName)\(suffix).\(pathExtension)"
            }

            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func isDescendant(_ url: URL, of possibleAncestor: URL) -> Bool {
        let path = normalized(url).path
        let ancestorPath = normalized(possibleAncestor).path
        return path != ancestorPath && path.hasPrefix(ancestorPath + "/")
    }
}

private final class NativeActionConfigStore {
    private var configURL: URL {
        RightMenuSharedPaths.extensionAppSupportURL.appendingPathComponent("native-actions-config.json")
    }

    func disabledActionIDs() -> Set<String> {
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let disabled = object["disabledActionIDs"] as? [String] else {
            return []
        }
        return Set(disabled)
    }

    func setAction(_ id: String, enabled: Bool, allActions: [String]) {
        var disabled = disabledActionIDs()
        if enabled {
            disabled.remove(id)
        } else {
            disabled.insert(id)
        }
        let known = Set(allActions)
        saveDisabledActionIDs(disabled.filter { known.contains($0) }.sorted())
    }

    func saveDisabledActionIDs(_ ids: [String]) {
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "disabledActionIDs": ids.sorted()
        ]
        do {
            let directory = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: .atomic)
        } catch {
            NSLog("RightMenu failed to save native action config: %@", String(describing: error))
        }
    }
}

private struct RightMenuAppError: LocalizedError, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }

    var description: String {
        message
    }
}

@main
enum RightMenuNativeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
