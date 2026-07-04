import Foundation

public struct CutBuffer: Codable, Equatable, Sendable {
    public let sourceURLs: [URL]
    public let createdAt: Date

    public init(sourceURLs: [URL], createdAt: Date = Date()) {
        self.sourceURLs = sourceURLs
        self.createdAt = createdAt
    }
}

public protocol CutBufferStoring {
    func load() throws -> CutBuffer?
    func save(_ buffer: CutBuffer) throws
    func clear() throws
}

public final class JSONCutBufferStore: CutBufferStoring {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public static func appSupportDefault(fileManager: FileManager = .default) -> JSONCutBufferStore {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("RightMenu", isDirectory: true)
        return JSONCutBufferStore(fileURL: base.appendingPathComponent("cut-buffer.json"))
    }

    public func load() throws -> CutBuffer? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(CutBuffer.self, from: data)
    }

    public func save(_ buffer: CutBuffer) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(buffer)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }
}

public final class MemoryCutBufferStore: CutBufferStoring {
    public private(set) var buffer: CutBuffer?

    public init(buffer: CutBuffer? = nil) {
        self.buffer = buffer
    }

    public func load() -> CutBuffer? {
        buffer
    }

    public func save(_ buffer: CutBuffer) {
        self.buffer = buffer
    }

    public func clear() {
        buffer = nil
    }
}
