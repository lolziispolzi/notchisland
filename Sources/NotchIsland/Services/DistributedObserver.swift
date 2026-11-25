import Foundation

/// Listens for a system-wide (distributed) notification and always delivers it at once.
///
/// AppKit can hold back distributed notifications for apps that are not active.
/// NotchIsland is never the active app, so block-based observers could miss events
/// such as "screen locked" or "track changed". `.deliverImmediately` prevents that.
final class DistributedObserver: NSObject {
    private let handler: (Notification) -> Void

    init(_ name: String, handler: @escaping (Notification) -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(self,
                                                            selector: #selector(receive(_:)),
                                                            name: Notification.Name(name),
                                                            object: nil,
                                                            suspensionBehavior: .deliverImmediately)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func receive(_ notification: Notification) {
        // Distributed notifications arrive on the main thread.
        handler(notification)
    }
}
