import Foundation

public protocol ClipboardWriting {
    func writeString(_ value: String) throws
}

public final class ProcessClipboardWriter: ClipboardWriting {
    public init() {}

    public func writeString(_ value: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")

        let input = Pipe()
        process.standardInput = input

        try process.run()
        input.fileHandleForWriting.write(Data(value.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
    }
}

public final class MemoryClipboardWriter: ClipboardWriting {
    public private(set) var value: String = ""

    public init() {}

    public func writeString(_ value: String) {
        self.value = value
    }
}

