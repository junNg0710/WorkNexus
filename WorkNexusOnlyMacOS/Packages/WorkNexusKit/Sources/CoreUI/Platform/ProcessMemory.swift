/// Not in the Flutter app.
import Darwin
import Foundation

/// The memory this process holds, as Activity Monitor counts it.
public enum ProcessMemory {
    /// The physical footprint in bytes; nil when the system does not say.
    public static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }
}

/// When the memory in use is worth a line in the log: now and then, and at once when it has grown a lot - so a log
/// sent in after the system ended the app shows whether memory was climbing.
public struct MemoryLogPolicy: Sendable {
    public let every: TimeInterval
    public let growth: UInt64
    private var lastAt: Date?
    private var lastBytes: UInt64 = 0

    public init(every: TimeInterval = 30 * 60, growth: UInt64 = 200 << 20) { self.every = every; self.growth = growth }

    /// The line to write for `bytes` in use at `now`, or nil when it is not time for one.
    public mutating func line(bytes: UInt64, now: Date) -> String? {
        let grew = bytes > lastBytes && bytes - lastBytes >= growth
        if let lastAt, now.timeIntervalSince(lastAt) < every, !grew { return nil }
        defer { lastAt = now; lastBytes = bytes }
        let megabytes = { (b: UInt64) in "\(b >> 20) MB" }
        guard lastAt != nil else { return "Memory in use: \(megabytes(bytes))" }
        return "Memory in use: \(megabytes(bytes)) (\(bytes >= lastBytes ? "+" : "-")\(megabytes(bytes >= lastBytes ? bytes - lastBytes : lastBytes - bytes)) since the last note)"
    }
}
