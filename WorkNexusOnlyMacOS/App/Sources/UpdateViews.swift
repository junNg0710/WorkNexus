import CoreDomain
import CoreUI
import FeatureAppUpdate
import SharedKit
import SwiftUI

/// Ported from: lib/features/app_update/presentation/widgets/update_rail_button.dart — shows only once a newer release
/// is known: install and restart when downloaded, the release page otherwise, hidden while downloading (as in Dart).
struct UpdateRailButton: View {
    @Environment(\.openURL) private var openURL
    let model: UpdateModel

    var body: some View {
        switch model.state {
        case .idle: EmptyView()
        case .downloading: EmptyView()   // hidden until downloaded and verified, as in Dart (UpdateIdle / UpdateDownloading)
        case .ready:
            RailLabeledButton(appString("updateRailLabel", "Update"), systemImage: "arrow.up.circle.fill",
                              help: appString("updateRestartNow", "Update & restart")) { Task { await model.installAndRestart() } }
        case .installing:
            RailLabeledButton(appString("updateRailLabel", "Update"), systemImage: "arrow.triangle.2.circlepath") {}
                .disabled(true)
        case .manual(let u), .failed(let u, _):
            RailLabeledButton(appString("updateRailLabel", "Update"), systemImage: "arrow.up.circle",
                              help: appString("updateRailAvailable", "Update available")) {
                if let url = URL(string: u.releaseUrl) { openURL(url) }
            }
        }
    }
}
