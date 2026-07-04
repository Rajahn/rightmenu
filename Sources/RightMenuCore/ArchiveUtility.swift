import Foundation

public enum ArchiveUtility {
    public static func zipItems(
        _ urls: [URL],
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let first = urls.first else {
            throw ActionExecutionError.missingTargetDirectory(actionID: BuiltInActionID.zipItems.rawValue)
        }

        let parent = first.deletingLastPathComponent().standardizedFileURL
        let allShareParent = urls.allSatisfy {
            $0.deletingLastPathComponent().standardizedFileURL.path == parent.path
        }
        guard allShareParent else {
            throw ActionExecutionError.commonParentRequired(actionID: BuiltInActionID.zipItems.rawValue)
        }

        let baseName = urls.count == 1
            ? first.deletingPathExtension().lastPathComponent
            : "Archive"
        let archiveURL = FileNaming.nextAvailableFileURL(
            in: parent,
            baseName: baseName,
            fileExtension: "zip",
            fileManager: fileManager
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = parent
        process.arguments = ["-qry", archiveURL.path] + urls.map(\.lastPathComponent)

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorText = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw ActionExecutionError.processFailed(
                executable: "/usr/bin/zip",
                exitCode: process.terminationStatus,
                stderr: errorText
            )
        }

        return archiveURL
    }
}

