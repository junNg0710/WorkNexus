import AppKit
import SwiftUI

/// Ported from: lib/core/widgets/inline_image.dart (typedefs)
/// Loads the bytes for an inline image URL (e.g. via an authenticated client).
public typealias ImageBytesLoader = @Sendable (String) async -> Data?
/// Resolves an inline image URL to an absolute link that can be copied or opened in a browser, or nil.
public typealias ImageUrlResolver = @Sendable (String) -> String?
/// Opens an already-resolved image URL externally (in a browser).
public typealias ImageExternalOpener = @Sendable (String) async -> Void

public extension AppTypography {
    /// A font at an arbitrary size in the user's chosen family (used where body text scales, e.g. rendered bodies).
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        family.isEmpty ? .system(size: size, weight: weight) : .custom(family, size: size).weight(weight)
    }
}

/// Asks the host to show an image enlarged at window level (so it covers the whole app). When no presenter is
/// installed, `InlineImage` shows the viewer in a sheet of its own.
public struct ImageViewerRequest: Identifiable {
    public let id = UUID()
    public var data: Data
    public var externalUrl: String?
    public var onOpenExternally: ImageExternalOpener?
}

private struct ImageViewerPresenterKey: EnvironmentKey { static let defaultValue: ((ImageViewerRequest) -> Void)? = nil }
public extension EnvironmentValues {
    var imageViewerPresenter: ((ImageViewerRequest) -> Void)? {
        get { self[ImageViewerPresenterKey.self] }
        set { self[ImageViewerPresenterKey.self] = newValue }
    }
}
