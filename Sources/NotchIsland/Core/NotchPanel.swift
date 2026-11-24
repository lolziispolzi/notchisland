import AppKit

/// Borderless, transparent panel that floats above the menu bar on every Space.
final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Closed by default: let clicks fall through to whatever is underneath.
        ignoresMouseEvents = true
    }

    /// Only true while a text field in the island needs typing (e.g. adding an event).
    var allowsKey = false

    // Otherwise never steal keyboard focus from the user's app.
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
