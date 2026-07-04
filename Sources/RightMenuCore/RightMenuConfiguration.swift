import Foundation

public struct FavoriteDirectory: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var url: URL

    public init(id: String = UUID().uuidString, title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}

public struct RightMenuConfiguration: Codable, Equatable, Sendable {
    public var enabledActionIDs: [String]
    public var favoriteDirectories: [FavoriteDirectory]
    public var defaultTerminalBundleID: String
    public var defaultEditorBundleID: String
    public var confirmDangerousActions: Bool

    public init(
        enabledActionIDs: [String] = ActionCatalog.builtIns.map(\.id),
        favoriteDirectories: [FavoriteDirectory] = [],
        defaultTerminalBundleID: String = "com.apple.Terminal",
        defaultEditorBundleID: String = "com.microsoft.VSCode",
        confirmDangerousActions: Bool = true
    ) {
        self.enabledActionIDs = enabledActionIDs
        self.favoriteDirectories = favoriteDirectories
        self.defaultTerminalBundleID = defaultTerminalBundleID
        self.defaultEditorBundleID = defaultEditorBundleID
        self.confirmDangerousActions = confirmDangerousActions
    }
}

public protocol ConfigurationStoring {
    func load() throws -> RightMenuConfiguration
    func save(_ configuration: RightMenuConfiguration) throws
}

public final class JSONConfigurationStore: ConfigurationStoring {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public static func appSupportDefault(fileManager: FileManager = .default) -> JSONConfigurationStore {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("RightMenu", isDirectory: true)
        return JSONConfigurationStore(fileURL: base.appendingPathComponent("config.json"))
    }

    public func load() throws -> RightMenuConfiguration {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return RightMenuConfiguration()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(RightMenuConfiguration.self, from: data)
    }

    public func save(_ configuration: RightMenuConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: [.atomic])
    }
}

