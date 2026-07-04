import Cocoa

private let clipboardHistoryMaxItems = 100

enum ClipboardHistoryCategory: String, Codable, CaseIterable {
    case text
    case link
    case filePath
    case code
    case image

    var title: String {
        switch self {
        case .text:
            return "文本"
        case .link:
            return "链接"
        case .filePath:
            return "文件/路径"
        case .code:
            return "代码"
        case .image:
            return "图片"
        }
    }

    var symbolName: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .link:
            return "link"
        case .filePath:
            return "folder"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .image:
            return "photo"
        }
    }
}

struct ClipboardHistoryRecord: Codable, Equatable {
    let id: String
    var category: ClipboardHistoryCategory
    var text: String?
    var filePaths: [String]
    var imageTIFFData: Data?
    var preview: String
    var detail: String
    var signature: String
    var isPinned: Bool
    var createdAt: Date
    var lastCopiedAt: Date

    var canOpenURL: URL? {
        guard category == .link,
              let value = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return url
    }
}

enum ClipboardHistoryFilter: Int, CaseIterable {
    case all
    case pinned
    case text
    case link
    case filePath
    case code
    case image

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .pinned:
            return "固定"
        case .text:
            return "文本"
        case .link:
            return "链接"
        case .filePath:
            return "文件/路径"
        case .code:
            return "代码"
        case .image:
            return "图片"
        }
    }

    func includes(_ record: ClipboardHistoryRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .pinned:
            return record.isPinned
        case .text:
            return record.category == .text
        case .link:
            return record.category == .link
        case .filePath:
            return record.category == .filePath
        case .code:
            return record.category == .code
        case .image:
            return record.category == .image
        }
    }
}

final class ClipboardHistoryCoordinator {
    private let store = ClipboardHistoryStore()
    private lazy var monitor = ClipboardHistoryMonitor(store: store)
    private lazy var windowController = ClipboardHistoryWindowController(store: store)

    func start() {
        store.load()
        monitor.start()
    }

    func showWindow() {
        windowController.showPanel()
    }

    func toggleQuickWindow() {
        windowController.toggleQuickPanel()
    }
}

final class ClipboardHistoryStore {
    private(set) var records: [ClipboardHistoryRecord] = []
    var onChange: (() -> Void)?

    private var fileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RightMenu", isDirectory: true)
            .appendingPathComponent("clipboard-history.json")
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder().decode([ClipboardHistoryRecord].self, from: data)
            normalizeLimit()
        } catch {
            NSLog("RightMenu failed to load clipboard history: %@", String(describing: error))
            records = []
        }
    }

    func add(_ record: ClipboardHistoryRecord) {
        if let index = records.firstIndex(where: { $0.signature == record.signature }) {
            var existing = records.remove(at: index)
            existing.lastCopiedAt = record.lastCopiedAt
            existing.preview = record.preview
            existing.detail = record.detail
            existing.text = record.text
            existing.filePaths = record.filePaths
            existing.imageTIFFData = record.imageTIFFData
            records.insert(existing, at: 0)
        } else {
            records.insert(record, at: 0)
        }
        normalizeLimit()
        saveAndNotify()
    }

    func delete(id: String) {
        records.removeAll { $0.id == id }
        saveAndNotify()
    }

    func togglePin(id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            return
        }
        records[index].isPinned.toggle()
        saveAndNotify()
    }

    func markCopied(id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            return
        }
        records[index].lastCopiedAt = Date()
        saveAndNotify()
    }

    func record(id: String) -> ClipboardHistoryRecord? {
        records.first { $0.id == id }
    }

    private func normalizeLimit() {
        let pinned = records.filter(\.isPinned)
        let unpinned = records.filter { !$0.isPinned }
        records = pinned.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
            + Array(unpinned.sorted { $0.lastCopiedAt > $1.lastCopiedAt }.prefix(clipboardHistoryMaxItems))
    }

    private func saveAndNotify() {
        save()
        onChange?()
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("RightMenu failed to save clipboard history: %@", String(describing: error))
        }
    }
}

final class ClipboardHistoryMonitor {
    private let store: ClipboardHistoryStore
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    init(store: ClipboardHistoryStore) {
        self.store = store
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
        poll()
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }
        lastChangeCount = pasteboard.changeCount

        guard let record = ClipboardHistoryClassifier.record(from: pasteboard) else {
            return
        }
        store.add(record)
    }
}

enum ClipboardHistoryClassifier {
    static func record(from pasteboard: NSPasteboard) -> ClipboardHistoryRecord? {
        let createdAt = Date()

        if let fileURLs = fileURLs(from: pasteboard), !fileURLs.isEmpty {
            let paths = fileURLs.map(\.path)
            return makeRecord(
                category: .filePath,
                text: paths.joined(separator: "\n"),
                filePaths: paths,
                imageTIFFData: nil,
                preview: paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "),
                detail: "\(paths.count) 个文件/路径",
                createdAt: createdAt
            )
        }

        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = normalizeWhitespace(string)
            let category = classify(string)
            let paths = category == .filePath ? parsePathLines(string) : []
            return makeRecord(
                category: category,
                text: string,
                filePaths: paths,
                imageTIFFData: nil,
                preview: normalized,
                detail: detail(for: category, string: string, paths: paths),
                createdAt: createdAt
            )
        }

        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation {
            let size = image.size
            return makeRecord(
                category: .image,
                text: nil,
                filePaths: [],
                imageTIFFData: tiff,
                preview: "图片 \(Int(size.width))x\(Int(size.height))",
                detail: ByteCountFormatter.string(fromByteCount: Int64(tiff.count), countStyle: .file),
                createdAt: createdAt
            )
        }

        return nil
    }

    static func write(_ record: ClipboardHistoryRecord, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        switch record.category {
        case .image:
            guard let data = record.imageTIFFData,
                  let image = NSImage(data: data) else {
                return false
            }
            return pasteboard.writeObjects([image])

        case .filePath:
            if !record.filePaths.isEmpty {
                let urls = record.filePaths.map { NSURL(fileURLWithPath: $0) }
                pasteboard.writeObjects(urls)
            }
            if let text = record.text {
                pasteboard.setString(text, forType: .string)
            }
            return true

        case .text, .link, .code:
            guard let text = record.text else {
                return false
            }
            pasteboard.setString(text, forType: .string)
            return true
        }
    }

    private static func makeRecord(
        category: ClipboardHistoryCategory,
        text: String?,
        filePaths: [String],
        imageTIFFData: Data?,
        preview: String,
        detail: String,
        createdAt: Date
    ) -> ClipboardHistoryRecord {
        let cleanedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = [
            category.rawValue,
            text ?? "",
            filePaths.joined(separator: "\u{1f}"),
            imageTIFFData?.base64EncodedString() ?? ""
        ].joined(separator: "\u{1e}")

        return ClipboardHistoryRecord(
            id: UUID().uuidString,
            category: category,
            text: text,
            filePaths: filePaths,
            imageTIFFData: imageTIFFData,
            preview: cleanedPreview.isEmpty ? category.title : String(cleanedPreview.prefix(240)),
            detail: detail,
            signature: signature,
            isPinned: false,
            createdAt: createdAt,
            lastCopiedAt: createdAt
        )
    }

    private static func fileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) ?? []
        let urls = objects.compactMap { object -> URL? in
            if let url = object as? URL {
                return url.isFileURL ? url : nil
            }
            if let nsURL = object as? NSURL,
               let url = nsURL as URL?,
               url.isFileURL {
                return url
            }
            return nil
        }
        return urls.isEmpty ? nil : urls
    }

    private static func classify(_ string: String) -> ClipboardHistoryCategory {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if isHTTPURL(trimmed) {
            return .link
        }
        let paths = parsePathLines(string)
        if !paths.isEmpty {
            return .filePath
        }
        if looksLikeCode(string) {
            return .code
        }
        return .text
    }

    private static func detail(for category: ClipboardHistoryCategory, string: String, paths: [String]) -> String {
        switch category {
        case .filePath:
            return paths.isEmpty ? "路径文本" : "\(paths.count) 个路径"
        case .link:
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "链接"
        case .code:
            return "\(string.split(separator: "\n", omittingEmptySubsequences: false).count) 行代码"
        case .text:
            return "\(string.count) 个字符"
        case .image:
            return "图片"
        }
    }

    private static func isHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return ["http", "https"].contains(scheme)
    }

    private static func parsePathLines(_ value: String) -> [String] {
        let lines = value
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty, lines.count <= 50 else {
            return []
        }

        let paths = lines.compactMap { raw -> String? in
            let unquoted = raw
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .replacingOccurrences(of: "\\ ", with: " ")
            if unquoted.hasPrefix("file://"),
               let url = URL(string: unquoted),
               url.isFileURL {
                return url.path
            }
            if unquoted.hasPrefix("/") || unquoted.hasPrefix("~/") {
                let expanded = (unquoted as NSString).expandingTildeInPath
                return FileManager.default.fileExists(atPath: expanded) ? expanded : unquoted
            }
            return nil
        }

        guard paths.count == lines.count else {
            return []
        }
        return paths
    }

    private static func looksLikeCode(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#!") {
            return true
        }
        let lines = trimmed.split(separator: "\n")
        guard lines.count >= 2 else {
            return false
        }
        let markers = [
            "import ",
            "func ",
            "class ",
            "struct ",
            "enum ",
            "def ",
            "const ",
            "let ",
            "var ",
            "=>",
            "{",
            "}",
            "</",
            "SELECT ",
            "FROM "
        ]
        let upper = trimmed.uppercased()
        return markers.contains { marker in
            marker == marker.uppercased() ? upper.contains(marker) : trimmed.contains(marker)
        }
    }

    private static func normalizeWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }
}

final class ClipboardHistoryWindowController: NSWindowController, NSWindowDelegate {
    private let store: ClipboardHistoryStore
    private let searchField = ClipboardHistorySearchField()
    private let segmented = NSSegmentedControl(labels: ClipboardHistoryFilter.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let rowsStack = ClipboardFlippedStackView()
    private let emptyLabel = NSTextField(labelWithString: "暂无剪贴板记录")
    private var searchPollTimer: Timer?
    private var filter: ClipboardHistoryFilter = .all
    private var query = ""

    init(store: ClipboardHistoryStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "剪贴板历史"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        super.init(window: window)
        window.delegate = self
        buildContent()
        store.onChange = { [weak self] in
            self?.reloadRows()
        }
        reloadRows()
        centerOnMainScreen()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPanel() {
        showPanel(resetFilters: false, focusSearch: false, nearMouse: false)
    }

    func toggleQuickPanel() {
        if window?.isVisible == true, window?.isKeyWindow == true {
            window?.orderOut(nil)
            return
        }
        showPanel(resetFilters: true, focusSearch: true, nearMouse: true)
    }

    private func showPanel(resetFilters: Bool, focusSearch: Bool, nearMouse: Bool) {
        if resetFilters {
            resetFiltersAndSearch()
        }
        reloadRows()
        startSearchPolling()
        if nearMouse {
            positionNearMouse()
        } else {
            centerOnMainScreen()
        }
        window?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if focusSearch {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.window?.makeFirstResponder(self.searchField)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        searchPollTimer?.invalidate()
        searchPollTimer = nil
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 18, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        root.addArrangedSubview(headerView())
        root.addArrangedSubview(filterView())
        root.addArrangedSubview(scrollView())
    }

    private func headerView() -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 12

        let imageView = NSImageView()
        if #available(macOS 11.0, *) {
            imageView.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "剪贴板历史")
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        }
        imageView.widthAnchor.constraint(equalToConstant: 34).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 34).isActive = true
        container.addArrangedSubview(imageView)

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3

        let title = NSTextField(labelWithString: "智能剪贴板历史")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "自动分类并快速复用复制过的内容")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        labels.addArrangedSubview(title)
        labels.addArrangedSubview(subtitle)
        container.addArrangedSubview(labels)
        return container
    }

    private func filterView() -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 10

        segmented.selectedSegment = ClipboardHistoryFilter.all.rawValue
        segmented.target = self
        segmented.action = #selector(filterChanged(_:))
        container.addArrangedSubview(segmented)

        searchField.placeholderString = "搜索剪贴板"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.onChange = { [weak self] value in
            self?.updateSearch(value)
        }
        searchField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        container.addArrangedSubview(searchField)

        return container
    }

    private func scrollView() -> NSScrollView {
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 8
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor

        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = rowsStack
        scroll.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 440),
            rowsStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        return scroll
    }

    private func reloadRows() {
        rowsStack.arrangedSubviews.forEach { view in
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let records = filteredRecords()
        guard !records.isEmpty else {
            rowsStack.addArrangedSubview(emptyLabel)
            return
        }

        for record in records {
            rowsStack.addArrangedSubview(rowView(for: record))
        }
    }

    private func filteredRecords() -> [ClipboardHistoryRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.records.filter { record in
            guard filter.includes(record) else {
                return false
            }
            guard !needle.isEmpty else {
                return true
            }
            return [
                record.preview,
                record.detail,
                record.text ?? "",
                record.filePaths.joined(separator: "\n"),
                record.category.title
            ].joined(separator: "\n").lowercased().contains(needle)
        }
    }

    private func rowView(for record: ClipboardHistoryRecord) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 672).isActive = true

        let icon = NSImageView()
        if #available(macOS 11.0, *) {
            let symbolName = record.isPinned ? "pin.fill" : record.category.symbolName
            icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: record.category.title)
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        }
        icon.contentTintColor = record.isPinned ? .systemOrange : .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        row.addArrangedSubview(icon)

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3

        let preview = NSTextField(labelWithString: record.preview)
        preview.font = .systemFont(ofSize: 13, weight: .medium)
        preview.lineBreakMode = .byTruncatingTail
        preview.maximumNumberOfLines = 1
        preview.widthAnchor.constraint(equalToConstant: 390).isActive = true

        let detail = NSTextField(labelWithString: "\(record.category.title) · \(record.detail)")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.maximumNumberOfLines = 1
        detail.widthAnchor.constraint(equalToConstant: 390).isActive = true

        labels.addArrangedSubview(preview)
        labels.addArrangedSubview(detail)
        row.addArrangedSubview(labels)

        row.addArrangedSubview(NSView())
        row.addArrangedSubview(actionButton(title: "复制", symbol: "doc.on.clipboard", recordID: record.id, action: #selector(copyRecord(_:))))
        row.addArrangedSubview(actionButton(title: record.isPinned ? "取消固定" : "固定", symbol: record.isPinned ? "pin.slash" : "pin", recordID: record.id, action: #selector(togglePin(_:))))
        row.addArrangedSubview(actionButton(title: "删除", symbol: "trash", recordID: record.id, action: #selector(deleteRecord(_:))))
        if record.canOpenURL != nil {
            row.addArrangedSubview(actionButton(title: "打开", symbol: "arrow.up.right.square", recordID: record.id, action: #selector(openRecord(_:))))
        }

        return row
    }

    private func actionButton(title: String, symbol: String, recordID: String, action: Selector) -> NSButton {
        let button = ClipboardHistoryButton(title: title, target: self, action: action)
        button.recordID = recordID
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.bezelStyle = .texturedRounded
        if #available(macOS 11.0, *) {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.imagePosition = .imageOnly
        } else {
            button.title = title
        }
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return button
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

    private func positionNearMouse() {
        guard let window else {
            return
        }
        let mouse = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouse, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen = targetScreen else {
            centerOnMainScreen()
            return
        }

        let visible = screen.visibleFrame
        let margin: CGFloat = 16
        var frame = window.frame
        frame.origin.x = min(
            max(mouse.x - frame.width / 2, visible.minX + margin),
            visible.maxX - frame.width - margin
        )
        frame.origin.y = min(
            max(mouse.y - frame.height - 14, visible.minY + margin),
            visible.maxY - frame.height - margin
        )
        window.setFrame(frame, display: true)
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        filter = ClipboardHistoryFilter(rawValue: sender.selectedSegment) ?? .all
        reloadRows()
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        updateSearch(sender.stringValue)
    }

    private func updateSearch(_ value: String) {
        query = value
        reloadRows()
    }

    private func resetFiltersAndSearch() {
        filter = .all
        query = ""
        segmented.selectedSegment = ClipboardHistoryFilter.all.rawValue
        searchField.stringValue = ""
    }

    private func startSearchPolling() {
        searchPollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self,
                  self.window?.isVisible == true,
                  self.searchField.stringValue != self.query else {
                return
            }
            self.updateSearch(self.searchField.stringValue)
        }
        RunLoop.main.add(timer, forMode: .common)
        searchPollTimer = timer
    }

    @objc private func copyRecord(_ sender: ClipboardHistoryButton) {
        guard let record = store.record(id: sender.recordID),
              ClipboardHistoryClassifier.write(record, to: NSPasteboard.general) else {
            NSSound.beep()
            return
        }
        store.markCopied(id: record.id)
    }

    @objc private func togglePin(_ sender: ClipboardHistoryButton) {
        store.togglePin(id: sender.recordID)
    }

    @objc private func deleteRecord(_ sender: ClipboardHistoryButton) {
        store.delete(id: sender.recordID)
    }

    @objc private func openRecord(_ sender: ClipboardHistoryButton) {
        guard let record = store.record(id: sender.recordID),
              let url = record.canOpenURL else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private final class ClipboardHistoryButton: NSButton {
    var recordID = ""
}

private final class ClipboardHistorySearchField: NSSearchField {
    var onChange: ((String) -> Void)?

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onChange?(stringValue)
    }
}

private final class ClipboardFlippedStackView: NSStackView {
    override var isFlipped: Bool {
        true
    }
}
