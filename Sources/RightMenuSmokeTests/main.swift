import Foundation
import RightMenuCore

@main
struct RightMenuSmokeTests {
    static func main() throws {
        try copyAbsolutePathsWritesOnePathPerLine()
        try shellEscapedPathUsesSingleQuoteSafeFormat()
        try newTextFileCreatesUniqueFileName()
        try cutAndPasteMovesItems()
        try copyGitRelativePathsUsesNearestRoot()
        try md5ActionCopiesDigest()
        try zipActionCreatesArchive()
        try executionLogRecordsSuccess()
        try actionManifestLoads()
        try scriptRunnerPassesSelectionAsArguments()
        print("All RightMenu smoke tests passed.")
    }

    private static func copyAbsolutePathsWritesOnePathPerLine() throws {
        let clipboard = MemoryClipboardWriter()
        let executor = ActionExecutor(clipboard: clipboard, executionLog: MemoryExecutionLogStore())
        let context = FinderContext(
            selectedItems: [
                FinderItem(url: URL(fileURLWithPath: "/tmp/a.txt"), isDirectory: false),
                FinderItem(url: URL(fileURLWithPath: "/tmp/b.txt"), isDirectory: false)
            ],
            targetDirectory: URL(fileURLWithPath: "/tmp")
        )

        let result = try executor.execute(
            try require(ActionCatalog.definition(id: BuiltInActionID.copyAbsolutePaths.rawValue)),
            context: context
        )

        try expect(result.summary == "Copied 2 path(s)", "unexpected copy summary")
        try expect(clipboard.value == "/tmp/a.txt\n/tmp/b.txt", "unexpected clipboard value")
    }

    private static func shellEscapedPathUsesSingleQuoteSafeFormat() throws {
        try expect(
            FileNaming.shellEscapedPath("/tmp/it's here.txt") == "'/tmp/it'\\''s here.txt'",
            "unexpected shell escaping"
        )
    }

    private static func newTextFileCreatesUniqueFileName() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("Untitled.txt").path,
            contents: Data()
        )

        let executor = ActionExecutor(
            clipboard: MemoryClipboardWriter(),
            executionLog: MemoryExecutionLogStore()
        )
        let context = FinderContext(targetDirectory: directory)
        let result = try executor.execute(
            try require(ActionCatalog.definition(id: BuiltInActionID.newTextFile.rawValue)),
            context: context
        )

        let created = try require(result.createdURLs.first)
        try expect(created.lastPathComponent == "Untitled 2.txt", "unexpected created file name")
        try expect(FileManager.default.fileExists(atPath: created.path), "created file is missing")
    }

    private static func cutAndPasteMovesItems() throws {
        let sourceDirectory = try makeTemporaryDirectory()
        let targetDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }
        defer { try? FileManager.default.removeItem(at: targetDirectory) }

        let sourceFile = sourceDirectory.appendingPathComponent("move-me.txt")
        FileManager.default.createFile(atPath: sourceFile.path, contents: Data("hello".utf8))

        let cutStore = MemoryCutBufferStore()
        let executor = ActionExecutor(
            clipboard: MemoryClipboardWriter(),
            cutBufferStore: cutStore,
            executionLog: MemoryExecutionLogStore()
        )

        let cutContext = FinderContext(
            selectedItems: [FinderItem(url: sourceFile, isDirectory: false)],
            targetDirectory: sourceDirectory
        )
        _ = try executor.execute(
            try require(ActionCatalog.definition(id: BuiltInActionID.cutItems.rawValue)),
            context: cutContext
        )

        let pasteContext = FinderContext(targetDirectory: targetDirectory)
        let result = try executor.execute(
            try require(ActionCatalog.definition(id: BuiltInActionID.pasteCutItems.rawValue)),
            context: pasteContext
        )

        let moved = try require(result.createdURLs.first)
        try expect(moved.path == targetDirectory.appendingPathComponent("move-me.txt").path, "unexpected move target")
        try expect(FileManager.default.fileExists(atPath: moved.path), "moved file is missing")
        try expect(!FileManager.default.fileExists(atPath: sourceFile.path), "source file still exists")
        try expect(cutStore.buffer == nil, "cut buffer was not cleared")
    }

    private static func copyGitRelativePathsUsesNearestRoot() throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }

        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let sourceDirectory = repo.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let fileURL = sourceDirectory.appendingPathComponent("main.swift")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())

        let clipboard = MemoryClipboardWriter()
        let executor = ActionExecutor(clipboard: clipboard, executionLog: MemoryExecutionLogStore())
        let context = FinderContext(
            selectedItems: [FinderItem(url: fileURL, isDirectory: false)],
            targetDirectory: sourceDirectory
        )

        _ = try executor.execute(
            try require(ActionCatalog.definition(id: BuiltInActionID.copyGitRelativePaths.rawValue)),
            context: context
        )

        try expect(clipboard.value == "Sources/main.swift", "unexpected Git-relative path")
    }

    private static func md5ActionCopiesDigest() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("hello.txt")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("hello".utf8))

        let clipboard = MemoryClipboardWriter()
        let executor = ActionExecutor(clipboard: clipboard, executionLog: MemoryExecutionLogStore())
        let context = FinderContext(
            selectedItems: [FinderItem(url: fileURL, isDirectory: false)],
            targetDirectory: directory
        )

        _ = try executor.execute(
            try require(ActionCatalog.definition(id: BuiltInActionID.computeMD5.rawValue)),
            context: context
        )

        try expect(
            clipboard.value == "5d41402abc4b2a76b9719d911017c592  hello.txt",
            "unexpected MD5 clipboard value"
        )
    }

    private static func zipActionCreatesArchive() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileA = directory.appendingPathComponent("a.txt")
        let fileB = directory.appendingPathComponent("b.txt")
        FileManager.default.createFile(atPath: fileA.path, contents: Data("a".utf8))
        FileManager.default.createFile(atPath: fileB.path, contents: Data("b".utf8))

        let executor = ActionExecutor(
            clipboard: MemoryClipboardWriter(),
            executionLog: MemoryExecutionLogStore()
        )
        let context = FinderContext(
            selectedItems: [
                FinderItem(url: fileA, isDirectory: false),
                FinderItem(url: fileB, isDirectory: false)
            ],
            targetDirectory: directory
        )

        let result = try executor.execute(
            try require(ActionCatalog.definition(id: BuiltInActionID.zipItems.rawValue)),
            context: context
        )

        let archive = try require(result.createdURLs.first)
        try expect(archive.lastPathComponent == "Archive.zip", "unexpected archive name")
        try expect(FileManager.default.fileExists(atPath: archive.path), "archive was not created")
    }

    private static func executionLogRecordsSuccess() throws {
        let log = MemoryExecutionLogStore()
        let executor = ActionExecutor(
            clipboard: MemoryClipboardWriter(),
            executionLog: log
        )
        let context = FinderContext(
            selectedItems: [FinderItem(url: URL(fileURLWithPath: "/tmp/a.txt"), isDirectory: false)],
            targetDirectory: URL(fileURLWithPath: "/tmp")
        )

        _ = try executor.execute(
            try require(ActionCatalog.definition(id: BuiltInActionID.copyFileNames.rawValue)),
            context: context
        )

        let event = try require(log.events.first)
        try expect(event.actionID == BuiltInActionID.copyFileNames.rawValue, "unexpected logged action")
        try expect(event.succeeded, "success was not logged")
    }

    private static func actionManifestLoads() throws {
        let manifestURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("actions/rightmenu-actions.json")
        let manifest = try ActionManifest.load(from: manifestURL)
        try manifest.validate()
        try expect(manifest.schemaVersion == 1, "unexpected manifest schema")
        try expect(manifest.quickActions.count >= 16, "quick action manifest is missing actions")
        try expect(
            manifest.quickActions.contains { $0.title == "RightMenu Copy Selected Path" },
            "copy selected path is missing from manifest"
        )
    }

    private static func scriptRunnerPassesSelectionAsArguments() throws {
        let definition = ActionDefinition(
            id: "custom.echo",
            title: "Echo",
            category: .custom,
            supportedShapes: [.anySelection],
            handler: .shellScript(ShellScriptAction(script: "printf '%s' \"$1\""))
        )
        let context = FinderContext(
            selectedItems: [
                FinderItem(url: URL(fileURLWithPath: "/tmp/example.txt"), isDirectory: false)
            ],
            targetDirectory: URL(fileURLWithPath: "/tmp")
        )

        let result = try ActionExecutor(
            clipboard: MemoryClipboardWriter(),
            executionLog: MemoryExecutionLogStore()
        )
            .execute(definition, context: context)

        try expect(result.stdout == "/tmp/example.txt", "script argument was not passed")
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightMenuTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw SmokeTestError.failed(message)
        }
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else {
            throw SmokeTestError.failed("required value was nil")
        }
        return value
    }
}

enum SmokeTestError: Error, LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            return message
        }
    }
}
