import AppKit
import SwiftUI

/// Owns the panel, watches the mouse, and opens/closes the island.
@MainActor
final class NotchController {
    private let viewModel: NotchViewModel
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var closeWork: DispatchWorkItem?

    private static let closeDelay: TimeInterval = 0.3

    init() {
        let geometry = NotchGeometry.current() ?? NotchGeometry(
            screenFrame: .zero, notchRect: .zero, hasNotch: false)
        viewModel = NotchViewModel(geometry: geometry)
        panel = NotchPanel(frame: geometry.panelFrame)

        let hosting = NSHostingView(rootView: NotchView(vm: viewModel))
        hosting.frame = NSRect(origin: .zero, size: geometry.panelFrame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.orderFrontRegardless()

        startMouseMonitoring()
    }

    func reposition() {
        guard let geometry = NotchGeometry.current() else { return }
        viewModel.geometry = geometry
        panel.setFrame(geometry.panelFrame, display: true)
    }

    // MARK: - Mouse

    private func startMouseMonitoring() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        // Fires while another app is frontmost (the usual case).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouse() }
        }) {
            monitors.append(global)
        }

        // Fires while our own panel receives the events.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouse() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handleMouse() {
        let point = NSEvent.mouseLocation
        let geometry = viewModel.geometry

        if viewModel.isOpen {
            if geometry.openRect.contains(point) {
                cancelClose()
            } else {
                scheduleClose()
            }
        } else if geometry.hoverRect.contains(point) {
            open()
        }
    }

    private func open() {
        cancelClose()
        viewModel.refreshWidgets()
        viewModel.isOpen = true
        panel.ignoresMouseEvents = false
    }

    private func close() {
        viewModel.isOpen = false
        panel.ignoresMouseEvents = true
    }

    private func scheduleClose() {
        guard closeWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.closeWork = nil
                self?.close()
            }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDelay, execute: work)
    }

    private func cancelClose() {
        closeWork?.cancel()
        closeWork = nil
    }
}
