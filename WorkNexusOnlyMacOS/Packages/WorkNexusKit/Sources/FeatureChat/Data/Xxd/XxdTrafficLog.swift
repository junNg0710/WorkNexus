import CoreDomain
import Foundation
import os

/// Chat socket traffic log. Only method names, outcomes and timings are logged — never params or payloads, which carry
/// message text and the login password.
/// Ported from: lib/features/chat/data/datasources/xxd/xxd_traffic_log.dart
public struct XxdTrafficLog: Sendable {
    private let logger = Logger(subsystem: "com.worknexus.chat", category: "xxd")
    public init() {}

    func request(_ r: XxdRequest) { if r.apiName != "ping" { logger.debug("→ \(r.method, privacy: .public)") } }

    func reply(_ api: String, _ elapsed: TimeInterval, _ p: XxdResponse) {
        logger.info("← \(api, privacy: .public) \(p.isSuccess ? "ok" : "failed: \(p.message ?? "-")", privacy: .public) (\(Int(elapsed * 1000)) ms)")
    }

    func failed(_ api: String, _ elapsed: TimeInterval, _ f: Failure) {
        logger.error("← \(api, privacy: .public) failed: \(f.message, privacy: .public) (\(Int(elapsed * 1000)) ms)")
    }

    func push(_ p: XxdResponse) { if p.apiName != "ping" { logger.debug("⇠ \(p.apiName, privacy: .public)") } }

    func state(_ s: XxdConnectionState) {
        switch s {
        case .disconnected: logger.info("disconnected")
        case .connecting: logger.info("connecting")
        case .online: logger.info("online")
        case .reconnecting(let a, let d, let f): logger.warning("reconnecting #\(a) in \(Int(d)) s (\(f.message, privacy: .public))")
        case .stopped(let f, _): logger.error("stopped: \(f.message, privacy: .public)")
        }
    }
}
