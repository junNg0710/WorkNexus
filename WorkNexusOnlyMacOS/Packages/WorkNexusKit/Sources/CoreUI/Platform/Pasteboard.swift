import AppKit
import UniformTypeIdentifiers

/// Ported from: lib/core/platform/image_clipboard.dart + features/chat/.../chat_attachments.dart (`readClipboardAttachments`)
public struct ClipboardAttachment: Sendable, Equatable {
    public var name: String
    public var data: Data
    public init(name: String, data: Data) { self.name = name; self.data = data }
}

/// Image / file helpers over `NSPasteboard` (injectable for tests).
public struct PasteboardKit {
    private let pasteboard: NSPasteboard
    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    /// Puts an image on the clipboard (PNG data; the pasteboard also offers TIFF for apps that want it).
    public func copyImage(_ data: Data) {
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        if let tiff = NSImage(data: data)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
    }

    /// The image on the clipboard as PNG, or nil when there is none.
    public func readImage() -> Data? {
        if let png = pasteboard.data(forType: .png), !png.isEmpty { return png }
        if let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }

    /// Paths of regular files copied on the clipboard (e.g. from Finder).
    public func readFilePaths() -> [String] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.map(\.path)
    }

    /// Files or an image on the clipboard, or nil when it only holds text (the caller then pastes text as usual). Copied
    /// files (e.g. from Finder) win over image data, which is what a screenshot puts on the clipboard.
    public func readAttachments(now: Date = Date()) -> [ClipboardAttachment]? {
        let paths = readFilePaths()
        if !paths.isEmpty {
            return paths.compactMap { path in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue,
                      let data = FileManager.default.contents(atPath: path) else { return nil }
                return ClipboardAttachment(name: (path as NSString).lastPathComponent, data: data)
            }
        }
        if let image = readImage(), !image.isEmpty {
            return [ClipboardAttachment(name: "pasted-\(Int(now.timeIntervalSince1970 * 1000)).png", data: image)]
        }
        return nil
    }
}

public func copyImageToClipboard(_ data: Data) { PasteboardKit().copyImage(data) }
public func readClipboardImage() -> Data? { PasteboardKit().readImage() }
public func readClipboardAttachments() -> [ClipboardAttachment]? { PasteboardKit().readAttachments() }
