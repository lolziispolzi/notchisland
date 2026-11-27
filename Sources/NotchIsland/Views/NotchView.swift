import SwiftUI

/// Root view. Draws the black island and switches between closed, live-activity and open states.
struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings

    private var activity: ClosedActivity { vm.isOpen ? .none : vm.closedActivity }
    private var topRadius: CGFloat { vm.isOpen ? NotchGeometry.maxTopRadius : 6 }
    private var bottomRadius: CGFloat { vm.isOpen ? 32 : 10 }

    private var size: CGSize {
        vm.isOpen ? vm.openSize : vm.closedSize
    }

    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)

    /// Coordinate space of the whole panel, used to report header button frames.
    static let space = "island"

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(Color.black)
                .overlay(Group {
                    // Closed, the island stays pure black to match the camera notch.
                    if vm.isOpen, settings.glossyIsland {
                        IslandGloss(topRadius: topRadius,
                                    bottomRadius: bottomRadius,
                                    notchHeight: vm.geometry.notchRect.height,
                                    tint: vm.nowPlaying.isPlaying ? vm.nowPlaying.accentColor : nil)
                            .transition(.opacity)
                    }
                })
                .frame(width: size.width + topRadius * 2, height: size.height)

            if vm.isOpen {
                OpenView(vm: vm, settings: settings)
                    .frame(width: size.width + topRadius * 2, height: size.height, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            } else if activity != .none {
                ClosedActivityView(activity: activity, vm: vm)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .edgesIgnoringSafeArea(.all)
        .coordinateSpace(name: NotchView.space)
        .onDrop(of: ["public.file-url"], isTargeted: $vm.isDropTargeted) { providers in
            guard settings.isVisible(.drop) else { return false }
            vm.shelf.add(providers)
            vm.tab = .drop
            return true
        }
        .animation(spring, value: vm.isOpen)
        .animation(spring, value: activity)
        .animation(spring, value: vm.isEditing)
        .animation(spring, value: vm.showsClosedLyrics)
        .animation(spring, value: settings.islandSize)
        .compatDarkScheme()
    }
}

/// Contents of the expanded island: header bar, the selected widget, and the customize bar.
struct OpenView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 10) {
            HeaderBar(vm: vm, settings: settings)
                .frame(height: vm.geometry.notchRect.height)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if vm.isEditing {
                CustomizeBar(vm: vm, settings: settings)
                    .frame(height: NotchGeometry.editBarHeight - 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, NotchGeometry.maxTopRadius + 18)
        .padding(.bottom, 16)
        .foregroundColor(.white)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.tab {
        case .media: MediaView(vm: vm)
        case .weather: WeatherView(vm: vm)
        case .calendar: CalendarView(vm: vm, settings: settings)
        case .sports: SportsView(vm: vm)
        case .drop: DropView(vm: vm)
        case .notes: NotesView(vm: vm, notes: vm.notes)
        }
    }
}

/// Row beside the notch: widget tabs on the left; battery, customize and settings on the right.
struct HeaderBar: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 1) {
                ForEach(settings.visibleWidgets) { widget in
                    HeaderButton(symbol: widget.symbol, isSelected: vm.tab == widget, help: widget.title) {
                        vm.tab = widget
                    }
                    .headerTarget("tab.\(widget.rawValue)")
                }
            }

            Spacer(minLength: vm.geometry.notchRect.width + 12)

            HStack(spacing: 6) {
                if settings.showBattery, let info = vm.battery.info {
                    BatteryBadge(info: info)
                        .padding(.trailing, 2)
                }
                HeaderButton(symbol: "slider.horizontal.3", isSelected: vm.isEditing, help: "Customize") {
                    vm.isEditing.toggle()
                }
                .headerTarget("customize")
                HeaderButton(symbol: "gearshape.fill", isSelected: false, help: "Settings") {
                    vm.openSettings()
                }
                .headerTarget("settings")
            }
        }
        .onPreferenceChange(HeaderTargetsKey.self) { targets in
            MainActor.assumeIsolated { vm.headerTargets = targets }
        }
    }
}

/// Collects header button frames so the controller can hit-test clicks.
struct HeaderTargetsKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's frame as a clickable header target.
    func headerTarget(_ id: String) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(key: HeaderTargetsKey.self,
                                       value: [id: geometry.frame(in: .named(NotchView.space))])
            }
        )
    }
}

struct HeaderButton: View {
    let symbol: String
    let isSelected: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SymbolImage(symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 22)
                .background(Capsule().fill(Color.white.opacity(isSelected ? 0.18 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .compatHelp(help)
    }
}

/// Now playing on the left, clock on the right.
struct MediaView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        if vm.mediaShowsLyrics, vm.nowPlaying.track != nil {
            HStack(alignment: .center, spacing: 16) {
                CompactPlayer(nowPlaying: vm.nowPlaying) { vm.mediaShowsLyrics = false }
                    .frame(width: 140, alignment: .leading)
                LyricsLinesView(nowPlaying: vm.nowPlaying, lyrics: vm.lyrics, fontSize: 15)
            }
        } else {
            HStack(alignment: .center, spacing: 16) {
                NowPlayingView(nowPlaying: vm.nowPlaying,
                               showsLyricsButton: vm.settings.lyricsEnabled,
                               onShowLyrics: { vm.mediaShowsLyrics = true })
                Spacer(minLength: 0)
                ClockView()
            }
        }
    }
}

/// Centered icon, title and message, with an optional button. Used for empty and error states.
struct WidgetMessage: View {
    let symbol: String
    let title: String
    var message: String?
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            SymbolImage(symbol)
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.5))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.25 : 0.15)))
            .contentShape(Capsule())
    }
}

/// Glossy finish for the open island: a soft sheen under the header row, a diagonal
/// highlight, a bright lower rim and, while music plays, a faint reflection of the
/// album's color. The strip beside the notch stays black so the island still grows
/// out of the camera housing.
struct IslandGloss: View {
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let notchHeight: CGFloat
    let tint: Color?

    var body: some View {
        GeometryReader { geometry in
            let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
            let headerEnd = min(0.4, (notchHeight + 4) / max(geometry.size.height, 1))
            ZStack {
                shape.fill(LinearGradient(gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: headerEnd),
                    .init(color: .white.opacity(0.09), location: headerEnd + 0.04),
                    .init(color: .white.opacity(0.02), location: 0.55),
                    .init(color: .clear, location: 0.7),
                ]), startPoint: .top, endPoint: .bottom))

                shape.fill(LinearGradient(gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: .white.opacity(0.06), location: 0.42),
                    .init(color: .clear, location: 0.54),
                ]), startPoint: .topLeading, endPoint: .bottomTrailing))

                if let tint {
                    shape.fill(RadialGradient(gradient: Gradient(colors: [tint.opacity(0.16), .clear]),
                                              center: .bottom,
                                              startRadius: 0,
                                              endRadius: geometry.size.width * 0.45))
                }

                shape.stroke(LinearGradient(gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: headerEnd),
                    .init(color: .white.opacity(0.08), location: 0.5),
                    .init(color: .white.opacity(0.28), location: 1),
                ]), startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            }
        }
        .allowsHitTesting(false)
    }
}
