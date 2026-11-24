import SwiftUI

/// The bar that slides in under the island when you press the customize button.
/// Show, hide and reorder widgets, and change the island size, without leaving the notch.
struct CustomizeBar: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(settings.widgetOrder) { widget in
                        WidgetChip(widget: widget, settings: settings)
                    }
                }
            }

            HStack(spacing: 12) {
                Picker("Size", selection: $settings.islandSize) {
                    ForEach(IslandSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)

                Toggle("Live activities", isOn: $settings.showLiveActivities)
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Spacer(minLength: 0)

                Button("More…") { vm.openSettings() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                Button("Done") { vm.isEditing = false }
                    .buttonStyle(PillButtonStyle())
            }
            .font(.system(size: 11, weight: .medium))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

/// One widget in the customize bar: arrows move it, the middle toggles it.
struct WidgetChip: View {
    let widget: WidgetKind
    @ObservedObject var settings: AppSettings

    private var isVisible: Bool { settings.isVisible(widget) }
    private var index: Int { settings.widgetOrder.firstIndex(of: widget) ?? 0 }

    var body: some View {
        HStack(spacing: 3) {
            arrow("chevron.left", offset: -1)
                .disabled(index == 0)

            Button {
                settings.setVisible(widget, !isVisible)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: widget.symbol)
                        .font(.system(size: 10))
                    Text(widget.shortTitle)
                        .font(.system(size: 10, weight: .semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isVisible ? "Hide \(widget.title)" : "Show \(widget.title)")

            arrow("chevron.right", offset: 1)
                .disabled(index == settings.widgetOrder.count - 1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(isVisible ? 0.18 : 0.04)))
        .opacity(isVisible ? 1 : 0.5)
    }

    private func arrow(_ symbol: String, offset: Int) -> some View {
        Button {
            settings.move(widget, by: offset)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 10, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
