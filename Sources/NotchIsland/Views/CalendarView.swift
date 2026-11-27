import SwiftUI

struct CalendarView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings
    @State private var isAdding = false

    private var calendar: CalendarService { vm.calendar }

    var body: some View {
        switch calendar.access {
        case .unavailable:
            WidgetMessage(symbol: "calendar.badge.exclamationmark",
                          title: "Calendar needs the app bundle",
                          message: "Run scripts/run-app.sh instead of swift run to use Calendar.")
        case .notDetermined:
            WidgetMessage(symbol: "calendar",
                          title: "See your upcoming events",
                          message: "NotchIsland reads and adds events in your calendars.",
                          buttonTitle: "Allow Calendar Access",
                          action: { calendar.requestAccess() })
        case .denied:
            WidgetMessage(symbol: "calendar.badge.exclamationmark",
                          title: "Calendar access is off",
                          message: "Turn on NotchIsland in Privacy & Security → Calendars.",
                          buttonTitle: "Open Privacy Settings",
                          action: { calendar.openPrivacySettings() })
        case .granted:
            if isAdding {
                AddEventForm(vm: vm, settings: settings) { isAdding = false }
            } else {
                agenda
            }
        }
    }

    private var agenda: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(DateText.string(Date(), template: "EEEE"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                Text(DateText.string(Date(), template: "d"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Spacer(minLength: 6)
                Button {
                    isAdding = true
                } label: {
                    SymbolLabel("New Event", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle())
            }
            .frame(width: 100, alignment: .leading)

            if calendar.events.isEmpty {
                Text("No upcoming events this week.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calendar.events) { event in
                            EventRow(event: event, calendar: calendar)
                        }
                    }
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let calendar: CalendarService

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(RelativeTime.eventLabel(start: event.start, isAllDay: event.isAllDay, now: Date()))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open Calendar") { calendar.openCalendarApp() }
            Divider()
            Button("Delete Event") { calendar.deleteEvent(id: event.id) }
        }
    }
}

/// Quick event entry inside the island. The panel takes the keyboard while it shows.
private struct AddEventForm: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings
    let onDone: () -> Void

    @State private var title = ""
    @State private var start = AddEventForm.nextHour()
    @State private var duration = 60
    @State private var alert = 10
    @State private var error: String?

    private static let durations = [15, 30, 45, 60, 90, 120]
    private static let alerts = [0, 5, 10, 15, 30, 60]

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Event title", text: $title, onCommit: save)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            HStack(spacing: 10) {
                DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(FieldDatePickerStyle())

                Picker("Duration", selection: $duration) {
                    ForEach(Self.durations, id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) min" : "\(Double(minutes) / 60, specifier: "%g") hr").tag(minutes)
                    }
                }
                .labelsHidden()
                .frame(width: 90)

                Picker("Alert", selection: $alert) {
                    ForEach(Self.alerts, id: \.self) { minutes in
                        Text(minutes == 0 ? "No alert" : "Alert \(minutes) min before").tag(minutes)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }

            HStack {
                if let error {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
                Spacer()
                Button("Cancel", action: cancel)
                    .compatCancelAction()
                Button("Add Event", action: save)
                    .compatDefaultAction()
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .controlSize(.small)
        .onAppear {
            alert = settings.newEventAlertMinutes
            vm.wantsKeyboard = true
        }
        .onDisappear { vm.wantsKeyboard = false }
        .onExitCommand(perform: cancel)
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        do {
            try vm.calendar.addEvent(title: trimmedTitle, start: start, durationMinutes: duration, alertMinutes: alert)
            onDone()
        } catch {
            self.error = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func cancel() {
        onDone()
    }

    nonisolated static func nextHour(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? now
    }
}
