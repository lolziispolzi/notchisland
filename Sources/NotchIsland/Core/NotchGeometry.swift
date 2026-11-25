import AppKit

/// All sizes and rects for the island, in AppKit screen coordinates (origin bottom-left).
struct NotchGeometry: Equatable {
    /// Extra height added while the customize bar is showing.
    static let editBarHeight: CGFloat = 84
    /// Largest possible open island. The panel is sized for this so it never needs resizing.
    static var maxOpenSize: CGSize {
        let large = IslandSize.large.openSize
        return CGSize(width: large.width, height: large.height + editBarHeight)
    }
    /// Largest top "ear" radius used by NotchShape. The panel is widened by this on each side.
    static let maxTopRadius: CGFloat = 14
    /// Used before any screen is known.
    static let placeholder = NotchGeometry(
        screenFrame: .zero,
        notchRect: NSRect(x: 0, y: 0, width: 190, height: 32),
        hasNotch: false
    )

    let screenFrame: NSRect
    /// The hardware notch, or a fake one on screens without a notch.
    let notchRect: NSRect
    let hasNotch: Bool

    /// Frame of the transparent panel. Big enough for the largest expanded island.
    var panelFrame: NSRect {
        let width = Self.maxOpenSize.width + Self.maxTopRadius * 2
        let height = Self.maxOpenSize.height
        return NSRect(x: notchRect.midX - width / 2,
                      y: screenFrame.maxY - height,
                      width: width,
                      height: height)
    }

    /// Mouse entering this area opens the island. `closedSize` is the size of the
    /// closed island, which grows for live activities; it defaults to the notch.
    func hoverRect(closedSize: CGSize? = nil) -> NSRect {
        let size = closedSize ?? notchRect.size
        return NSRect(x: notchRect.midX - size.width / 2 - 12,
                      y: screenFrame.maxY - size.height - 6,
                      width: size.width + 24,
                      height: size.height + 8)
    }

    /// Mouse leaving this area closes the island.
    func openRect(size: CGSize) -> NSRect {
        NSRect(x: notchRect.midX - size.width / 2 - Self.maxTopRadius,
               y: screenFrame.maxY - size.height,
               width: size.width + Self.maxTopRadius * 2,
               height: size.height + 2)
    }

    // MARK: - Factories

    static func current(for choice: DisplayChoice) -> NotchGeometry? {
        let screens = NSScreen.screens
        switch choice {
        case .notchScreen:
            if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                return make(for: notched)
            }
            return screens.first.map(make(for:))
        case .primaryScreen:
            return screens.first.map(make(for:))
        }
    }

    static func make(for screen: NSScreen) -> NotchGeometry {
        if screen.safeAreaInsets.top > 0 {
            return notched(screenFrame: screen.frame,
                           notchHeight: screen.safeAreaInsets.top,
                           leftAreaWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
                           rightAreaWidth: screen.auxiliaryTopRightArea?.width ?? 0)
        }
        return fake(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    static func notched(screenFrame frame: NSRect,
                        notchHeight: CGFloat,
                        leftAreaWidth: CGFloat,
                        rightAreaWidth: CGFloat) -> NotchGeometry {
        let width = frame.width - leftAreaWidth - rightAreaWidth
        let rect = NSRect(x: frame.minX + leftAreaWidth,
                          y: frame.maxY - notchHeight,
                          width: width,
                          height: notchHeight)
        return NotchGeometry(screenFrame: frame, notchRect: rect, hasNotch: true)
    }

    static func fake(screenFrame frame: NSRect, visibleFrame: NSRect) -> NotchGeometry {
        let menuBarHeight = max(frame.maxY - visibleFrame.maxY, 24)
        let width: CGFloat = 190
        let rect = NSRect(x: frame.midX - width / 2,
                          y: frame.maxY - menuBarHeight,
                          width: width,
                          height: menuBarHeight)
        return NotchGeometry(screenFrame: frame, notchRect: rect, hasNotch: false)
    }
}
