import Foundation

/// Ported from: lib/features/translation/data/datasources/opencode_cli_runner.dart
/// `OpenCodeCli` backed by the real `opencode` binary. Every call is a short, read-only subcommand run on a UI path
/// (gating Translate, filling the model picker), so each one is bounded by `queryTimeout` and the child is killed when
/// it expires — a wedged CLI must not wedge the app.
public final class OpenCodeCliRunner: OpenCodeCli, @unchecked Sendable {
    private let runner: CliRunner
    private let queryTimeout: TimeInterval

    public init(runner: CliRunner = CliRunner(), queryTimeout: TimeInterval = 25) {
        self.runner = runner; self.queryTimeout = queryTimeout
    }

    public func hasAuthenticatedProvider() async -> Bool {
        guard let out = await query(["auth", "list"]) else { return false }
        if let n = Self.credentialCount(out) { return n > 0 }
        return out.contains("●")   // fallback: a provider bullet is present
    }

    public func listModels() async -> [String] {
        guard let out = await query(["models"]) else { return [] }
        return Self.modelIds(out)
    }

    static func credentialCount(_ out: String) -> Int? {
        guard let r = out.range(of: #"(\d+)\s+credential"#, options: .regularExpression) else { return nil }
        return Int(out[r].prefix { $0.isNumber })
    }

    /// `provider/model`, one per line — banners and error text are ignored.
    static func modelIds(_ out: String) -> [String] {
        var ids = Set<String>()
        for line in out.split(separator: "\n") {
            let id = line.trimmingCharacters(in: .whitespaces)
            if id.range(of: #"^[\w.-]+/[\w.:-]+$"#, options: .regularExpression) != nil { ids.insert(id) }
        }
        return ids.sorted()
    }

    /// Runs an `opencode` subcommand and returns its combined output, or nil when the binary is missing, the call
    /// fails, or it outlives `queryTimeout`.
    private func query(_ args: [String]) async -> String? {
        guard let path = await runner.resolve("opencode") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err; process.standardInput = FileHandle.nullDevice
        let so = PipeCapture(out), se = PipeCapture(err)
        let timedOut = Locked(false)
        let ok: Bool = await withCheckedContinuation { cont in
            process.terminationHandler = { _ in cont.resume(returning: true) }
            do { try process.run() } catch { cont.resume(returning: false); return }
            try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
            DispatchQueue.global().asyncAfter(deadline: .now() + queryTimeout) { [weak process] in
                guard let process, process.isRunning else { return }
                timedOut.withLock { $0 = true }
                process.terminate()
            }
        }
        guard ok else { return nil }
        async let a = so.text(within: 1), b = se.text(within: 1)
        let (outText, errText) = await (a, b)
        return timedOut.withLock({ $0 }) ? nil : outText + errText
    }
}
