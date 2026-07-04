import Foundation

public final class ActionExecutor {
    private let clipboard: ClipboardWriting
    private let fileManager: FileManager
    private let scriptRunner: ScriptRunner
    private let cutBufferStore: CutBufferStoring
    private let executionLog: ExecutionLogWriting?

    public init(
        clipboard: ClipboardWriting = ProcessClipboardWriter(),
        fileManager: FileManager = .default,
        scriptRunner: ScriptRunner = ScriptRunner(),
        cutBufferStore: CutBufferStoring = JSONCutBufferStore.appSupportDefault(),
        executionLog: ExecutionLogWriting? = JSONLinesExecutionLogStore.appSupportDefault()
    ) {
        self.clipboard = clipboard
        self.fileManager = fileManager
        self.scriptRunner = scriptRunner
        self.cutBufferStore = cutBufferStore
        self.executionLog = executionLog
    }

    public func execute(
        _ definition: ActionDefinition,
        context: FinderContext
    ) throws -> ActionExecutionResult {
        let startedAt = Date()
        do {
            let result = try executeValidated(definition, context: context)
            try? appendLog(
                definition: definition,
                context: context,
                startedAt: startedAt,
                succeeded: true,
                summary: result.summary,
                errorDescription: nil
            )
            return result
        } catch {
            try? appendLog(
                definition: definition,
                context: context,
                startedAt: startedAt,
                succeeded: false,
                summary: "Failed",
                errorDescription: error.localizedDescription
            )
            throw error
        }
    }

    private func executeValidated(
        _ definition: ActionDefinition,
        context: FinderContext
    ) throws -> ActionExecutionResult {
        guard context.supports(definition.supportedShapes) else {
            throw ActionExecutionError.unsupportedContext(
                actionID: definition.id,
                shape: context.shape
            )
        }

        switch definition.handler {
        case let .builtIn(actionID):
            return try executeBuiltIn(actionID, context: context)
        case let .shellScript(scriptAction):
            let result = try scriptRunner.run(
                scriptAction,
                context: context,
                timeoutSeconds: definition.timeoutSeconds
            )
            guard result.exitCode == 0 else {
                throw ActionExecutionError.scriptFailed(
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
            }
            return ActionExecutionResult(
                summary: result.stdout
                    .split(separator: "\n")
                    .first
                    .map(String.init) ?? "Script completed",
                stdout: result.stdout,
                stderr: result.stderr
            )
        }
    }

    private func executeBuiltIn(
        _ actionID: BuiltInActionID,
        context: FinderContext
    ) throws -> ActionExecutionResult {
        switch actionID {
        case .copyAbsolutePaths:
            return try writeLinesToClipboard(
                context.itemsOrTarget.map(\.path),
                summary: "Copied \(context.itemsOrTarget.count) path(s)"
            )

        case .copyFileURLs:
            return try writeLinesToClipboard(
                context.itemsOrTarget.map(\.absoluteString),
                summary: "Copied \(context.itemsOrTarget.count) file URL(s)"
            )

        case .copyFileNames:
            return try writeLinesToClipboard(
                context.itemsOrTarget.map(\.lastPathComponent),
                summary: "Copied \(context.itemsOrTarget.count) name(s)"
            )

        case .copyParentDirectories:
            let parents = context.itemsOrTarget.map {
                $0.deletingLastPathComponent().path
            }
            return try writeLinesToClipboard(
                parents,
                summary: "Copied \(parents.count) parent path(s)"
            )

        case .copyMarkdownLinks:
            let links = context.itemsOrTarget.map { url in
                "[\(url.lastPathComponent)](\(url.absoluteString))"
            }
            return try writeLinesToClipboard(
                links,
                summary: "Copied \(links.count) Markdown link(s)"
            )

        case .copyShellEscapedPaths:
            return try writeLinesToClipboard(
                context.itemsOrTarget.map { FileNaming.shellEscapedPath($0.path) },
                summary: "Copied \(context.itemsOrTarget.count) shell-escaped path(s)"
            )

        case .copyGitRelativePaths:
            let paths = try context.itemsOrTarget.map { url -> String in
                guard let root = GitPathResolver.repositoryRoot(containing: url, fileManager: fileManager) else {
                    throw ActionExecutionError.gitRootNotFound(path: url.path)
                }
                return GitPathResolver.relativePath(for: url, root: root)
            }
            return try writeLinesToClipboard(
                paths,
                summary: "Copied \(paths.count) Git-relative path(s)"
            )

        case .newTextFile:
            return try createEmptyFile(
                context: context,
                baseName: "Untitled",
                fileExtension: "txt",
                actionID: actionID
            )

        case .newMarkdownFile:
            return try createEmptyFile(
                context: context,
                baseName: "Untitled",
                fileExtension: "md",
                actionID: actionID
            )

        case .newJSONFile:
            return try createFile(
                context: context,
                baseName: "Untitled",
                fileExtension: "json",
                contents: "{\n  \n}\n",
                actionID: actionID
            )

        case .newYAMLFile:
            return try createFile(
                context: context,
                baseName: "Untitled",
                fileExtension: "yaml",
                contents: "---\n",
                actionID: actionID
            )

        case .cutItems:
            try cutBufferStore.save(CutBuffer(sourceURLs: context.selectedURLs))
            return ActionExecutionResult(summary: "Marked \(context.selectedURLs.count) item(s) for move")

        case .pasteCutItems:
            return try pasteCutItems(context: context)

        case .computeMD5:
            return try copyHashes(
                context: context,
                algorithmName: "MD5",
                hasher: FileHasher.md5(url:)
            )

        case .computeSHA256:
            return try copyHashes(
                context: context,
                algorithmName: "SHA-256",
                hasher: FileHasher.sha256(url:)
            )

        case .zipItems:
            let archiveURL = try ArchiveUtility.zipItems(context.selectedURLs, fileManager: fileManager)
            return ActionExecutionResult(
                summary: "Created \(archiveURL.lastPathComponent)",
                createdURLs: [archiveURL]
            )
        }
    }

    private func writeLinesToClipboard(
        _ lines: [String],
        summary: String
    ) throws -> ActionExecutionResult {
        let value = lines.joined(separator: "\n")
        try clipboard.writeString(value)
        return ActionExecutionResult(summary: summary)
    }

    private func createEmptyFile(
        context: FinderContext,
        baseName: String,
        fileExtension: String,
        actionID: BuiltInActionID
    ) throws -> ActionExecutionResult {
        try createFile(
            context: context,
            baseName: baseName,
            fileExtension: fileExtension,
            contents: "",
            actionID: actionID
        )
    }

    private func createFile(
        context: FinderContext,
        baseName: String,
        fileExtension: String,
        contents: String,
        actionID: BuiltInActionID
    ) throws -> ActionExecutionResult {
        guard let directory = context.primaryDirectory else {
            throw ActionExecutionError.missingTargetDirectory(actionID: actionID.rawValue)
        }

        let fileURL = FileNaming.nextAvailableFileURL(
            in: directory,
            baseName: baseName,
            fileExtension: fileExtension,
            fileManager: fileManager
        )

        fileManager.createFile(atPath: fileURL.path, contents: Data(contents.utf8))
        return ActionExecutionResult(
            summary: "Created \(fileURL.lastPathComponent)",
            createdURLs: [fileURL]
        )
    }

    private func pasteCutItems(context: FinderContext) throws -> ActionExecutionResult {
        guard let directory = context.primaryDirectory else {
            throw ActionExecutionError.missingTargetDirectory(actionID: BuiltInActionID.pasteCutItems.rawValue)
        }

        guard let buffer = try cutBufferStore.load(), !buffer.sourceURLs.isEmpty else {
            throw ActionExecutionError.missingCutBuffer
        }

        var movedURLs: [URL] = []
        for sourceURL in buffer.sourceURLs {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }

            if sourceURL.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path {
                continue
            }

            let destinationURL = FileNaming.nextAvailableURL(
                named: sourceURL.lastPathComponent,
                in: directory,
                fileManager: fileManager
            )

            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
                movedURLs.append(destinationURL)
            } catch {
                throw ActionExecutionError.moveFailed(
                    source: sourceURL.path,
                    destination: destinationURL.path,
                    reason: error.localizedDescription
                )
            }
        }

        try cutBufferStore.clear()
        return ActionExecutionResult(
            summary: "Moved \(movedURLs.count) item(s)",
            createdURLs: movedURLs
        )
    }

    private func copyHashes(
        context: FinderContext,
        algorithmName: String,
        hasher: (URL) throws -> String
    ) throws -> ActionExecutionResult {
        let lines = try context.itemsOrTarget.map { url -> String in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                throw ActionExecutionError.unsupportedDirectoryHash(path: url.path)
            }
            return "\(try hasher(url))  \(url.lastPathComponent)"
        }

        return try writeLinesToClipboard(
            lines,
            summary: "Copied \(algorithmName) for \(lines.count) item(s)"
        )
    }

    private func appendLog(
        definition: ActionDefinition,
        context: FinderContext,
        startedAt: Date,
        succeeded: Bool,
        summary: String,
        errorDescription: String?
    ) throws {
        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        let event = ActionExecutionEvent(
            actionID: definition.id,
            actionTitle: definition.title,
            startedAt: startedAt,
            durationMilliseconds: duration,
            inputPaths: context.itemsOrTarget.map(\.path),
            succeeded: succeeded,
            summary: summary,
            errorDescription: errorDescription
        )
        try executionLog?.append(event)
    }
}
