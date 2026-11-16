import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Ported from: lib/core/platform/app_icon_service.dart + app_icon_image.dart
/// The app's own icon, which the user can replace with a picture of theirs: the Dock/app-switcher icon
/// (`NSApp.applicationIconImage`) and, through `onApply`, the tray's. The one kept — a 256 px square PNG — lives in the
/// app's support folder, so the original can be moved or deleted.
@MainActor
public final class AppIconService {
    /// The side of the icon kept on disk.
    public nonisolated static let side = 256
    private static let prefix = "custom-"

    private let folder: URL
    private let apply: @MainActor (NSImage?) -> Void

    /// - Parameter onApply: also hands the icon in use (nil = the app's own) to the tray.
    public init(folder: URL = PlatformPaths.applicationSupport().appendingPathComponent("app_icon", isDirectory: true),
                onApply: @escaping @MainActor (NSImage?) -> Void = { _ in }) {
        self.folder = folder; self.apply = onApply
    }

    /// The picture in use, or nil while the app has its own icon.
    public func current() -> URL? {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return entries.first { $0.lastPathComponent.hasPrefix(Self.prefix) && $0.pathExtension == "png" }
    }

    /// Makes the image at `source` the app's icon. False when it is not an image or cannot be read or kept (nothing
    /// changes then, or the app is left with its own icon).
    @discardableResult
    public func choose(_ source: URL) -> Bool {
        guard let data = try? Data(contentsOf: source), let png = Self.squarePNG(data) else { return false }
        do {
            clear()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            try png.write(to: folder.appendingPathComponent("\(Self.prefix)\(stamp).png"), options: .atomic)
        } catch {
            reapply()
            return false
        }
        reapply()
        return true
    }

    /// Gives the app its own icon back.
    public func reset() { clear(); reapply() }

    /// Puts the icon in use (the app's own when there is none) on the Dock and the tray. Cosmetic: never an error.
    public func reapply() {
        let image = current().flatMap { NSImage(contentsOf: $0) }
        // nil restores the icon from the bundle.
        NSApp?.applicationIconImage = image
        apply(image)
    }

    private func clear() {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for e in entries where e.lastPathComponent.hasPrefix(Self.prefix) { try? FileManager.default.removeItem(at: e) }
    }

    // MARK: image handling

    /// `data` (any image ImageIO knows; of an icon file, the largest picture) cropped to a square around its centre and
    /// scaled to `side` pixels, as PNG; nil when it is not an image.
    nonisolated static func squarePNG(_ data: Data, side: Int = AppIconService.side) -> Data? {
        guard let image = largestImage(data), image.width > 0, image.height > 0 else { return nil }
        let crop = min(image.width, image.height)
        let rect = CGRect(x: (image.width - crop) / 2, y: (image.height - crop) / 2, width: crop, height: crop)
        guard let square = image.cropping(to: rect),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }

    /// An icon file holds one image per size; a plain decode would take the first (often 16 px), so pick the largest.
    private nonisolated static func largestImage(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var best: CGImage?
        for i in 0..<CGImageSourceGetCount(src) {
            guard let frame = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            if best == nil || frame.width > best!.width { best = frame }
        }
        return best
    }
}
