import CoreDomain
import Foundation

/// Ported from: lib/features/panic_switch/data/repositories/local_panic_switch_config_repository.dart
public struct FilePanicSwitchConfigRepository: PanicSwitchConfigRepository {
    private let file: PanicSwitchSettingsFile

    /// - Parameter url: the JSON file (`<Application Support>/panic_switch.json`).
    public init(url: URL) { file = PanicSwitchSettingsFile(url: url) }

    public func load() async -> Outcome<PanicSwitchConfig> {
        do {
            return .success(try file.read().map(PanicSwitchConfigMapper.fromJSON) ?? PanicSwitchConfig())
        } catch {
            return .failure(.storage("Could not read the panic switch settings: \(error.localizedDescription)"))
        }
    }

    public func save(_ config: PanicSwitchConfig) async -> Outcome<Void> {
        do {
            try file.write(try PanicSwitchConfigMapper.toJSON(config))
            return .success(())
        } catch {
            return .failure(.storage("Could not save the panic switch settings: \(error.localizedDescription)"))
        }
    }
}
