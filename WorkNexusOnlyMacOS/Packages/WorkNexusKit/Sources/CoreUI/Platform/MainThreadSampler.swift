/// Not in the Flutter app.
import CoreDomain
import Darwin
import Foundation
import os

/// While the performance log is on and the app is in front: a watchdog thread that looks at what the main thread is
/// running whenever it has not drawn a frame for a moment, so a stutter no measured work explains still names the code
/// that held the screen up (`StallSamples`). The main thread says it is alive with `beat()` on every frame; nothing is
/// looked at while frames come on time.
///
/// Looking means stopping the main thread for a few microseconds and reading its call stack. While it is stopped the
/// watchdog allocates nothing and takes no lock (the main thread may hold either); names are found afterwards.
public final class MainThreadSampler: @unchecked Sendable {
    public static let shared = MainThreadSampler()

    /// The return addresses of one look, innermost first.
    public typealias Stack = [UInt]

    /// The main thread is looked at once it has been silent this long (a frame is late at 50 ms)...
    static let silentAfter: TimeInterval = 0.03
    /// ...then again this often, in microseconds...
    static let every: useconds_t = 10_000
    /// ...at most this many times per silence: frames also stop when the screen sleeps, with nothing to find.
    static let mostPerSilence = 150
    static let depth = 96

    private struct State {
        var generation = 0
        var running = false
        var lastBeat: TimeInterval = 0
        var stacks: [Stack] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var thread: thread_act_t = 0
    private var stackLow: UInt = 0, stackTop: UInt = 0

    init() {}

    /// Starts watching the main thread (call it there).
    @MainActor
    public func start() {
        if thread == 0 {
            let me = pthread_self()
            thread = pthread_mach_thread_np(me)
            stackTop = UInt(bitPattern: pthread_get_stackaddr_np(me))
            stackLow = stackTop - UInt(pthread_get_stacksize_np(me))
        }
        let generation = state.withLock { s -> Int in
            s.generation += 1; s.running = true; s.lastBeat = PerformanceLog.now(); s.stacks = []
            return s.generation
        }
        let watchdog = Thread { [self] in watch(generation) }
        watchdog.name = "com.worknexus.main-thread-sampler"
        watchdog.qualityOfService = .userInteractive
        watchdog.start()
    }

    @MainActor
    public func stop() {
        state.withLock { $0.running = false; $0.generation += 1; $0.stacks = [] }
    }

    /// The main thread is alive (a frame was drawn). Returns what it was seen running since the beat before - nothing,
    /// unless it was silent for a while.
    @MainActor
    public func beat() -> [Stack] {
        state.withLock { s in
            s.lastBeat = PerformanceLog.now()
            guard !s.stacks.isEmpty else { return [] }
            defer { s.stacks = [] }
            return s.stacks
        }
    }

    private func watch(_ generation: Int) {
        let buffer = UnsafeMutablePointer<UInt>.allocate(capacity: Self.depth)
        defer { buffer.deallocate() }
        var silence: TimeInterval = -1, looks = 0
        while true {
            usleep(Self.every)
            let (alive, beat) = state.withLock { ($0.running && $0.generation == generation, $0.lastBeat) }
            guard alive else { return }
            guard PerformanceLog.now() - beat >= Self.silentAfter else { continue }
            if beat != silence { silence = beat; looks = 0 }
            guard looks < Self.mostPerSilence else { continue }
            looks += 1
            let count = Self.look(thread, low: stackLow, top: stackTop, into: buffer, depth: Self.depth)
            guard count > 0 else { continue }
            let stack = Array(UnsafeBufferPointer(start: buffer, count: count))
            state.withLock { s in if s.running, s.generation == generation, s.lastBeat == beat { s.stacks.append(stack) } }
        }
    }

    /// Stops `thread`, copies its program counter and the return addresses up its stack into `out`, and lets it go on.
    /// Nothing here may allocate or lock: the stopped thread may be inside `malloc`.
    @inline(never)
    private static func look(_ thread: thread_act_t, low: UInt, top: UInt, into out: UnsafeMutablePointer<UInt>, depth: Int) -> Int {
        guard thread_suspend(thread) == KERN_SUCCESS else { return 0 }
        var pc: UInt = 0, fp: UInt = 0
        let ok = registers(thread, &pc, &fp)
        var count = 0
        if ok {
            out[0] = pc; count = 1
            // A frame record is two words: the caller's frame pointer, then the return address. Only inside the main
            // thread's own stack, and only upwards.
            while count < depth, fp >= low, fp &+ 16 <= top, fp & 7 == 0 {
                let record = UnsafePointer<UInt>(bitPattern: fp).unsafelyUnwrapped
                let next = record[0], back = record[1] & addressMask
                if back == 0 { break }
                out[count] = back; count += 1
                if next <= fp { break }
                fp = next
            }
        }
        thread_resume(thread)
        return count
    }

    /// The bits of a return address that are an address (the rest may hold a signature).
    private static let addressMask: UInt = 0x0000_7fff_ffff_ffff

    private static func registers(_ thread: thread_act_t, _ pc: inout UInt, _ fp: inout UInt) -> Bool {
        #if arch(arm64)
        var s = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &s) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { thread_get_state(thread, ARM_THREAD_STATE64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return false }
        pc = UInt(s.__pc) & addressMask; fp = UInt(s.__fp)
        return true
        #elseif arch(x86_64)
        var s = x86_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &s) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { thread_get_state(thread, x86_THREAD_STATE64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return false }
        pc = UInt(s.__rip); fp = UInt(s.__rbp)
        return true
        #else
        return false
        #endif
    }
}

// MARK: Names

extension MainThreadSampler {
    /// How often each place was seen in `stacks`: the innermost function of the app itself, or - when the app's code is
    /// nowhere on the stack but where it starts - the system function the thread was in.
    public static func tally(_ stacks: [Stack]) -> [String: Int] {
        var seen: [String: Int] = [:]
        var known: [UInt: Symbol?] = [:]
        for stack in stacks {
            var place: String?
            for (i, address) in stack.enumerated() {
                // A return address points after the call: one byte back is inside the calling function.
                let at = i == 0 ? address : address - 1
                let symbol: Symbol?
                if let hit = known[at] { symbol = hit } else { symbol = Symbol(at); known[at] = symbol }
                guard let symbol, symbol.isApp, !StallSamples.isEntry(symbol.name), !StallSamples.isLibrary(symbol.name) else { continue }
                place = symbol.name
                break
            }
            if place == nil, let top = stack.first, let leaf = Symbol(top) { place = "\(leaf.name) (\(leaf.image))" }
            if let place { seen[place, default: 0] += 1 }
        }
        return seen
    }

    struct Symbol {
        let name: String
        let image: String
        let isApp: Bool

        init?(_ address: UInt) {
            var info = Dl_info()
            guard dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0, let file = info.dli_fname, let symbol = info.dli_sname else { return nil }
            let path = String(cString: file)
            image = (path as NSString).lastPathComponent
            isApp = path == Self.ownImage
            name = StallSamples.short(Self.demangled(symbol))
        }

        /// The binary this code is in: the app (the whole package is linked into it).
        private static let ownImage: String = {
            var info = Dl_info()
            guard dladdr(#dsohandle, &info) != 0, let file = info.dli_fname else { return "" }
            return String(cString: file)
        }()

        private static func demangled(_ symbol: UnsafePointer<CChar>) -> String {
            guard let out = swift_demangle(symbol, UInt(strlen(symbol)), nil, nil, 0) ?? cxa_demangle(symbol, nil, nil, nil) else {
                return String(cString: symbol)
            }
            defer { free(out) }
            return String(cString: out)
        }
    }
}

/// The Swift runtime's own demangler; nil when `mangledName` is not a Swift symbol. The result is the caller's to free.
@_silgen_name("swift_demangle")
private func swift_demangle(_ mangledName: UnsafePointer<CChar>?, _ mangledNameLength: UInt, _ outputBuffer: UnsafeMutablePointer<CChar>?,
                            _ outputBufferSize: UnsafeMutablePointer<UInt>?, _ flags: UInt32) -> UnsafeMutablePointer<CChar>?

/// The C++ runtime's demangler (AttributeGraph, Core Animation), looked up in the running process - the package does
/// not link the C++ runtime itself; nil when `mangledName` is not a C++ symbol. The result is the caller's to free.
private func cxa_demangle(_ mangledName: UnsafePointer<CChar>?, _ outputBuffer: UnsafeMutablePointer<CChar>?,
                          _ length: UnsafeMutablePointer<Int>?, _ status: UnsafeMutablePointer<Int32>?) -> UnsafeMutablePointer<CChar>? {
    cxaDemangle?(mangledName, outputBuffer, length, status)
}

private typealias CxaDemangle = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?,
                                                UnsafeMutablePointer<Int32>?) -> UnsafeMutablePointer<CChar>?
/// `RTLD_DEFAULT` is -2: every image loaded.
private let cxaDemangle: CxaDemangle? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "__cxa_demangle").map { unsafeBitCast($0, to: CxaDemangle.self) }
