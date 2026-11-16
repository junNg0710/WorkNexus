import Foundation
import WebKit

/// Ported from: lib/features/mini_apps/presentation/util/mini_app_permission_kind.dart
/// How each kind of permission is shown (SF Symbols for Lucide), and how the web view's own names for them map onto the app's.
extension MiniAppPermissionKind {
    var systemImage: String {
        switch self {
        case .notifications: "bell"
        case .clipboard: "doc.on.clipboard"
        case .autoplay: "play.circle"
        case .multipleDownloads: "arrow.down.circle"
        case .localFonts: "textformat"
        case .camera: "camera"
        case .microphone: "mic"
        case .location: "mappin"
        case .other: "shield"
        }
    }

    private var key: String {
        switch self {
        case .notifications: "Notifications"
        case .clipboard: "Clipboard"
        case .autoplay: "Autoplay"
        case .multipleDownloads: "MultipleDownloads"
        case .localFonts: "LocalFonts"
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .location: "Location"
        case .other: "Other"
        }
    }

    /// The name in the permissions list ("Camera").
    var label: String { localizedKey("miniAppPerm\(key)Label") }
    /// What the page wants, as a phrase after "wants to" ("use your camera").
    var action: String { localizedKey("miniAppPerm\(key)Action") }
    /// One line on what allowing it means.
    var detail: String { localizedKey("miniAppPerm\(key)Desc") }
}

/// The kinds a web view's media capture request stands for (camera and microphone together are two).
func miniAppPermissionKinds(of type: WKMediaCaptureType) -> [MiniAppPermissionKind] {
    switch type {
    case .camera: [.camera]
    case .microphone: [.microphone]
    case .cameraAndMicrophone: [.camera, .microphone]
    @unknown default: [.other]
    }
}

/// A string from the app's `Localizable.xcstrings` by a key built at run time (`String(localized:)` takes literal keys only).
func localizedKey(_ key: String) -> String { Bundle.main.localizedString(forKey: key, value: nil, table: nil) }
