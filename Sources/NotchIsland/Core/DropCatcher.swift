import AppKit

/// A small, invisible window over the camera notch that accepts dragged files.
///
/// While the island is closed its panel lets every event pass through, and macOS
/// doesn't report another app's drag to our mouse monitors, so the island had no way
/// to notice a file being dragged to it. This window is always there: when a drag
/// reaches the notch it opens the island on the Drop Zone, and a drop right on the
/// notch adds the files too. It only covers the notch itself, where there are no
/// menus, so it never gets in the way of clicks.
final class DropCatcherWindow: NSPanel {
    let catcher = DropCatcherView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        // Just above the island panel, so a drag over the notch finds this first.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = catcher
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class DropCatcherView: NSView {
    /// A file drag reached the notch.
    var onDragEnter: (() -> Void)?
    /// Files were dropped on the notch.
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        // Nearly transparent rather than fully clear: macOS skips fully transparent
        // pixels when it looks for a drop target. Over the black notch it can't be seen.
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.02).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true])
        return (objects as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !Self.fileURLs(from: sender.draggingPasteboard).isEmpty else { return [] }
        onDragEnter?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}
