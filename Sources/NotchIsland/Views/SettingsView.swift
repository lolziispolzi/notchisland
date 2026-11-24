import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                if let message = launchAtLogin.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Picker("Show on", selection: $settings.displayChoice) {
                    ForEach(DisplayChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
            }

            Section("Behavior") {
                Toggle("Open on hover", isOn: $settings.openOnHover)
                if settings.openOnHover {
                    LabeledContent("Hover delay") {
                        HStack {
                            Slider(value: $settings.hoverDelay, in: 0...1, step: 0.05)
                            Text(String(format: "%.2fs", settings.hoverDelay))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                } else {
                    Text("Click the notch to open the island.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
            }

            Section("Widgets") {
                Toggle("Now playing", isOn: $settings.showNowPlaying)
                Toggle("Live activities while closed", isOn: $settings.showLiveActivities)
                Toggle("Battery", isOn: $settings.showBattery)
                Toggle("File shelf", isOn: $settings.showShelf)
            }

            Section("About") {
                LabeledContent("Version", value: Self.version)
                Text("Now playing needs permission to control Music or Spotify. macOS asks the first time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 580)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}
