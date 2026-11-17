/// Not in the Flutter app: the picture on the media viewer's stage.
import AppKit
import SwiftUI

/// A still picture, or - given its `data` - one with frames (a GIF, an animated WebP) that plays, fitted to the stage with
/// the picture's proportions so zoom and rotation act on it alike.
struct ChatViewerPicture: View {
    let picture: NSImage
    /// The bytes of an animated picture; nil for a still one.
    let data: Data?

    var body: some View {
        if let data {
            FrameAnimatedImage(data: data, animated: true)
                .aspectRatio(picture.size.width > 0 && picture.size.height > 0 ? picture.size : CGSize(width: 1, height: 1), contentMode: .fit)
        } else {
            Image(nsImage: picture).resizable().scaledToFit()
        }
    }
}
