import Foundation

/// Runs a program and returns its stdout, or nil when it fails (not found, non-zero exit, or too slow).
typealias RunProcess = @Sendable (_ executable: String, _ arguments: [String]) async -> String?

/// Finds the `node` an AI tool should run the MCP server with.
///
/// An app opened from the Dock does not inherit the user's shell `PATH` (Homebrew, nvm, …), so it asks the user's login
/// shell, then falls back to the usual install places.
/// Ported from: lib/features/chat/data/datasources/node_runtime_probe.dart (macOS branch only)
struct NodeRuntimeProbe: Sendable {
    struct Found: Equatable, Sendable { let path: String; let version: String }

    private let run: RunProcess
    private let environment: [String: String]
    static let fallbacks = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]

    init(run: @escaping RunProcess = NodeRuntimeProbe.runProcess, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.run = run; self.environment = environment
    }

    /// Every `node` that runs, with its `--version`, in the order the user's `PATH` would pick them, then the usual places.
    func findAll() async -> [Found] {
        var found: [Found] = [], seen = Set<String>()
        for candidate in await candidates() {
            guard let version = await run(candidate, ["--version"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  version.hasPrefix("v") else { continue }
            let path = await stablePath(candidate)
            if seen.insert(path).inserted { found.append(Found(path: path, version: version)) }
        }
        return found
    }

    /// Where a version manager's shim or per-shell link really runs node from. An fnm "multishell" link lives in a temporary
    /// folder that is gone after a restart; an asdf / mise shim picks the version by the folder it runs in, which for an AI
    /// tool is not the user's project. Any other path — Homebrew's `bin/node` link included, which survives upgrades unlike
    /// the versioned folder it points into — is kept as it is.
    private func stablePath(_ path: String) async -> String {
        guard path.contains("fnm_multishells") || path.contains("/shims/") else { return path }
        let real = await run(path, ["-p", "process.execPath"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (real?.isEmpty == false) ? real! : path
    }

    private func candidates() async -> [String] {
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        // A login shell has the profile's PATH; only if that has no node, an interactive one, which also reads the rc file
        // nvm usually sets up in.
        var fromShell = await shellNode(shell, "-lc")
        if fromShell.isEmpty { fromShell = await shellNode(shell, "-lic") }
        var ordered: [String] = [], seen = Set<String>()
        for p in fromShell + Self.fallbacks where seen.insert(p).inserted { ordered.append(p) }
        return ordered
    }

    private func shellNode(_ shell: String, _ flags: String) async -> [String] {
        Self.lines(await run(shell, [flags, "command -v node"])).filter { $0.hasPrefix("/") }
    }

    static func lines(_ out: String?) -> [String] {
        (out ?? "").components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Runs `executable` with no input, for at most 5 seconds; its stdout when it exits with 0.
    static let runProcess: RunProcess = { executable, arguments in
        await withCheckedContinuation { continuation in
            let process = Process(), out = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { p in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: p.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil)
            }
            do { try process.run() } catch {
                // Not installed or not executable: not a usable node.
                process.terminationHandler = nil
                continuation.resume(returning: nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if process.isRunning { process.terminate() } }
        }
    }
}
