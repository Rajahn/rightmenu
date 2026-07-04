import Foundation

public struct ActionExecutionEvent: Codable, Equatable, Sendable {
    public let id: String
    public let actionID: String
    public let actionTitle: String
    public let startedAt: Date
    public let durationMilliseconds: Int
    public let inputPaths: [String]
    public let succeeded: Bool
    public let summary: String
    public let errorDescription: String?

    public init(
        id: String = UUID().uuidString,
        actionID: String,
        actionTitle: String,
        startedAt: Date,
        durationMilliseconds: Int,
        inputPaths: [String],
        succeeded: Bool,
        summary: String,
        errorDescription: String? = nil
    ) {
        self.id = id
        self.actionID = actionID
        self.actionTitle = actionTitle
        self.startedAt = startedAt
        self.durationMilliseconds = durationMilliseconds
        self.inputPaths = inputPaths
        self.succeeded = succeeded
        self.summary = summary
        self.errorDescription = errorDescription
    }
}

public protocol ExecutionLogWriting {
    func append(_ event: ActionExecutionEvent) throws
}

public final class JSONLinesExecutionLogStore: ExecutionLogWriting {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public static func appSupportDefault(fileManager: FileManager = .default) -> JSONLinesExecutionLogStore {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("RightMenu", isDirectory: true)
        return JSONLinesExecutionLogStore(fileURL: base.appendingPathComponent("executions.jsonl"))
    }

    public func append(_ event: ActionExecutionEvent) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event) + Data("\n".utf8)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: fileURL, options: [.atomic])
        }
    }
}

public final class MemoryExecutionLogStore: ExecutionLogWriting {
    public private(set) var events: [ActionExecutionEvent] = []

    public init() {}

    public func append(_ event: ActionExecutionEvent) {
        events.append(event)
    }
}

