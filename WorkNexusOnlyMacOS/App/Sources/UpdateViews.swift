import CoreDomain
import CoreUI
import FeatureAppUpdate
import SharedKit
import SwiftUI

/// Ported from: lib/features/app_update/presentation/widgets/update_rail_button.dart — hidden until a newer release is
/// known. While it downloads, a ring round the arrow fills with the progress (the tooltip says how far) and spins while
/// installing; once downloaded and verified it installs and restarts; a release without an in-app build opens its page.
struct UpdateRailButton: View {
    @Environment(\.openURL) private var openURL
    let model: UpdateModel

    var body: some View {
        switch model.state {
        case .idle: EmptyView()
        case .downloading(_, let progress):
            // Nothing to do until it is downloaded; the tooltip says how far.
            RailLabeledButton(label: appString("updateRailLabel", "Update"),
                              help: appString("updateDownloadingPercent", "Downloading the update… {percent}%")
                                  .replacingOccurrences(of: "{percent}", with: "\(Int((progress * 100).rounded()))"),
                              action: {}) { UpdateProgressRing(progress: progress) }
        case .ready(let u, _):
            RailLabeledButton(appString("updateRailLabel", "Update"), systemImage: "arrow.up.circle.fill",
                              help: appFormat("updateRestartToUpdate", "Restart to update to %1$@", u.latestTag)) {
                Task { await model.installAndRestart() }
            }
        case .installing:
            RailLabeledButton(label: appString("updateRailLabel", "Update"), help: appString("updateRestarting", "Installing — WorkNexus will restart…"),
                              action: {}) { UpdateProgressRing(progress: nil) }
        case .manual(let u), .failed(let u, _):
            RailLabeledButton(appString("updateRailLabel", "Update"), systemImage: "arrow.up.circle",
                              help: appString("updateRailAvailable", "Update available")) {
                if let url = URL(string: u.releaseUrl) { openURL(url) }
            }
        }
    }
}

/// The update banner under the title bar, and the What's new dialog shown once after an update (lib/features/app_update/
/// presentation/widgets/whats_new_at_launch.dart): the banner's container is always mounted, so it hosts the dialog.
struct UpdateBannerHost: View {
    let model: UpdateModel
    @Bindable var whatsNew: WhatsNewModel

    var body: some View {
        VStack(spacing: 0) { UpdateBannerView(model: model) }
            .appDialog(item: $whatsNew.news) { news in
                ReleaseNotesDialog(whatsNew: news) { whatsNew.dismiss() }
            }
    }
}
