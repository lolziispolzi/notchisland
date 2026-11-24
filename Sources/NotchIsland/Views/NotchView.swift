import SwiftUI
import UniformTypeIdentifiers

/// Root view. Draws the black island and switches between closed, live-activity and open states.
struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings

    private var activity: ClosedActivity { vm.isOpen ? .none : vm.closedActivity }
    private var topRadius: CGFloat { vm.isOpen ? NotchGeometry.maxTopRadius : 6 }
    private var bottomRadius: CGFloat { vm.isOpen ? 32 : 10 }

    private var size: CGSize {
        if vm.isOpen { return vm.openSize }
        let notch = vm.geometry.notchRect.size
        return CGSize(width: notch.width + vm.closedExtraWidth, height: notch.height)
    }

    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(Color.black)
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
        .onDrop(of: [UTType.fileURL], isTargeted: $vm.isDropTargeted) { providers in
            guard settings.isVisible(.drop) else { return false }
            vm.shelf.add(providers)
            vm.tab = .drop
            return true
        }
        .animation(spring, value: vm.isOpen)
        .animation(spring, value: activity)
        .animation(spring, value: vm.isEditing)
        .animation(spring, value: settings.islandSize)
        .preferredColorScheme(.dark)
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
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.tab {
        case .media: MediaView(vm: vm)
        case .weather: WeatherView(vm: vm)
        case .calendar: CalendarView(vm: vm, settings: settings)
        case .sports: SportsView(vm: vm)
        case .drop: DropView(vm: vm)
        }
    }
}

/// Row beside the notch: widget tabs on the left; battery, customize and settings on the right.
struct HeaderBar: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(settings.visibleWidgets) { widget in
                    HeaderButton(symbol: widget.symbol, isSelected: vm.tab == widget, help: widget.title) {
                        vm.tab = widget
                    }
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
                HeaderButton(symbol: "gearshape.fill", isSelected: false, help: "Settings") {
                    vm.openSettings()
                }
            }
        }
    }
}

struct HeaderButton: View {
    let symbol: String
    let isSelected: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(Capsule().fill(Color.white.opacity(isSelected ? 0.18 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Now playing on the left, clock on the right.
struct MediaView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            NowPlayingView(nowPlaying: vm.nowPlaying)
            Spacer(minLength: 0)
            ClockView()
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
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.5))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
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
