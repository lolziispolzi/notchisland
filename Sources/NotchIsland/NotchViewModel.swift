import SwiftUI

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var geometry: NotchGeometry
    @Published var battery: BatteryInfo?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    /// Called on open, so nothing polls while the island is closed.
    func refreshWidgets() {
        battery = BatteryInfo.current()
    }
}
