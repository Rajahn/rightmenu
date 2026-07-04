import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    private let manifest = NativeActionManifest.load()
    private let fileOperationStore = NativeFileOperationStore()

    override init() {
        super.init()

        FIFinderSyncController.default().directoryURLs = Set([
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: NSHomeDirectory()),
            URL(fileURLWithPath: "/Users"),
            URL(fileURLWithPath: "/Volumes"),
            URL(fileURLWithPath: "/private"),
            URL(fileURLWithPath: "/tmp")
        ])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "RightMenu")
        let useSelection = shouldUseSelection(for: menuKind)
        let hasSelection = useSelection && !selectedURLs().isEmpty
        let disabled = NativeActionConfig.disabledActionIDs()
        var addedGroup = false

        for group in manifest.groups {
            let visibleActions = group.filter { action in
                !disabled.contains(action.id) && action.isVisible(hasSelection: hasSelection)
            }
            guard !visibleActions.isEmpty else {
                continue
            }

            if addedGroup {
                menu.addItem(NSMenuItem.separator())
            }

            for action in visibleActions {
                guard let selector = selector(for: action.handler) else {
                    NSLog("RightMenu FinderSync missing handler: %@", action.handler)
                    continue
                }
                let item = addItem(
                    to: menu,
                    title: action.title(hasSelection: hasSelection),
                    symbol: action.symbol,
                    actionID: action.id,
                    useSelection: useSelection,
                    action: selector
                )
                if action.handler == "pasteItems" {
                    item.isEnabled = fileOperationStore.hasBuffer()
                }
            }
            addedGroup = true
        }

        return menu
    }

    @discardableResult
    private func addItem(
        to menu: NSMenu,
        title: String,
        symbol: String,
        actionID: String,
        useSelection: Bool,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = [
            "actionID": actionID,
            "useSelection": useSelection
        ] as NSDictionary
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        }
        menu.addItem(item)
        return item
    }

    private func selector(for handler: String) -> Selector? {
        switch handler {
        case "copyPath":
            return #selector(copyPath(_:))
        case "copyShellPath":
            return #selector(copyShellPath(_:))
        case "copyName":
            return #selector(copyName(_:))
        case "copyParentPath":
            return #selector(copyParentPath(_:))
        case "copyGitRelativePath":
            return #selector(copyGitRelativePath(_:))
        case "copyItems":
            return #selector(copyItems(_:))
        case "cutItems":
            return #selector(cutItems(_:))
        case "pasteItems":
            return #selector(pasteItems(_:))
        case "openTerminal":
            return #selector(openTerminal(_:))
        case "openVSCode":
            return #selector(openVSCode(_:))
        case "openCursor":
            return #selector(openCursor(_:))
        case "newTextFile":
            return #selector(newTextFile(_:))
        case "newMarkdownFile":
            return #selector(newMarkdownFile(_:))
        case "zipSelectedItems":
            return #selector(zipSelectedItems(_:))
        default:
            return nil
        }
    }

    private func shouldUseSelection(for menuKind: FIMenuKind) -> Bool {
        switch menuKind {
        case .contextualMenuForContainer:
            return false
        default:
            return true
        }
    }

    private func shouldUseSelection(for sender: NSMenuItem) -> Bool {
        guard let metadata = sender.representedObject as? NSDictionary,
              let useSelection = metadata["useSelection"] as? Bool else {
            return true
        }
        return useSelection
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        copyLines(urlsForCurrentContext(useSelection: shouldUseSelection(for: sender)).map(\.path))
    }

    @objc private func copyShellPath(_ sender: NSMenuItem) {
        copyLines(urlsForCurrentContext(useSelection: shouldUseSelection(for: sender)).map { shellQuoted($0.path) })
    }

    @objc private func copyName(_ sender: NSMenuItem) {
        copyLines(urlsForCurrentContext(useSelection: shouldUseSelection(for: sender)).map(\.lastPathComponent))
    }

    @objc private func copyParentPath(_ sender: NSMenuItem) {
        copyLines(urlsForCurrentContext(useSelection: shouldUseSelection(for: sender)).map { $0.deletingLastPathComponent().path })
    }

    @objc private func copyGitRelativePath(_ sender: NSMenuItem) {
        do {
            let lines = try urlsForCurrentContext(useSelection: shouldUseSelection(for: sender)).map { url -> String in
                guard let root = gitRoot(containing: url) else {
                    throw RightMenuError("未找到 Git 仓库: \(url.path)")
                }
                let rootPath = root.path
                let path = url.path
                if path == rootPath {
                    return "."
                }
                if path.hasPrefix(rootPath + "/") {
                    return String(path.dropFirst(rootPath.count + 1))
                }
                return path
            }
            copyLines(lines)
        } catch {
            fail(error)
        }
    }

    @objc private func copyItems(_ sender: NSMenuItem) {
        do {
            let urls = selectedURLs()
            guard !urls.isEmpty else {
                throw RightMenuError("没有选中的项目")
            }
            try fileOperationStore.save(NativeFileOperationBuffer(operation: .copy, urls: urls))
        } catch {
            fail(error)
        }
    }

    @objc private func cutItems(_ sender: NSMenuItem) {
        do {
            let urls = selectedURLs()
            guard !urls.isEmpty else {
                throw RightMenuError("没有选中的项目")
            }
            try fileOperationStore.save(NativeFileOperationBuffer(operation: .cut, urls: urls))
        } catch {
            fail(error)
        }
    }

    @objc private func pasteItems(_ sender: NSMenuItem) {
        do {
            guard let destinationDirectory = directoryForPaste(useSelection: shouldUseSelection(for: sender)) else {
                throw RightMenuError("未找到粘贴目标目录")
            }
            _ = try fileOperationStore.loadRequired()
            requestHostPaste(into: destinationDirectory)
        } catch {
            fail(error)
        }
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        guard let directory = directoryForOpening(useSelection: shouldUseSelection(for: sender)) else {
            return fail(RightMenuError("未找到可打开的目录"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", directory.path]
        do {
            try process.run()
        } catch {
            fail(error)
        }
    }

    @objc private func openVSCode(_ sender: NSMenuItem) {
        openApplication(named: "Visual Studio Code", useSelection: shouldUseSelection(for: sender))
    }

    @objc private func openCursor(_ sender: NSMenuItem) {
        openApplication(named: "Cursor", useSelection: shouldUseSelection(for: sender))
    }

    @objc private func newTextFile(_ sender: NSMenuItem) {
        createFile(baseName: "Untitled", fileExtension: "txt", contents: "", useSelection: shouldUseSelection(for: sender))
    }

    @objc private func newMarkdownFile(_ sender: NSMenuItem) {
        createFile(baseName: "Untitled", fileExtension: "md", contents: "", useSelection: shouldUseSelection(for: sender))
    }

    @objc private func zipSelectedItems(_ sender: NSMenuItem) {
        do {
            let urls = shouldUseSelection(for: sender) ? selectedURLs() : []
            guard !urls.isEmpty else {
                throw RightMenuError("没有选中的项目")
            }

            let parent = urls[0].deletingLastPathComponent()
            guard urls.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL }) else {
                throw RightMenuError("压缩要求所选项目位于同一目录")
            }

            let archive = nextAvailableURL(in: parent, baseName: "Archive", fileExtension: "zip")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = parent
            process.arguments = ["-qry", archive.path] + urls.map(\.lastPathComponent)
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw RightMenuError("zip 退出码: \(process.terminationStatus)")
            }
            NSWorkspace.shared.activateFileViewerSelecting([archive])
        } catch {
            fail(error)
        }
    }

    private func selectedURLs() -> [URL] {
        (FIFinderSyncController.default().selectedItemURLs() ?? []).map(\.standardizedFileURL)
    }

    private func targetURL() -> URL? {
        FIFinderSyncController.default().targetedURL()?.standardizedFileURL
    }

    private func urlsForCurrentContext(useSelection: Bool) -> [URL] {
        let selected = useSelection ? selectedURLs() : []
        if useSelection, !selected.isEmpty {
            return selected
        }
        if let target = targetURL() {
            return [target]
        }
        return []
    }

    private func directoryForOpening(useSelection: Bool) -> URL? {
        let selected = useSelection ? selectedURLs() : []
        if selected.count == 1 {
            let url = selected[0]
            return isDirectory(url) ? url : url.deletingLastPathComponent()
        }
        if selected.count > 1 {
            return commonParent(of: selected)
        }
        return targetURL()
    }

    private func directoryForCreation(useSelection: Bool) -> URL? {
        let selected = useSelection ? selectedURLs() : []
        if selected.count == 1, isDirectory(selected[0]) {
            return selected[0]
        }
        return targetURL()
    }

    private func directoryForPaste(useSelection: Bool) -> URL? {
        directoryForOpening(useSelection: useSelection)
    }

    private func commonParent(of urls: [URL]) -> URL? {
        guard let first = urls.first?.deletingLastPathComponent().standardizedFileURL else {
            return nil
        }
        return urls.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL == first } ? first : nil
    }

    private func createFile(baseName: String, fileExtension: String, contents: String, useSelection: Bool) {
        do {
            guard let directory = directoryForCreation(useSelection: useSelection) else {
                throw RightMenuError("未找到新建文件目录")
            }
            let url = nextAvailableURL(in: directory, baseName: baseName, fileExtension: fileExtension)
            try contents.data(using: .utf8)?.write(to: url, options: .withoutOverwriting)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            fail(error)
        }
    }

    private func nextAvailableURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        let fileManager = FileManager.default
        var index = 1
        while true {
            let suffix = index == 1 ? "" : " \(index)"
            let candidate = directory.appendingPathComponent("\(baseName)\(suffix)").appendingPathExtension(fileExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func openApplication(named appName: String, useSelection: Bool) {
        guard let directory = directoryForOpening(useSelection: useSelection) else {
            return fail(RightMenuError("未找到可打开的目录"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName, directory.path]
        do {
            try process.run()
        } catch {
            fail(error)
        }
    }

    private func requestHostPaste(into directory: URL) {
        var components = URLComponents()
        components.scheme = "rightmenu"
        components.host = "paste-items"
        components.queryItems = [
            URLQueryItem(name: "destination", value: directory.standardizedFileURL.path)
        ]
        guard let url = components.url else {
            return fail(RightMenuError("无法构造粘贴请求"))
        }
        NSWorkspace.shared.open(url)
    }

    private func copyLines(_ lines: [String]) {
        guard !lines.isEmpty else {
            return fail(RightMenuError("没有可复制的内容"))
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func gitRoot(containing url: URL) -> URL? {
        var current = isDirectory(url) ? url : url.deletingLastPathComponent()
        let fileManager = FileManager.default

        while true {
            if fileManager.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func fail(_ error: Error) {
        NSLog("RightMenu FinderSync error: %@", String(describing: error))
        NSSound.beep()
    }
}

private struct RightMenuError: LocalizedError, CustomStringConvertible {
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

private struct NativeActionManifest: Decodable {
    let schemaVersion: Int
    let groups: [[NativeActionSpec]]

    static func load() -> NativeActionManifest {
        let fallback = NativeActionManifest(schemaVersion: 1, groups: [])
        guard let url = Bundle(for: FinderSync.self).url(
            forResource: "rightmenu-native-actions",
            withExtension: "json"
        ) else {
            NSLog("RightMenu FinderSync native action manifest missing")
            return fallback
        }

        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(NativeActionManifest.self, from: data)
            guard manifest.schemaVersion == 1 else {
                throw RightMenuError("Unsupported native action manifest schema: \(manifest.schemaVersion)")
            }
            return manifest
        } catch {
            NSLog("RightMenu FinderSync native action manifest load failed: %@", String(describing: error))
            return fallback
        }
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

    func isVisible(hasSelection: Bool) -> Bool {
        switch visibility {
        case .always:
            return true
        case .selectionOnly:
            return hasSelection
        case .emptyOnly:
            return !hasSelection
        }
    }

    func title(hasSelection: Bool) -> String {
        if !hasSelection, let emptyTitle {
            return emptyTitle
        }
        return title
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

    init(operation: NativeFileOperation, urls: [URL]) {
        self.schemaVersion = 1
        self.operation = operation
        self.paths = urls.map(\.path)
    }

    var urls: [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }
}

private final class NativeFileOperationStore {
    private var fileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RightMenu", isDirectory: true)
            .appendingPathComponent("file-operation-buffer.json")
    }

    func hasBuffer() -> Bool {
        (try? load()) != nil
    }

    func loadRequired() throws -> NativeFileOperationBuffer {
        guard let buffer = try load() else {
            throw RightMenuError("没有可粘贴的项目")
        }
        return buffer
    }

    func load() throws -> NativeFileOperationBuffer? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        let buffer = try JSONDecoder().decode(NativeFileOperationBuffer.self, from: data)
        guard buffer.schemaVersion == 1, !buffer.paths.isEmpty else {
            return nil
        }
        return buffer
    }

    func save(_ buffer: NativeFileOperationBuffer) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(buffer)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }
}

private enum NativeActionConfig {
    static func disabledActionIDs() -> Set<String> {
        guard let data = try? Data(contentsOf: configURL()),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let disabled = object["disabledActionIDs"] as? [String] else {
            return []
        }
        return Set(disabled)
    }

    private static func configURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RightMenu", isDirectory: true)
            .appendingPathComponent("native-actions-config.json")
    }
}
