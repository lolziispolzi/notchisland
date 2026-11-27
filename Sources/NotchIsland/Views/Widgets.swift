import SwiftUI

struct ClockView: View {
    var body: some View {
        // TimelineView only exists while the island is open, so there is no idle timer.
        Ticker(every: 1) { context in
            VStack(alignment: .trailing, spacing: 2) {
                Text(DateText.string(context.date, template: "jmm"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .compatMonospacedDigit()
                Text(DateText.string(context.date, template: "EEEEMMMd"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
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
                .compatMonospacedDigit()
            SymbolImage(info.symbolName)
                .font(.system(size: 14))
                .foregroundColor(info.isLow ? Color.red : (info.isCharging ? Color.green : Color.white))
        }
    }
}
