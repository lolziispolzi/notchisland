import Foundation
import IOKit.ps

struct BatteryInfo: Equatable {
    let percent: Int
    let isCharging: Bool
    let isPluggedIn: Bool

    /// Reads the internal battery via IOKit. Returns nil on Macs without a battery.
    static func current() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            return BatteryInfo(
                percent: max > 0 ? current * 100 / max : 0,
                isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }
        return nil
    }

    var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var isLow: Bool { percent <= 20 && !isCharging }
}

/// Publishes battery state. Updates come from IOKit power-source notifications, not polling.
@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var info: BatteryInfo?

    /// Called when a power adapter is connected.
    var onPluggedIn: (() -> Void)?

    private var runLoopSource: CFRunLoopSource?

    init() {
        info = BatteryInfo.current()

        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.refresh() }
        }, context)?.takeRetainedValue()

        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }
    }

    func refresh() {
        let old = info
        info = BatteryInfo.current()
        if let old, let new = info, !old.isPluggedIn, new.isPluggedIn {
            onPluggedIn?()
        }
    }
}
