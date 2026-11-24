import SwiftUI
import UniformTypeIdentifiers

/// Root view. Draws the black island and switches between closed, live-activity and open states.
struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var battery: BatteryService
    @ObservedObject var shelf: ShelfStore

    private var activity: ClosedActivity { vm.isOpen ? .none : vm.closedActivity }
    private var topRadius: CGFloat { vm.isOpen ? NotchGeometry.maxTopRadius : 6 }
    private var bottomRadius: CGFloat { vm.isOpen ? 32 : 10 }

    private var size: CGSize {
        if vm.isOpen { return NotchGeometry.openSize }
        let notch = vm.geometry.notchRect.size
        return CGSize(width: notch.width + vm.closedExtraWidth, height: notch.height)
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(Color.black)
                .frame(width: size.width + topRadius * 2, height: size.height)

            if vm.isOpen {
                OpenView(vm: vm, settings: settings, nowPlaying: nowPlaying, battery: battery, shelf: shelf)
                    .frame(width: size.width + topRadius * 2, height: size.height, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            } else if activity != .none {
                ClosedActivityView(activity: activity,
                                   notchWidth: vm.geometry.notchRect.width,
                                   nowPlaying: nowPlaying,
                                   battery: battery)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [UTType.fileURL], isTargeted: $vm.isDropTargeted) { providers in
            guard settings.showShelf else { return false }
            shelf.add(providers)
            vm.tab = .shelf
            return true
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: vm.isOpen)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: activity)
        .preferredColorScheme(.dark)
    }
}

/// Contents of the expanded island: header bar plus the selected tab.
struct OpenView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var battery: BatteryService
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        VStack(spacing: 10) {
            HeaderBar(vm: vm, settings: settings, battery: battery, notchWidth: vm.geometry.notchRect.width)
                .frame(height: vm.geometry.notchRect.height)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, NotchGeometry.maxTopRadius + 18)
        .padding(.bottom, 16)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var content: some View {
        if vm.tab == .shelf, settings.showShelf {
            ShelfView(shelf: shelf, isTargeted: vm.isDropTargeted)
        } else {
            HomeView(settings: settings, nowPlaying: nowPlaying)
        }
    }
}

/// Row beside the notch: tabs on the left, battery and settings on the right.
struct HeaderBar: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var battery: BatteryService
    let notchWidth: CGFloat

    private var tabs: [NotchTab] { settings.showShelf ? NotchTab.allCases : [.home] }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(tabs, id: \.self) { tab in
                    Button {
                        vm.tab = tab
                    } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 22)
                            .background(Capsule().fill(Color.white.opacity(vm.tab == tab ? 0.18 : 0)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }

            Spacer(minLength: notchWidth + 12)

            HStack(spacing: 10) {
                if settings.showBattery, let info = battery.info {
                    BatteryBadge(info: info)
                }
                Button {
                    vm.openSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
    }
}

struct HomeView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var nowPlaying: NowPlayingService

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if settings.showNowPlaying {
                NowPlayingView(nowPlaying: nowPlaying)
            }
            Spacer(minLength: 0)
            ClockView()
        }
    }
}
