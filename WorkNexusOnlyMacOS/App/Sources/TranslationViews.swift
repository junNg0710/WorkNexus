import CoreDomain
import CoreUI
import FeatureTranslation
import Foundation
import Observation
import SwiftUI

/// The state behind one ticket's translation: the cached record (watched), whether a run is in flight, the reason the last one
/// failed. The tab and the footer of the same ticket share one (lib/features/translation presentation providers).
@MainActor @Observable
final class TranslationTabModel {
    private(set) var record: TranslationRecord?
    private(set) var loading = false
    private(set) var failure: String?
    /// The language picked for this ticket (the header's translate button, the footer's picker); nil: Settings' language.
    private(set) var pickedLang: String?
    let ticketId: String
    private let hub: TranslationHub
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var run: Task<Void, Never>?

    fileprivate init(ticketId: String, hub: TranslationHub) { self.ticketId = ticketId; self.hub = hub }

    static func source(of ticket: Ticket) -> TicketSource { TicketSource(title: ticket.title, body: ticket.body) }

    /// The language this ticket is translated into.
    var targetLang: String { pickedLang ?? hub.settings().translationLang }

    func state(_ ticket: Ticket) -> TranslationState {
        let feature = hub.feature
        // A stored translation in another language is not this one: it is asked for again.
        let current = record.flatMap { $0.targetLang == targetLang ? $0 : nil }
        return feature.resolveState(currentSourceHash: feature.service.contentHash(Self.source(of: ticket)), record: current, loading: loading, hasError: failure != nil)
    }

    /// Starts watching the cached record (the views call it when they appear).
    func start() {
        guard watcher == nil else { return }
        let id = ticketId, repo = hub.feature.repository
        watcher = Task { [weak self] in
            for await r in repo.watchTranslation(ticketId: id) { self?.record = r }
        }
    }

    /// Translates through the provider chosen for translation, first making sure it is set up; a run in flight is left alone.
    /// `language` translates this ticket into it from now on (Settings' language is left as it is).
    func translate(_ ticket: Ticket, into language: String? = nil) {
        guard !loading else { return }
        if let language { pickedLang = language }
        loading = true; failure = nil
        let feature = hub.feature, settings = hub.settings(), gate = hub.gate, target = targetLang
        run = Task { [weak self] in
            defer { self?.loading = false }
            guard await gate.ensureLinked() else { return }
            let src = Self.source(of: ticket)
            let model = settings.translationModel.isEmpty ? nil : settings.translationModel
            switch await feature.service.translate(ticketId: ticket.id, source: src, sourceHash: feature.service.contentHash(src),
                                                   targetLang: target, model: model) {
            case .success(let rec): _ = await feature.repository.saveTranslation(rec)
            case .failure(let f): if case .cancelled = f {} else { self?.failure = f.message }
            }
        }
    }

    /// Aborts the run in flight (a queued model, a wedged CLI); the footer offers it while loading.
    func cancel() { Task { await hub.feature.service.cancel(ticketId) } }
}

/// One `TranslationTabModel` per ticket, so the footer and the tab of a ticket — drawn by different parts of the detail panel —
/// read and drive the same run.
@MainActor
final class TranslationHub {
    let feature: TranslationFeature
    /// What translation runs on, for the "Translate with …" labels.
    let aiSetup: AiSetupStore
    let settings: () -> AppSettings
    let gate: OpenCodeLinkGate
    private var models: [String: TranslationTabModel] = [:]

    init(feature: TranslationFeature, aiSetup: AiSetupStore, settings: @escaping () -> AppSettings, gate: OpenCodeLinkGate) {
        self.feature = feature; self.aiSetup = aiSetup; self.settings = settings; self.gate = gate
    }

    /// The translation backend's name: `OpenAI (gpt-5-mini)`, `OpenCode`.
    var backendName: String { aiSetup.backendName(.translation, legacyModel: settings().translationModel) }

    func model(for ticketId: String) -> TranslationTabModel {
        if let m = models[ticketId] { return m }
        let m = TranslationTabModel(ticketId: ticketId, hub: self)
        models[ticketId] = m
        return m
    }
}

/// The small translation-state dot on a board card: green when the cached translation is current, amber when the ticket
/// changed since, nothing when it was never translated.
struct TranslationDot: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    let feature: TranslationFeature
    @State private var record: TranslationRecord?

    var body: some View {
        let hash = feature.service.contentHash(TicketSource(title: ticket.title, body: ticket.body))
        let state = feature.resolveState(currentSourceHash: hash, record: record)
        Group {
            if state == .done || state == .outdated {
                Circle().fill(state == .done ? theme.colors.green : theme.colors.amber).frame(width: 8, height: 8)
                    .help(state == .done ? appString("translationStateDone", "Translated") : appString("translationStateOutdated", "Out of date"))
            }
        }
        .task(id: ticket.id) {
            for await r in feature.repository.watchTranslation(ticketId: ticket.id) { record = r }
        }
    }
}
