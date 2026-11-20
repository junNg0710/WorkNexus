import AppKit

/// Not in the Flutter app.
/// An `NSImageView` that only shows: it never registers for drags. A plain one does, and over a chat it took a dragged file
/// (or would have swapped its picture for a dropped one) before the chat's own drop areas underneath could.
public final class NoDropImageView: NSImageView {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        unregisterDraggedTypes()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        unregisterDraggedTypes()
    }

    public override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {}
}
