import SwiftUI

struct ClockView: View {
    var body: some View {
        // TimelineView only exists while the island is open, so there is no idle timer.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .trailing, spacing: 2) {
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

struct BatteryBadge: View {
    let info: BatteryInfo

    var body: some View {
        HStack(spacing: 4) {
            Text("\(info.percent)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Image(systemName: info.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(info.isLow ? Color.red : (info.isCharging ? Color.green : Color.white))
        }
    }
}
