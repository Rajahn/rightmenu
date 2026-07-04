import Foundation

public enum FileNaming {
    public static func nextAvailableFileURL(
        in directory: URL,
        baseName: String,
        fileExtension: String,
        fileManager: FileManager = .default
    ) -> URL {
        let first = directory.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        if !fileManager.fileExists(atPath: first.path) {
            return first
        }

        var index = 2
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName) \(index)")
                .appendingPathExtension(fileExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    public static func nextAvailableURL(
        named originalName: String,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let first = directory.appendingPathComponent(originalName)
        if !fileManager.fileExists(atPath: first.path) {
            return first
        }

        let nsName = originalName as NSString
        let baseName = nsName.deletingPathExtension
        let fileExtension = nsName.pathExtension

        var index = 2
        while true {
            let candidateName = fileExtension.isEmpty
                ? "\(baseName) \(index)"
                : "\(baseName) \(index).\(fileExtension)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    public static func shellEscapedPath(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
