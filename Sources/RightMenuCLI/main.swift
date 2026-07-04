import Foundation
import RightMenuCore

@main
struct RightMenuCLI {
    static func main() throws {
        var args = Array(CommandLine.arguments.dropFirst())

        guard let command = args.first else {
            printUsage()
            return
        }
        args.removeFirst()

        switch command {
        case "list":
            for action in ActionCatalog.builtIns {
                print("\(action.id)\t\(action.title)")
            }

        case "config-path":
            print(JSONConfigurationStore.appSupportDefault().fileURL.path)

        case "write-default-config":
            let store = JSONConfigurationStore.appSupportDefault()
            try store.save(RightMenuConfiguration())
            print("Wrote \(store.fileURL.path)")

        case "log-path":
            print(JSONLinesExecutionLogStore.appSupportDefault().fileURL.path)

        case "run":
            guard let actionID = args.first else {
                printUsage()
                return
            }
            args.removeFirst()

            let context = try makeContext(from: args)
            guard let definition = ActionCatalog.definition(id: actionID) else {
                throw CLIError.unknownAction(actionID)
            }

            let result = try ActionExecutor().execute(definition, context: context)
            print(result.summary)

        default:
            printUsage()
        }
    }

    private static func makeContext(from rawPaths: [String]) throws -> FinderContext {
        let fileManager = FileManager.default
        if rawPaths.isEmpty {
            return FinderContext(
                targetDirectory: URL(fileURLWithPath: fileManager.currentDirectoryPath)
            )
        }

        let items = rawPaths.map { rawPath -> FinderItem in
            let url = URL(fileURLWithPath: rawPath)
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return FinderItem(url: url, isDirectory: isDirectory.boolValue)
        }

        let targetDirectory = items.count == 1 && items[0].isDirectory
            ? items[0].url
            : items.first?.url.deletingLastPathComponent()

        return FinderContext(selectedItems: items, targetDirectory: targetDirectory)
    }

    private static func printUsage() {
        print("""
        Usage:
          rightmenu-cli list
          rightmenu-cli config-path
          rightmenu-cli write-default-config
          rightmenu-cli log-path
          rightmenu-cli run <action-id> [paths...]
        """)
    }
}

enum CLIError: Error, LocalizedError {
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case let .unknownAction(actionID):
            return "Unknown action: \(actionID)"
        }
    }
}
