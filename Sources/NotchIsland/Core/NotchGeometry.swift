import AppKit

/// All sizes and rects for the island, in AppKit screen coordinates (origin bottom-left).
struct NotchGeometry: Equatable {
    /// Size of the island when expanded.
    static let openSize = CGSize(width: 560, height: 190)
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
    /// `extraWidth` is how much wider a closed live activity makes the island.
    func hoverRect(extraWidth: CGFloat = 0) -> NSRect {
        NSRect(x: notchRect.minX - extraWidth / 2 - 12,
               y: notchRect.minY - 6,
               width: notchRect.width + extraWidth + 24,
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
