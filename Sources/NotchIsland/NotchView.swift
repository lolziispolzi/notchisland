import SwiftUI

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel

    private var topRadius: CGFloat { vm.isOpen ? NotchGeometry.maxTopRadius : 6 }
    private var bottomRadius: CGFloat { vm.isOpen ? 32 : 10 }
    private var bodySize: CGSize { vm.isOpen ? NotchGeometry.openSize : vm.geometry.closedSize }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(Color.black)
                .frame(width: bodySize.width + topRadius * 2, height: bodySize.height)

            if vm.isOpen {
                ExpandedContent(vm: vm)
                    .padding(.top, vm.geometry.notchRect.height + 6)
                    .padding(.horizontal, topRadius + 24)
                    .padding(.bottom, 20)
                    .frame(width: bodySize.width + topRadius * 2,
                           height: bodySize.height,
                           alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: vm.isOpen)
        .preferredColorScheme(.dark)
    }
}

/// What shows inside the island when it is open. Add widgets here.
struct ExpandedContent: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        HStack(alignment: .top) {
            ClockWidget()
            Spacer()
            if let battery = vm.battery {
                BatteryWidget(info: battery)
            }
        }
        .foregroundStyle(.white)
    }
}
