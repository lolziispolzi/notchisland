import AppKit
import Combine
import SwiftUI

// Back-ports that let NotchIsland run on macOS 10.15 Catalina and newer.
// Each one uses the system API where it exists and a simple stand-in on older
// systems, so the app looks and behaves the same on current macOS.

// MARK: - Symbols

/// SF Symbols arrived in macOS 11. On 10.15 a matching text glyph stands in.
struct SymbolImage: View {
    let name: String
    var multicolor = false

    init(_ name: String, multicolor: Bool = false) {
        self.name = name
        self.multicolor = multicolor
    }

    var body: some View {
        if #available(macOS 12, *), multicolor {
            Image(systemName: name).symbolRenderingMode(.multicolor)
        } else if #available(macOS 11, *) {
            Image(systemName: name)
        } else {
            Text(SymbolGlyphs.glyph(for: name))
        }
    }
}

/// An icon and a title, like `Label`, which arrived in macOS 11.
struct SymbolLabel: View {
    let title: String
    let symbol: String

    init(_ title: String, systemImage: String) {
        self.title = title
        symbol = systemImage
    }

    var body: some View {
        if #available(macOS 11, *) {
            Label(title, systemImage: symbol)
        } else {
            HStack(spacing: 4) {
                SymbolImage(symbol)
                Text(title)
            }
        }
    }
}

enum SymbolGlyphs {
    /// Text stand-ins for the SF Symbols the app uses, for macOS 10.15.
    static func glyph(for name: String) -> String {
        if let glyph = table[name] { return glyph }
        if name.hasPrefix("battery") { return name.contains("bolt") ? "⚡︎" : "▭" }
        if name.hasPrefix("cloud") { return "☁︎" }
        return "•"
    }

    private static let table: [String: String] = [
        "arrow.down.circle": "⬇︎", "backward.fill": "⏮︎", "forward.fill": "⏭︎",
        "play.fill": "▶︎", "pause.fill": "⏸︎", "shuffle": "⤮", "repeat": "↻",
        "baseball.fill": "⚾︎", "basketball.fill": "●", "football.fill": "⬮",
        "hockey.puck.fill": "▬", "sportscourt": "▦", "sportscourt.fill": "▦",
        "bolt.fill": "⚡︎", "calendar": "▦", "calendar.badge.exclamationmark": "▦",
        "capsule.fill": "⬬", "checkmark": "✓", "chevron.down": "⌄", "chevron.up": "⌃",
        "chevron.left": "‹", "chevron.right": "›", "doc.on.clipboard": "⎘",
        "dot.radiowaves.left.and.right": "◉", "exclamationmark.icloud": "⚠︎",
        "folder": "▰", "folder.badge.plus": "+", "gearshape": "⚙︎", "gearshape.fill": "⚙︎",
        "key.fill": "⚿", "location.fill": "➤", "location.slash": "⊘", "lock.display": "⚿",
        "menubar.dock.rectangle": "▭", "minus.circle": "⊖", "moon.stars.fill": "☾",
        "music.note": "♪", "note.text": "✎", "pin.fill": "📌︎", "plus": "+",
        "quote.bubble": "❝", "quote.bubble.fill": "❝", "rectangle.3.group": "▤",
        "slider.horizontal.3": "☰", "sparkle": "✦", "sparkles": "✦", "sparkles.tv": "✦",
        "square.and.arrow.up": "⇪", "sun.max.fill": "☀︎", "trash": "✕",
        "tray.and.arrow.down": "⬇︎", "tray.and.arrow.down.fill": "⬇︎",
        "cloud.sun": "⛅︎", "cloud.sun.fill": "⛅︎", "cloud.moon.fill": "☁︎",
        "cloud.bolt.rain.fill": "⛈︎", "cloud.snow.fill": "❄︎", "cloud.fog.fill": "≋",
    ]
}

extension NSImage {
    /// An SF Symbol on macOS 11 and newer; nil on 10.15.
    static func symbol(_ name: String, description: String? = nil) -> NSImage? {
        if #available(macOS 11, *) {
            return NSImage(systemSymbolName: name, accessibilityDescription: description)
        }
        return nil
    }
}

// MARK: - Modifiers

extension View {
    /// Tooltip (macOS 11 and newer).
    @ViewBuilder
    func compatHelp(_ text: String) -> some View {
        if #available(macOS 11, *) {
            help(text)
        } else {
            self
        }
    }

    /// Fixed-width digits (macOS 12 and newer).
    @ViewBuilder
    func compatMonospacedDigit() -> some View {
        if #available(macOS 12, *) {
            monospacedDigit()
        } else {
            self
        }
    }

    /// Selectable text (macOS 12 and newer).
    @ViewBuilder
    func compatTextSelection() -> some View {
        if #available(macOS 12, *) {
            textSelection(.enabled)
        } else {
            self
        }
    }

    /// Dark appearance for the view and the window that hosts it.
    @ViewBuilder
    func compatDarkScheme() -> some View {
        if #available(macOS 11, *) {
            preferredColorScheme(.dark)
        } else {
            environment(\.colorScheme, .dark)
        }
    }

    /// Grouped settings form (macOS 13 and newer).
    @ViewBuilder
    func compatGroupedForm() -> some View {
        if #available(macOS 13, *) {
            formStyle(.grouped)
        } else {
            padding(16)
        }
    }

    /// Hides a scroll view's background (macOS 13 and newer).
    @ViewBuilder
    func compatHideScrollBackground() -> some View {
        if #available(macOS 13, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    /// Turns off scrolling (macOS 13 and newer).
    @ViewBuilder
    func compatScrollDisabled(_ disabled: Bool) -> some View {
        if #available(macOS 13, *) {
            scrollDisabled(disabled)
        } else {
            self
        }
    }

    /// Rolls changing numbers (macOS 13 and newer).
    @ViewBuilder
    func compatNumericTransition() -> some View {
        if #available(macOS 13, *) {
            contentTransition(.numericText())
        } else {
            self
        }
    }

    /// Return key triggers this button (macOS 11 and newer).
    @ViewBuilder
    func compatDefaultAction() -> some View {
        if #available(macOS 11, *) {
            keyboardShortcut(.defaultAction)
        } else {
            self
        }
    }

    /// Escape key triggers this button (macOS 11 and newer).
    @ViewBuilder
    func compatCancelAction() -> some View {
        if #available(macOS 11, *) {
            keyboardShortcut(.cancelAction)
        } else {
            self
        }
    }

    /// Calls `action` when `value` changes, like `onChange(of:)` (macOS 11).
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 11, *) {
            onChange(of: value, perform: action)
        } else {
            modifier(ChangeObserver(value: value, action: action))
        }
    }
}

private struct ChangeObserver<V: Equatable>: ViewModifier {
    let value: V
    let action: (V) -> Void
    @State private var last: V?

    func body(content: Content) -> some View {
        content
            .onAppear { last = value }
            .onReceive(Just(value)) { new in
                guard let old = last, old != new else { return }
                last = new
                action(new)
            }
    }
}

// MARK: - Views

/// A row with a title on the left and content on the right, like `LabeledContent` (macOS 13).
struct LabeledRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            content
        }
    }
}

extension LabeledRow where Content == Text {
    init(_ title: String, value: String) {
        self.init(title) { Text(value) }
    }
}

/// A small spinning progress indicator, like `ProgressView()` (macOS 11).
/// Its size follows `.controlSize(_:)`.
struct Spinner: NSViewRepresentable {
    @Environment(\.controlSize) private var size

    private var nsControlSize: NSControl.ControlSize {
        switch size {
        case .mini: return .mini
        case .small: return .small
        default: return .regular
        }
    }

    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.isIndeterminate = true
        indicator.controlSize = nsControlSize
        indicator.startAnimation(nil)
        return indicator
    }

    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {
        nsView.controlSize = nsControlSize
    }
}

/// Passed to a `Ticker`'s content, like `TimelineView.Context`.
struct TickContext {
    let date: Date
}

/// Redraws its content on a fixed interval, like `TimelineView(.periodic)` (macOS 12).
/// The timer only runs while the view is on screen.
struct Ticker<Content: View>: View {
    let interval: TimeInterval
    var paused = false
    let content: (TickContext) -> Content

    @State private var date = Date()
    @State private var timer: Timer?

    init(every interval: TimeInterval, paused: Bool = false, @ViewBuilder content: @escaping (TickContext) -> Content) {
        self.interval = interval
        self.paused = paused
        self.content = content
    }

    var body: some View {
        content(TickContext(date: date))
            .onAppear(perform: start)
            .onDisappear(perform: stop)
            .onChangeCompat(of: paused) { _ in start() }
    }

    private func start() {
        stop()
        date = Date()
        guard !paused else { return }
        let binding = $date
        let timer = Timer(timeInterval: interval, repeats: true) { _ in binding.wrappedValue = Date() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// A frosted background, like the `.ultraThinMaterial` style (macOS 12).
struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Multi-line text editing, like `TextEditor` (macOS 11), on every version.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var textColor: NSColor = .white
    /// Increase to move keyboard focus into the editor.
    var focusRequest = 0
    /// Called when the editor gains or loses keyboard focus.
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FocusReportingTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.delegate = context.coordinator
        textView.onFocusChange = { focused in context.coordinator.parent.onFocusChange(focused) }
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 4)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = textColor
        if focusRequest != context.coordinator.handledFocusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        var handledFocusRequest: Int

        init(_ parent: PlainTextEditor) {
            self.parent = parent
            handledFocusRequest = parent.focusRequest
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private final class FocusReportingTextView: NSTextView {
    var onFocusChange: (Bool) -> Void = { _ in }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange(false) }
        return accepted
    }
}

/// Loads and shows an image from the web, like `AsyncImage` (macOS 12).
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    let placeholder: Placeholder

    @State private var image: NSImage?
    @State private var loadedURL: URL?

    init(url: URL?, contentMode: ContentMode = .fill, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image, loadedURL == url {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .onAppear(perform: load)
        .onChangeCompat(of: url) { _ in load() }
    }

    private func load() {
        guard let url, loadedURL != url else { return }
        let target = url
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let loaded = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async {
                guard url == target else { return }
                image = loaded
                loadedURL = target
            }
        }.resume()
    }
}

// MARK: - Dates

enum DateText {
    private static var cache: [String: DateFormatter] = [:]

    /// Formats with a localized template, e.g. "jmm" for a time or "EEEE MMM d".
    static func string(_ date: Date, template: String) -> String {
        let formatter: DateFormatter
        if let cached = cache[template] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate(template)
            cache[template] = formatter
        }
        return formatter.string(from: date)
    }

    /// Formats with a date and time style, like `Date.formatted(date:time:)`.
    static func string(_ date: Date, date dateStyle: DateFormatter.Style, time timeStyle: DateFormatter.Style) -> String {
        DateFormatter.localizedString(from: date, dateStyle: dateStyle, timeStyle: timeStyle)
    }
}

// MARK: - AppKit

extension NSApplication {
    /// Brings the app forward. `activate()` replaced the older call in macOS 14.
    func activateCompat() {
        if #available(macOS 14, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}

extension NSScreen {
    /// Height of the camera housing, or 0 (screens without a notch, or before macOS 12).
    var notchHeight: CGFloat {
        if #available(macOS 12, *) {
            return safeAreaInsets.top
        }
        return 0
    }

    /// Widths of the menu-bar areas left and right of the notch (macOS 12 and newer).
    var notchSideWidths: (left: CGFloat, right: CGFloat) {
        if #available(macOS 12, *) {
            return (auxiliaryTopLeftArea?.width ?? 0, auxiliaryTopRightArea?.width ?? 0)
        }
        return (0, 0)
    }
}

extension Color {
    /// `Color.cyan` arrived in macOS 12.
    static let compatCyan = Color(red: 0.35, green: 0.78, blue: 0.98)
}

// MARK: - Networking

extension URLSession {
    /// `data(from:)` arrived in macOS 12.
    func compatData(from url: URL) async throws -> (Data, URLResponse) {
        try await compatData(for: URLRequest(url: url))
    }

    /// `data(for:)` arrived in macOS 12.
    func compatData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            dataTask(with: request) { data, response, error in
                if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }.resume()
        }
    }
}

/// Items laid out in rows of a fixed number of equal columns, like `LazyVGrid` (macOS 11).
struct SimpleGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let columns: Int
    var spacing: CGFloat = 12
    let cell: (Item) -> Cell

    init(items: [Item], columns: Int, spacing: CGFloat = 12, @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.items = items
        self.columns = max(columns, 1)
        self.spacing = spacing
        self.cell = cell
    }

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(rows[index]) { item in
                        cell(item).frame(maxWidth: .infinity)
                    }
                    // Keep the last row's cells the same width as the others.
                    ForEach(0..<(columns - rows[index].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }
}

extension AnyTransition {
    /// New content slides up from the bottom, like `.push(from: .bottom)` (macOS 13).
    static var pushFromBottom: AnyTransition {
        .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity))
    }
}
