import CoreDomain
import Foundation

/// Ported from: lib/features/translation/data/repositories/opencode_auth_file_key_repository.dart
/// `OpenCodeKeyRepository` backed by OpenCode's own `auth.json`: saving is the programmatic equivalent of
/// `opencode auth login`, so usage stays on the user's own account.
public struct OpenCodeAuthFileKeyRepository: OpenCodeKeyRepository {
    private let file: OpenCodeAuthFile
    public init(file: OpenCodeAuthFile = OpenCodeAuthFile()) { self.file = file }

    public func authFor(providerId: String) async -> Outcome<OpenCodeProviderAuth> {
        do {
            guard let entry = try file.read()[providerId.trimmingCharacters(in: .whitespaces)] else { return .success(.none) }
            let fields = entry as? [String: Any] ?? [:]
            return .success(OpenCodeProviderAuth(linked: true, keyPreview: (fields["type"] as? String) == "api" ? Self.mask(fields["key"] as? String) : nil))
        } catch let e as NSError where Self.isMalformedJSON(e) {
            return .failure(Self.malformed)
        } catch {
            return .failure(.storage("Could not read OpenCode credentials: \(error.localizedDescription)"))
        }
    }

    public func saveApiKey(providerId: String, key: String) async -> Outcome<Void> {
        let id = providerId.trimmingCharacters(in: .whitespaces), secret = key.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !secret.isEmpty else { return .failure(.storage("Provider and API key are required")) }
        do {
            // Read–modify–write of the whole file so entries we don't touch (OAuth logins, other providers) survive.
            var entries = try file.read()
            entries[id] = ["type": "api", "key": secret]
            try file.write(entries)
            return .success(())
        } catch let e as NSError where Self.isMalformedJSON(e) {
            return .failure(Self.malformed)
        } catch {
            return .failure(.storage("Could not write OpenCode credentials: \(error.localizedDescription)"))
        }
    }

    public func removeApiKey(providerId: String) async -> Outcome<Void> {
        let id = providerId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return .failure(.storage("Provider is required")) }
        do {
            var entries = try file.read()
            // Only an API key goes: an OAuth login (`opencode auth login`) is not ours to delete.
            guard (entries[id] as? [String: Any])?["type"] as? String == "api" else { return .success(()) }
            entries[id] = nil
            try file.write(entries)
            return .success(())
        } catch let e as NSError where Self.isMalformedJSON(e) {
            return .failure(Self.malformed)
        } catch {
            return .failure(.storage("Could not write OpenCode credentials: \(error.localizedDescription)"))
        }
    }

    private static func isMalformedJSON(_ e: NSError) -> Bool { e.domain == NSCocoaErrorDomain && e.code == 3840 }

    /// Refuse to guess at a file we can't parse — overwriting it would wipe working logins.
    static let malformed = Failure.parse("OpenCode's credentials file isn't valid JSON — fix it with `opencode auth login` before saving a key here.")

    /// Recognizable but not recoverable: the last four characters behind a fixed-width mask.
    static func mask(_ key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        let dots = "••••••"
        return key.count <= 4 ? dots : dots + key.suffix(4)
    }
}
