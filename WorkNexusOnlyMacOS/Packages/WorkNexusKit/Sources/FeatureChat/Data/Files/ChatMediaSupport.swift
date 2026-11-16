import CoreDomain
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// MIME / image-size helpers for attachments.
/// Ported from: lib/features/chat/data/repositories/chat_attachment_loader.dart (top-level helpers), datasources/image_header_size.dart,
/// datasources/square_avatar_png.dart
enum ChatMedia {
    static func isImageMime(_ mime: String?) -> Bool {
        guard let mime else { return false }
        return mime.hasPrefix("image/") && mime != "image/svg+xml"
    }

    private static let mimeByExtension: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
        "bmp": "image/bmp", "heic": "image/heic", "mp4": "video/mp4", "mov": "video/quicktime", "webm": "video/webm",
        "mkv": "video/x-matroska", "mp3": "audio/mpeg", "wav": "audio/wav", "pdf": "application/pdf", "zip": "application/zip",
        "txt": "text/plain", "csv": "text/csv", "json": "application/json", "doc": "application/msword",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "xls": "application/vnd.ms-excel",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "ppt": "application/vnd.ms-powerpoint",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ]

    static func mimeType(forFileName name: String) -> String? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        return mimeByExtension[name[name.index(after: dot)...].lowercased()]
    }

    /// Pixel size of an image (ImageIO reads just the header).
    static func imageSize(_ data: Data) -> (width: Int, height: Int)? {
        guard data.count >= 24, let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { return nil }
        return (w, h)
    }

    /// The square of a picture (the chosen `crop`, else the centre) scaled to at most `maxSide` px, as PNG.
    static func squareAvatarPng(_ image: Data, crop: ChatAvatarCrop?, maxSide: Int = 256) -> Outcome<(png: Data, side: Int)> {
        guard let src = CGImageSourceCreateWithData(image as CFData, nil), let source = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return .failure(.unexpected("Unsupported picture"))
        }
        let w = Double(source.width), h = Double(source.height)
        let fit = min(w, h)
        // Kept inside the picture: a crop from a rounded zoom may overshoot a px.
        let cropSide = min(max(crop?.side ?? fit, 1), fit)
        let left = min(max(crop?.left ?? (w - cropSide) / 2, 0), w - cropSide)
        let top = min(max(crop?.top ?? (h - cropSide) / 2, 0), h - cropSide)
        let side = min(Int(cropSide.rounded()), maxSide)
        guard let piece = source.cropping(to: CGRect(x: left, y: top, width: cropSide, height: cropSide)),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return .failure(.unexpected("Unsupported picture"))
        }
        ctx.interpolationQuality = .high
        ctx.draw(piece, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let out = ctx.makeImage() else { return .failure(.unexpected("Unsupported picture")) }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return .failure(.unexpected("Unsupported picture")) }
        CGImageDestinationAddImage(dest, out, nil)
        guard CGImageDestinationFinalize(dest) else { return .failure(.unexpected("Unsupported picture")) }
        return .success((data as Data, side))
    }
}
