/// Not in the Flutter app: the saved AI providers and choices, held on the main actor for the views.
import CoreDomain
import FeatureTranslation
import Foundation
import Observation

/// The `AiSetup` as the UI sees it: loaded once at startup and replaced on every save, so labels such as "Translate with
/// OpenAI (gpt-5-mini)" read it synchronously. The repository underneath keeps the same value cached for the routing.
@MainActor @Observable
final class AiSetupStore {
    private(set) var setup: AiSetup = .empty
    private(set) var loaded = false
    /// The stored setup could not be read (its item is damaged); everything runs on OpenCode until it is saved again.
    private(set) var loadFailed = false
    @ObservationIgnored private let repository: AiSetupRepository

    init(repository: AiSetupRepository) { self.repository = repository }

    func load() async {
        switch await repository.load() {
        case .success(let s): setup = s; loadFailed = false
        case .failure: loadFailed = true
        }
        loaded = true
    }

    /// Saves `new`; on success it is what everything reads from now on.
    @discardableResult
    func save(_ new: AiSetup) async -> Bool {
        guard case .success = await repository.save(new) else { return false }
        setup = new; loadFailed = false
        return true
    }

    /// What `purpose` runs on, for labels: `OpenAI (gpt-5-mini)`, `OpenCode`. `legacyModel` is `AppSettings.translationModel`.
    func backendName(_ purpose: AiPurpose, legacyModel: String) -> String {
        AiSettingsLogic.backendName(setup, purpose: purpose, legacyModel: legacyModel)
    }
}
