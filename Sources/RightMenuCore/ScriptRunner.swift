import Foundation

public struct ScriptExecutionResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct ScriptRunner {
    public init() {}

    public func run(
        _ action: ShellScriptAction,
        context: FinderContext,
        timeoutSeconds: Int
    ) throws -> ScriptExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: action.shell)
        process.arguments = ["-c", action.script, "rightmenu-action"] + context.itemsOrTarget.map(\.path)

        var environment = ProcessInfo.processInfo.environment
        environment["RIGHTMENU_PATHS"] = context.itemsOrTarget.map(\.path).joined(separator: "\n")
        environment["RIGHTMENU_TARGET_DIR"] = context.primaryDirectory?.path ?? ""
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
            process.terminate()
            throw ActionExecutionError.scriptTimedOut(seconds: timeoutSeconds)
        }

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return ScriptExecutionResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}

