import Foundation

public enum ActionCatalog {
    public static let builtIns: [ActionDefinition] = [
        ActionDefinition(
            id: BuiltInActionID.copyAbsolutePaths.rawValue,
            title: "Copy Absolute Path",
            category: .copy,
            supportedShapes: [.emptyArea, .anySelection],
            handler: .builtIn(.copyAbsolutePaths)
        ),
        ActionDefinition(
            id: BuiltInActionID.copyFileURLs.rawValue,
            title: "Copy File URL",
            category: .copy,
            supportedShapes: [.emptyArea, .anySelection],
            handler: .builtIn(.copyFileURLs)
        ),
        ActionDefinition(
            id: BuiltInActionID.copyFileNames.rawValue,
            title: "Copy File Name",
            category: .copy,
            supportedShapes: [.emptyArea, .anySelection],
            handler: .builtIn(.copyFileNames)
        ),
        ActionDefinition(
            id: BuiltInActionID.copyParentDirectories.rawValue,
            title: "Copy Parent Directory",
            category: .copy,
            supportedShapes: [.emptyArea, .anySelection],
            handler: .builtIn(.copyParentDirectories)
        ),
        ActionDefinition(
            id: BuiltInActionID.copyMarkdownLinks.rawValue,
            title: "Copy Markdown Link",
            category: .copy,
            supportedShapes: [.emptyArea, .anySelection],
            handler: .builtIn(.copyMarkdownLinks)
        ),
        ActionDefinition(
            id: BuiltInActionID.copyShellEscapedPaths.rawValue,
            title: "Copy Shell-Escaped Path",
            category: .copy,
            supportedShapes: [.emptyArea, .anySelection],
            handler: .builtIn(.copyShellEscapedPaths)
        ),
        ActionDefinition(
            id: BuiltInActionID.copyGitRelativePaths.rawValue,
            title: "Copy Git-Relative Path",
            category: .copy,
            supportedShapes: [.anySelection],
            handler: .builtIn(.copyGitRelativePaths)
        ),
        ActionDefinition(
            id: BuiltInActionID.newTextFile.rawValue,
            title: "New Text File",
            category: .create,
            supportedShapes: [.emptyArea, .singleFolder, .directoryContext],
            handler: .builtIn(.newTextFile)
        ),
        ActionDefinition(
            id: BuiltInActionID.newMarkdownFile.rawValue,
            title: "New Markdown File",
            category: .create,
            supportedShapes: [.emptyArea, .singleFolder, .directoryContext],
            handler: .builtIn(.newMarkdownFile)
        ),
        ActionDefinition(
            id: BuiltInActionID.newJSONFile.rawValue,
            title: "New JSON File",
            category: .create,
            supportedShapes: [.emptyArea, .singleFolder, .directoryContext],
            handler: .builtIn(.newJSONFile)
        ),
        ActionDefinition(
            id: BuiltInActionID.newYAMLFile.rawValue,
            title: "New YAML File",
            category: .create,
            supportedShapes: [.emptyArea, .singleFolder, .directoryContext],
            handler: .builtIn(.newYAMLFile)
        ),
        ActionDefinition(
            id: BuiltInActionID.cutItems.rawValue,
            title: "Cut Items",
            category: .move,
            supportedShapes: [.anySelection],
            handler: .builtIn(.cutItems)
        ),
        ActionDefinition(
            id: BuiltInActionID.pasteCutItems.rawValue,
            title: "Paste Cut Items Here",
            category: .move,
            supportedShapes: [.emptyArea, .singleFolder, .directoryContext],
            handler: .builtIn(.pasteCutItems)
        ),
        ActionDefinition(
            id: BuiltInActionID.computeMD5.rawValue,
            title: "Copy MD5",
            category: .utility,
            supportedShapes: [.anySelection],
            handler: .builtIn(.computeMD5)
        ),
        ActionDefinition(
            id: BuiltInActionID.computeSHA256.rawValue,
            title: "Copy SHA-256",
            category: .utility,
            supportedShapes: [.anySelection],
            handler: .builtIn(.computeSHA256)
        ),
        ActionDefinition(
            id: BuiltInActionID.zipItems.rawValue,
            title: "Zip Items",
            category: .utility,
            supportedShapes: [.anySelection],
            handler: .builtIn(.zipItems)
        ),
        ActionDefinition(
            id: "open.terminal",
            title: "Open in Terminal",
            category: .open,
            supportedShapes: [.emptyArea, .anySelection, .directoryContext],
            handler: .shellScript(ShellScriptAction(script: #"open -a Terminal "${RIGHTMENU_TARGET_DIR:-$1}""#))
        ),
        ActionDefinition(
            id: "open.vscode",
            title: "Open in VS Code",
            category: .open,
            supportedShapes: [.emptyArea, .anySelection, .directoryContext],
            handler: .shellScript(ShellScriptAction(script: #"if command -v code >/dev/null 2>&1; then code "${RIGHTMENU_TARGET_DIR:-$1}"; else open -a "Visual Studio Code" "${RIGHTMENU_TARGET_DIR:-$1}"; fi"#))
        ),
        ActionDefinition(
            id: "open.cursor",
            title: "Open in Cursor",
            category: .open,
            supportedShapes: [.emptyArea, .anySelection, .directoryContext],
            handler: .shellScript(ShellScriptAction(script: #"if command -v cursor >/dev/null 2>&1; then cursor "${RIGHTMENU_TARGET_DIR:-$1}"; else open -a Cursor "${RIGHTMENU_TARGET_DIR:-$1}"; fi"#))
        ),
        ActionDefinition(
            id: "open.reveal-in-finder",
            title: "Reveal in Finder",
            category: .open,
            supportedShapes: [.anySelection],
            handler: .shellScript(ShellScriptAction(script: #"for item in "$@"; do open -R "$item"; done"#))
        )
    ]

    public static func definition(id: String) -> ActionDefinition? {
        builtIns.first { $0.id == id }
    }
}
