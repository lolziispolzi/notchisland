import SwiftUI
import IOKit.ps

// MARK: - Clock

struct ClockWidget: View {
    var body: some View {
        // TimelineView only exists while the island is open, so no idle timer.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Battery

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
}

struct BatteryWidget: View {
    let info: BatteryInfo

    var body: some View {
        HStack(spacing: 6) {
            Text("\(info.percent)%")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Image(systemName: info.symbolName)
                .font(.system(size: 18))
                .foregroundStyle(info.percent <= 20 && !info.isCharging ? .red : .white)
        }
    }
}
