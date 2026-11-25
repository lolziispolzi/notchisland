import AppKit
import Combine
import SwiftUI

/// Owns the panel, watches the mouse, and opens/closes the island.
@MainActor
final class NotchController {
    private let vm: NotchViewModel
    private let settings: AppSettings
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private static let closeDelay: TimeInterval = 0.3

    init(viewModel: NotchViewModel, settings: AppSettings) {
        vm = viewModel
        self.settings = settings
        panel = NotchPanel(frame: viewModel.geometry.panelFrame)

        let root = NotchView(vm: viewModel, settings: settings)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: viewModel.geometry.panelFrame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        // Set the frame again now that constraining is off, then show it.
        panel.setFrame(viewModel.geometry.panelFrame, display: false)
        panel.orderFrontRegardless()

        startMouseMonitoring()

        settings.$displayChoice
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        // Let the panel take the keyboard only while a text field needs it.
        viewModel.$wantsKeyboard
            .removeDuplicates()
            .sink { [weak self] wants in self?.setKeyboardEnabled(wants) }
            .store(in: &cancellables)
    }

    private func setKeyboardEnabled(_ enabled: Bool) {
        panel.allowsKey = enabled
        if enabled {
            panel.makeKeyAndOrderFront(nil)
        } else if panel.isKeyWindow {
            panel.resignKey()
        }
    }

    func reposition() {
        guard let geometry = NotchGeometry.current(for: settings.displayChoice) else { return }
        vm.geometry = geometry
        panel.setFrame(geometry.panelFrame, display: true)
    }

    // MARK: - Mouse

    private func startMouseMonitoring() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]

        // Fires while another app is frontmost (the usual case).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }

        // Fires while our own panel receives the events.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        let geometry = vm.geometry

        // Clicking into the Notes tab: take the keyboard before the click lands,
        // so the text editor gets focus and typing goes to the note.
        if vm.isOpen, event.type == .leftMouseDown, event.window === panel, vm.tab == .notes {
            setKeyboardEnabled(true)
        }

        if vm.isOpen {
            // Typing in the island: stay open until the form is done.
            if vm.wantsKeyboard {
                cancelClose()
                return
            }
            // Keep it open while a button is held, so dragging a file out of the shelf works.
            let buttonHeld = event.type != .leftMouseUp && NSEvent.pressedMouseButtons != 0
            if geometry.openRect(size: vm.openSize).contains(point) || buttonHeld {
                cancelClose()
            } else {
                scheduleClose()
            }
            return
        }

        let inside = geometry.hoverRect(extraWidth: vm.closedExtraWidth).contains(point)
        switch event.type {
        case .leftMouseDragged:
            if inside, settings.isVisible(.drop), Self.dragHasFiles() {
                open(tab: .drop)
            }
        case .leftMouseDown:
            if inside, !settings.openOnHover {
                open()
            }
        case .mouseMoved:
            guard settings.openOnHover else { return }
            if inside { scheduleOpen() } else { cancelOpen() }
        default:
            break
        }
    }

    private static func dragHasFiles() -> Bool {
        (NSPasteboard(name: .drag).types ?? []).contains(.fileURL)
    }

    // MARK: - Open / close

    private func open(tab: WidgetKind? = nil) {
        cancelOpen()
        cancelClose()
        if let tab { vm.tab = tab }
        guard !vm.isOpen else { return }

        vm.willOpen()
        vm.isOpen = true
        panel.ignoresMouseEvents = false

        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func close() {
        vm.isOpen = false
        vm.didClose()
        setKeyboardEnabled(false)
        panel.ignoresMouseEvents = true
    }

    private func scheduleOpen() {
        guard openWork == nil else { return }
        let delay = settings.hoverDelay
        guard delay > 0 else {
            open()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.openWork = nil
                self?.open()
            }
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelOpen() {
        openWork?.cancel()
        openWork = nil
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

/// The island's window is never the active window, so by default macOS swallows
/// the first click on it (normally used to bring a window forward). Accepting the
/// first click makes every button in the island work on a single click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
