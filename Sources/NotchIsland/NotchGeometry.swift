import AppKit

/// All sizes and rects for the island, in AppKit screen coordinates (origin bottom-left).
struct NotchGeometry: Equatable {
    /// Size of the island when expanded.
    static let openSize = CGSize(width: 480, height: 170)
    /// Largest top "flare" radius used by NotchShape. The panel is widened by this on each side.
    static let maxTopRadius: CGFloat = 14

    let screenFrame: NSRect
    /// The hardware notch, or a fake one on screens without a notch.
    let notchRect: NSRect
    let hasNotch: Bool

    var closedSize: CGSize { notchRect.size }

    /// Frame of the transparent panel. Big enough for the expanded island.
    var panelFrame: NSRect {
        let width = Self.openSize.width + Self.maxTopRadius * 2
        let height = Self.openSize.height
        return NSRect(x: notchRect.midX - width / 2,
                      y: screenFrame.maxY - height,
                      width: width,
                      height: height)
    }

    /// Mouse entering this area opens the island.
    var hoverRect: NSRect {
        NSRect(x: notchRect.minX - 12,
               y: notchRect.minY - 6,
               width: notchRect.width + 24,
               height: notchRect.height + 8)
    }

    /// Mouse leaving this area closes the island.
    var openRect: NSRect {
        let size = Self.openSize
        return NSRect(x: notchRect.midX - size.width / 2 - Self.maxTopRadius,
                      y: screenFrame.maxY - size.height,
                      width: size.width + Self.maxTopRadius * 2,
                      height: size.height + 2)
    }

    /// Picks the built-in notched screen if there is one, otherwise the main screen.
    static func current() -> NotchGeometry? {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched(screen)
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return fake(screen)
    }

    private static func notched(_ screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let height = screen.safeAreaInsets.top
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        let width = frame.width - leftWidth - rightWidth
        let rect = NSRect(x: frame.minX + leftWidth,
                          y: frame.maxY - height,
                          width: width,
                          height: height)
        return NotchGeometry(screenFrame: frame, notchRect: rect, hasNotch: true)
    }

    private static func fake(_ screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let menuBarHeight = max(frame.maxY - screen.visibleFrame.maxY, 24)
        let width: CGFloat = 190
        let rect = NSRect(x: frame.midX - width / 2,
                          y: frame.maxY - menuBarHeight,
                          width: width,
                          height: menuBarHeight)
        return NotchGeometry(screenFrame: frame, notchRect: rect, hasNotch: false)
    }
}
