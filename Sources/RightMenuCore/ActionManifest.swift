import Foundation

public struct ActionManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let actions: [ManifestAction]

    public init(schemaVersion: Int, actions: [ManifestAction]) {
        self.schemaVersion = schemaVersion
        self.actions = actions
    }

    public static func load(from url: URL) throws -> ActionManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ActionManifest.self, from: data)
    }

    public static func decode(_ data: Data) throws -> ActionManifest {
        try JSONDecoder().decode(ActionManifest.self, from: data)
    }

    public var quickActions: [ManifestAction] {
        actions.filter { $0.quickAction != nil }
    }

    public func validate() throws {
        guard schemaVersion == 1 else {
            throw ActionManifestError.unsupportedSchema(schemaVersion)
        }

        var ids = Set<String>()
        var titles = Set<String>()

        for action in actions {
            guard ids.insert(action.id).inserted else {
                throw ActionManifestError.duplicateActionID(action.id)
            }
            guard titles.insert(action.title).inserted else {
                throw ActionManifestError.duplicateTitle(action.title)
            }
            if action.surfaces.contains(.quickAction), action.quickAction == nil {
                throw ActionManifestError.missingQuickAction(action.id)
            }
        }
    }
}

public struct ManifestAction: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let category: String
    public let surfaces: [ManifestSurface]
    public let coreActionID: String?
    public let quickAction: ManifestQuickAction?

    public init(
        id: String,
        title: String,
        category: String,
        surfaces: [ManifestSurface],
        coreActionID: String? = nil,
        quickAction: ManifestQuickAction? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.surfaces = surfaces
        self.coreActionID = coreActionID
        self.quickAction = quickAction
    }
}

public enum ManifestSurface: String, Codable, Equatable, Sendable {
    case quickAction
    case core
    case finderSync
}

public struct ManifestQuickAction: Codable, Equatable, Sendable {
    public let input: QuickActionInput
    public let scriptKey: String
    public let sendFileTypes: [String]?

    public init(input: QuickActionInput, scriptKey: String, sendFileTypes: [String]? = nil) {
        self.input = input
        self.scriptKey = scriptKey
        self.sendFileTypes = sendFileTypes
    }
}

public enum QuickActionInput: String, Codable, Equatable, Sendable {
    case selected
    case finder
}

public enum ActionManifestError: Error, Equatable, LocalizedError {
    case unsupportedSchema(Int)
    case duplicateActionID(String)
    case duplicateTitle(String)
    case missingQuickAction(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(schema):
            return "Unsupported action manifest schema version: \(schema)."
        case let .duplicateActionID(id):
            return "Duplicate action id in manifest: \(id)."
        case let .duplicateTitle(title):
            return "Duplicate action title in manifest: \(title)."
        case let .missingQuickAction(id):
            return "Action \(id) declares quickAction surface but has no quickAction block."
        }
    }
}

