import CoreDomain
import Foundation
import Observation

/// Ported from: lib/features/connections/presentation/connection_controllers.dart (`AddConnectionState`,
/// `AddConnectionController`). The state of the add-connection form: busy while connecting, the last error, and
/// `done` once the account is saved (the dialog closes then, even if the first sync failed - the error is shown
/// as a toast by the host).
@MainActor @Observable
public final class AddConnectionModel {
    public private(set) var busy = false
    public private(set) var error: String?
    public private(set) var done = false
    /// "Connected, but sync failed: ..." - the account was kept.
    public private(set) var syncWarning: String?

    @ObservationIgnored private let connect: (ConnectRequest) async -> ConnectResult
    public init(connect: @escaping (ConnectRequest) async -> ConnectResult) { self.connect = connect }

    public func reset() { busy = false; error = nil; done = false; syncWarning = nil }

    /// Returns true if the account was added.
    @discardableResult
    public func submit(_ request: ConnectRequest) async -> Bool {
        busy = true; error = nil; syncWarning = nil
        let result = await connect(request)
        busy = false
        switch result {
        case .added: done = true; return true
        case .addedButSyncFailed(_, let message):
            syncWarning = L.connectedButSyncFailed(message); done = true; return true
        case .failed(let issue):
            error = Self.text(issue); return false
        }
    }

    static func text(_ issue: ConnectIssue) -> String {
        switch issue {
        case .allFieldsRequired: L.allFieldsRequired
        case .noWorkspace: L.chooseWorkspace
        case .connectionFailed: L.connectionFailed
        case .rejected(let message): message
        }
    }
}
