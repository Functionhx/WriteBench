import Foundation
import Darwin

struct ProcessRequest: Sendable {
    var executable: URL
    var arguments: [String]
    var directory: URL
    var input: Data = Data()
    var timeout: TimeInterval = 30
}
struct ProcessResult: Sendable {
    var status: Int32
    var stdout: Data
    var stderr: Data
    var text: String { String(decoding: stdout + stderr, as: UTF8.self) }
}
protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) async throws -> ProcessResult
}
// File-backed streams avoid pipe deadlocks. Each invocation owns private temporary files.
actor LocalProcessRunner: ProcessRunning {
    func run(_ request: ProcessRequest) async throws -> ProcessResult {
        try Task.checkCancellation()
        let fm = FileManager.default
        let io = fm.temporaryDirectory.appendingPathComponent("writebench-process-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: io, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: io) }
        let inputURL = io.appendingPathComponent("stdin"), outputURL = io.appendingPathComponent("stdout"), errorURL = io.appendingPathComponent("stderr")
        for (url, data) in [(inputURL, request.input), (outputURL, Data()), (errorURL, Data())] {
            guard fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw CodexError.launch }
        }
        let input = try FileHandle(forReadingFrom: inputURL), output = try FileHandle(forWritingTo: outputURL), error = try FileHandle(forWritingTo: errorURL)
        defer { try? input.close(); try? output.close(); try? error.close() }
        let process = Process()
        process.executableURL = request.executable; process.arguments = request.arguments; process.currentDirectoryURL = request.directory
        // No shell, interpolated command, API key, token or provider URL is passed to Codex.
        let inherited = ProcessInfo.processInfo.environment
        var environment = inherited.filter { ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "CODEX_HOME"].contains($0.key) }
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = error
        do { try process.run() } catch { throw CodexError.launch }
        let deadline = Date().addingTimeInterval(request.timeout)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                if Date() >= deadline { throw CodexError.timeout }
                for url in [outputURL, errorURL] {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    if size > 4_000_000 { throw CodexError.outputTooLarge }
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            try Task.checkCancellation()
        } catch {
            if process.isRunning {
                process.terminate()
                // Cancellation must not leave a paid CLI request running in the background.
                for _ in 0..<10 where process.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
            throw error
        }
        return ProcessResult(status: process.terminationStatus, stdout: try Data(contentsOf: outputURL), stderr: try Data(contentsOf: errorURL))
    }
}
