import Foundation

public enum GitPathResolver {
    public static func repositoryRoot(containing url: URL, fileManager: FileManager = .default) -> URL? {
        var current = directoryForSearch(from: url, fileManager: fileManager).standardizedFileURL

        while true {
            let gitPath = current.appendingPathComponent(".git").path
            if fileManager.fileExists(atPath: gitPath) {
                return current
            }

            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    public static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        guard itemPath.hasPrefix(rootPath) else {
            return itemPath
        }

        let start = itemPath.index(itemPath.startIndex, offsetBy: rootPath.count)
        let suffix = String(itemPath[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty ? "." : suffix
    }

    private static func directoryForSearch(from url: URL, fileManager: FileManager) -> URL {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }
}

