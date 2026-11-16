import Foundation

/// Ported from: lib/core/domain/value_objects/media_request.dart
public struct MediaRequest: Sendable, Equatable {
    public var url: URL
    public var headers: [String: String]
    public init(url: URL, headers: [String: String] = [:]) { self.url = url; self.headers = headers }
}
