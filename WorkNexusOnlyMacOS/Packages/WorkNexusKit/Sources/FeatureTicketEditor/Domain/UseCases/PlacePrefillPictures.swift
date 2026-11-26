/// Not in the Flutter app.
import CoreTools
import Foundation

/// Puts the pictures a new ticket was opened with (the ones of the chat messages it quotes) into its body: each is
/// uploaded under the form's own upload id - ZenTao drops an upload no saved form claims - and its token in the HTML
/// becomes the `<img>` the upload answers with. A picture that could not be uploaded stays named in words.
public struct PlacePrefillPictures: Sendable {
    public init() {}

    /// - Parameter upload: uploads one picture (bytes, file name); the URL to embed it at, or nil.
    public func callAsFunction(_ prefill: TicketEditorPrefill, upload: (Data, String) async -> String?) async -> String {
        var html = prefill.bodyHtml
        for picture in prefill.pictures where html.contains(picture.token) {
            let placed: String
            if let url = await upload(picture.data, picture.name) {
                placed = "<img src=\"\(Self.escaped(url))\" />"
            } else {
                placed = Self.escaped(picture.name)
            }
            html = html.replacingOccurrences(of: picture.token, with: placed)
        }
        return html
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
