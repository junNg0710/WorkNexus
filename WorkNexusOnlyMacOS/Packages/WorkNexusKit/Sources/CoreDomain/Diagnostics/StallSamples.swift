/// Not in the Flutter app.
import Foundation

/// Where the main thread was seen while it held frames up (`MainThreadSampler` looks every few milliseconds of a stall),
/// as the performance log writes it: what no measured work explains still gets a name.
public enum StallSamples {
    /// "main thread in A ×12, B ×5": the `limit` places seen most often (each time seen is about ten milliseconds). Nil
    /// when the main thread was not seen anywhere.
    public static func describe(_ seen: [String: Int], limit: Int = 4) -> String? {
        guard !seen.isEmpty else { return nil }
        let top = seen.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit)
        return "main thread in " + top.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
    }

    /// The main thread was only waiting for the next event: the frame was late for another reason than the app's own
    /// work (the display or the window server did not come for it in time).
    public static let idle = "nothing (waiting for the next event)"

    /// Whether everything seen during a late frame was the main thread waiting.
    public static func onlyIdle(_ seen: [String: Int]) -> Bool { !seen.isEmpty && seen.keys.allSatisfy { $0 == idle } }

    /// A demangled symbol short enough for a log line: the function without its arguments, generics or result; a closure
    /// is named after the function it is in.
    public static func short(_ name: String) -> String {
        // A private name carries the file it is private to: "(load in _8C4801BC…)" is just "load".
        var s = Substring(name.replacing(privateName) { String($0.output.1) })
        var closure = false
        for prefix in ["partial apply forwarder for ", "merged "] where s.hasPrefix(prefix) { s = s.dropFirst(prefix.count) }
        // "(extension in Swift):Swift.Array.filter" is "Swift.Array.filter".
        if s.hasPrefix("(extension in "), let r = s.range(of: "):") { s = s[r.upperBound...] }
        while s.hasPrefix("closure #") || s.hasPrefix("implicit closure #"), let r = s.range(of: " in ") {
            s = s[r.upperBound...]; closure = true
        }
        for stop in ["(", " : ", " -> ", "<"] {
            if let r = s.range(of: stop), r.lowerBound > s.startIndex { s = s[..<r.lowerBound] }
        }
        let out = String(s.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return closure ? out + " {closure}" : out
    }

    /// Whether a (shortened) symbol is where the app starts: every stack of the main thread ends there, so it says nothing.
    public static func isEntry(_ short: String) -> Bool {
        short == "main" || short.hasSuffix(".$main") || short.hasSuffix(".main") || short.hasSuffix("_dylib_entry_point")
    }

    /// Whether a (shortened) symbol is library code that was compiled into the app (a standard-library function made for
    /// one of the app's types, a bridged AppKit initialiser): the app's function that called it is the one to name.
    public static func isLibrary(_ short: String) -> Bool {
        ["Swift.", "__C.", "@nonobjc ", "@objc ", "generic specialization", "function signature specialization", "reabstraction thunk",
         "protocol witness", "Foundation.", "SwiftUI."].contains { short.hasPrefix($0) }
    }

    static let maxLength = 80
    nonisolated(unsafe) private static let privateName = #/\((\w+) in _[0-9A-F]+\)/#
}
