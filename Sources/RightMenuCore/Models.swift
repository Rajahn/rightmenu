import Foundation

public enum ActionCategory: String, Codable, CaseIterable, Sendable {
    case copy
    case create
    case open
    case move
    case utility
    case dangerous
    case custom
}

public enum SelectionShape: String, Codable, CaseIterable, Sendable {
    case emptyArea
    case singleFile
    case singleFolder
    case multipleItems
    case anySelection
    case directoryContext
}

public struct FinderItem: Codable, Equatable, Sendable {
    public let url: URL
    public let isDirectory: Bool

    public init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }
}

public struct FinderContext: Equatable, Sendable {
    public let selectedItems: [FinderItem]
    public let targetDirectory: URL?

    public init(selectedItems: [FinderItem] = [], targetDirectory: URL? = nil) {
        self.selectedItems = selectedItems
        self.targetDirectory = targetDirectory
    }

    public var selectedURLs: [URL] {
        selectedItems.map(\.url)
    }

    public var itemsOrTarget: [URL] {
        if selectedURLs.isEmpty, let targetDirectory {
            return [targetDirectory]
        }
        return selectedURLs
    }

    public var primaryDirectory: URL? {
        if let targetDirectory {
            return targetDirectory
        }

        if selectedItems.count == 1, let item = selectedItems.first, item.isDirectory {
            return item.url
        }

        return selectedItems.first?.url.deletingLastPathComponent()
    }

    public var shape: SelectionShape {
        if selectedItems.isEmpty {
            return .emptyArea
        }

        if selectedItems.count > 1 {
            return .multipleItems
        }

        return selectedItems[0].isDirectory ? .singleFolder : .singleFile
    }

    public func supports(_ supportedShapes: [SelectionShape]) -> Bool {
        if supportedShapes.contains(.directoryContext), primaryDirectory != nil {
            return true
        }

        if supportedShapes.contains(.anySelection), !selectedItems.isEmpty {
            return true
        }

        return supportedShapes.contains(shape)
    }
}

public enum BuiltInActionID: String, Codable, CaseIterable, Sendable {
    case copyAbsolutePaths = "copy.absolute-paths"
    case copyFileURLs = "copy.file-urls"
    case copyFileNames = "copy.file-names"
    case copyParentDirectories = "copy.parent-directories"
    case copyMarkdownLinks = "copy.markdown-links"
    case copyShellEscapedPaths = "copy.shell-escaped-paths"
    case copyGitRelativePaths = "copy.git-relative-paths"
    case newTextFile = "create.text-file"
    case newMarkdownFile = "create.markdown-file"
    case newJSONFile = "create.json-file"
    case newYAMLFile = "create.yaml-file"
    case cutItems = "move.cut-items"
    case pasteCutItems = "move.paste-cut-items"
    case computeMD5 = "utility.md5"
    case computeSHA256 = "utility.sha256"
    case zipItems = "archive.zip-items"
}

public struct ShellScriptAction: Codable, Equatable, Sendable {
    public let script: String
    public let shell: String

    public init(script: String, shell: String = "/bin/zsh") {
        self.script = script
        self.shell = shell
    }
}

public enum ActionHandler: Codable, Equatable, Sendable {
    case builtIn(BuiltInActionID)
    case shellScript(ShellScriptAction)
}

public struct ActionDefinition: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let category: ActionCategory
    public let supportedShapes: [SelectionShape]
    public let isDestructive: Bool
    public let requiresConfirmation: Bool
    public let timeoutSeconds: Int
    public let handler: ActionHandler

    public init(
        id: String,
        title: String,
        category: ActionCategory,
        supportedShapes: [SelectionShape],
        isDestructive: Bool = false,
        requiresConfirmation: Bool = false,
        timeoutSeconds: Int = 10,
        handler: ActionHandler
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.supportedShapes = supportedShapes
        self.isDestructive = isDestructive
        self.requiresConfirmation = requiresConfirmation
        self.timeoutSeconds = timeoutSeconds
        self.handler = handler
    }
}

public struct ActionExecutionResult: Equatable, Sendable {
    public let summary: String
    public let createdURLs: [URL]
    public let stdout: String
    public let stderr: String

    public init(
        summary: String,
        createdURLs: [URL] = [],
        stdout: String = "",
        stderr: String = ""
    ) {
        self.summary = summary
        self.createdURLs = createdURLs
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum ActionExecutionError: Error, Equatable, LocalizedError {
    case unsupportedContext(actionID: String, shape: SelectionShape)
    case missingTargetDirectory(actionID: String)
    case missingCutBuffer
    case moveFailed(source: String, destination: String, reason: String)
    case gitRootNotFound(path: String)
    case unsupportedDirectoryHash(path: String)
    case commonParentRequired(actionID: String)
    case unknownBuiltInAction(BuiltInActionID)
    case processFailed(executable: String, exitCode: Int32, stderr: String)
    case scriptFailed(exitCode: Int32, stderr: String)
    case scriptTimedOut(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedContext(actionID, shape):
            return "Action \(actionID) does not support context \(shape.rawValue)."
        case let .missingTargetDirectory(actionID):
            return "Action \(actionID) needs a target directory."
        case .missingCutBuffer:
            return "No cut items are available to paste."
        case let .moveFailed(source, destination, reason):
            return "Failed to move \(source) to \(destination): \(reason)"
        case let .gitRootNotFound(path):
            return "No Git repository root was found for \(path)."
        case let .unsupportedDirectoryHash(path):
            return "Hashing directories is not supported yet: \(path)."
        case let .commonParentRequired(actionID):
            return "Action \(actionID) requires selected items to share the same parent directory."
        case let .unknownBuiltInAction(actionID):
            return "Unknown built-in action \(actionID.rawValue)."
        case let .processFailed(executable, exitCode, stderr):
            return "\(executable) failed with exit code \(exitCode): \(stderr)"
        case let .scriptFailed(exitCode, stderr):
            return "Script failed with exit code \(exitCode): \(stderr)"
        case let .scriptTimedOut(seconds):
            return "Script timed out after \(seconds) seconds."
        }
    }
}
