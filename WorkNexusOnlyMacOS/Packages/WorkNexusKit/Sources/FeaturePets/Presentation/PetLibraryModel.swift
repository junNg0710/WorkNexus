import CoreDomain
import CoreUI
import Foundation
import Observation

/// The pets installed on this Mac, and the sprite sheet of the one shown. Sheets are read off the main thread, once each:
/// until a pet's sheet is ready (or when it cannot be read) `sheet(for:)` says nil and the TBChat character stands in.
/// Not in the Flutter app.
@MainActor @Observable
public final class PetLibraryModel {
    public private(set) var installed: [InstalledPet] = []
    /// Pets being downloaded, by id.
    public private(set) var installing: Set<String> = []
    /// What went wrong with the last install or removal; nil once one goes through.
    public private(set) var lastError: String?
    private var sheets: [String: PetSpriteSheet] = [:]

    @ObservationIgnored private let services: PetsFeature.Services
    @ObservationIgnored private var reading: Set<String> = []
    @ObservationIgnored private var unreadable: Set<String> = []

    public init(services: PetsFeature.Services) {
        self.services = services
        Task { await refresh() }
    }

    public func refresh() async {
        if let pets = await services.listInstalled().value { installed = pets }
    }

    public func isInstalled(_ id: String) -> Bool { installed.contains { $0.id == id } }

    /// The sheet of installed pet `id`; nil for the TBChat character (`id` nil), a pet not installed, or one still being read.
    public func sheet(for id: String?) -> PetSpriteSheet? {
        guard let id, let pet = installed.first(where: { $0.id == id }) else { return nil }
        if let sheet = sheets[id] { return sheet }
        guard !reading.contains(id), !unreadable.contains(id) else { return nil }
        reading.insert(id)
        let url = pet.spritesheetURL
        // Not during the view update that asked: the sheet is published on a later turn of the main actor.
        Task {
            let sheet = await Task.detached(priority: .userInitiated) { PetSpriteSheet(contentsOf: url) }.value
            reading.remove(id)
            if let sheet { sheets[id] = sheet } else { unreadable.insert(id) }
        }
        return nil
    }

    /// Downloads `pet`; true once it is installed.
    @discardableResult
    public func install(_ pet: CatalogPet) async -> Bool {
        guard !installing.contains(pet.id) else { return false }
        installing.insert(pet.id)
        defer { installing.remove(pet.id) }
        switch await services.install(pet) {
        case .success(let done):
            sheets[done.id] = nil; unreadable.remove(done.id)
            installed.removeAll { $0.id == done.id }
            installed.append(done)
            installed.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            lastError = nil
            return true
        case .failure(let f):
            lastError = f.message
            Diagnostics.warning("pets", "install \(pet.id) failed: \(f.message)")
            return false
        }
    }

    public func remove(_ id: String) async {
        switch await services.remove(id: id) {
        case .success:
            installed.removeAll { $0.id == id }
            sheets[id] = nil
            lastError = nil
        case .failure(let f):
            lastError = f.message
        }
    }
}
