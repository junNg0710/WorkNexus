import Foundation

/// Ported from: lib/core/domain/value_objects/media_request.dart
public struct MediaRequest: Sendable, Equatable {
    public var url: URL
    public var headers: [String: String]
    /// The kind of file behind `url` ("mp4"), for an address that does not say: ZenTao serves an attachment from a path
    /// without an extension and with no content type, which a player cannot open unless it is told what it is.
    public var fileExtension: String?
    public init(url: URL, headers: [String: String] = [:], fileExtension: String? = nil) {
        self.url = url; self.headers = headers; self.fileExtension = fileExtension
    }
}
