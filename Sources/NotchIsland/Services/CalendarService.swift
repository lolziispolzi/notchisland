import AppKit
import Combine
import EventKit
import SwiftUI

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?
}

/// Reads and creates calendar events with EventKit, and raises a heads-up
/// next to the notch shortly before each event starts.
@MainActor
final class CalendarService: ObservableObject {
    enum Access: Equatable {
        case notDetermined
        case granted
        case denied
        /// Running under `swift run`: no Info.plist, so no permission prompt is possible.
        case unavailable
    }

    @Published private(set) var access: Access
    /// Events that have not ended yet, from today through the next 7 days.
    @Published private(set) var events: [CalendarEvent] = []
    /// The next event, while it is inside the heads-up window.
    @Published private(set) var headsUp: CalendarEvent?

    private let store = EKEventStore()
    private let settings: AppSettings
    private var observers: [NSObjectProtocol] = []
    private var headsUpWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
        access = Self.currentAccess()

        observers.append(NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })

        // Timers do not fire during sleep, so re-check on wake.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })

        settings.$eventHeadsUpMinutes
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleHeadsUp() }
            .store(in: &cancellables)

        reload()
    }

    static func currentAccess() -> Access {
        guard AppEnvironment.isBundled else { return .unavailable }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined { return .notDetermined }
        if #available(macOS 14, *) {
            return status == .fullAccess ? .granted : .denied
        }
        return status == .authorized ? .granted : .denied
    }

    func requestAccess() {
        guard AppEnvironment.isBundled else { return }
        NSApp.activateCompat()
        Task {
            if #available(macOS 14, *) {
                _ = try? await store.requestFullAccessToEvents()
            } else {
                _ = try? await store.requestAccess(to: .event)
            }
            access = Self.currentAccess()
            reload()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    func reload() {
        access = Self.currentAccess()
        guard access == .granted else {
            events = []
            headsUp = nil
            return
        }

        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        guard let end = Calendar.current.date(byAdding: .day, value: 8, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(30)
            .map { event in
                CalendarEvent(id: event.eventIdentifier ?? UUID().uuidString,
                              title: event.title ?? "Untitled",
                              start: event.startDate,
                              end: event.endDate,
                              isAllDay: event.isAllDay,
                              color: Color(event.calendar?.color ?? .systemBlue),
                              location: event.location)
            }
        scheduleHeadsUp()
    }

    /// Saves a new event to the default calendar. The alarm makes macOS Calendar
    /// notify the user, on this Mac and on synced devices.
    func addEvent(title: String, start: Date, durationMinutes: Int, alertMinutes: Int) throws {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(max(durationMinutes, 5) * 60))
        event.calendar = store.defaultCalendarForNewEvents
        if alertMinutes > 0 {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alertMinutes * 60)))
        }
        try store.save(event, span: .thisEvent, commit: true)
        reload()
    }

    func deleteEvent(id: String) {
        guard let event = store.event(withIdentifier: id) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
        reload()
    }

    // MARK: - Heads-up

    private func scheduleHeadsUp() {
        headsUpWork?.cancel()
        headsUpWork = nil

        let lead = TimeInterval(settings.eventHeadsUpMinutes * 60)
        guard lead > 0, access == .granted else {
            headsUp = nil
            return
        }

        let now = Date()
        if let current = Self.headsUpEvent(in: events, now: now, lead: lead) {
            headsUp = current
            // Clear it when the event starts, then look for the next one.
            scheduleCheck(after: current.start.timeIntervalSince(now))
            return
        }

        headsUp = nil
        if let next = events.first(where: { !$0.isAllDay && $0.start > now }) {
            scheduleCheck(after: next.start.addingTimeInterval(-lead).timeIntervalSince(now))
        }
    }

    private func scheduleCheck(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.scheduleHeadsUp() }
        }
        headsUpWork = work
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(delay, 1), execute: work)
    }

    /// The first timed event that starts within `lead` seconds from `now`.
    nonisolated static func headsUpEvent(in events: [CalendarEvent], now: Date, lead: TimeInterval) -> CalendarEvent? {
        events.first { !$0.isAllDay && $0.start > now && $0.start.timeIntervalSince(now) <= lead }
    }
}

enum RelativeTime {
    /// "now", "in 8m", "in 2h".
    static func countdown(to date: Date, from now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes)m" }
        return "in \(minutes / 60)h"
    }

    /// "Today · 3:00 PM", "Tomorrow · All day", "Thu · 9:30 AM".
    static func eventLabel(start: Date, isAllDay: Bool, now: Date, calendar: Calendar = .current) -> String {
        let day: String
        if calendar.isDate(start, inSameDayAs: now) {
            day = "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(start, inSameDayAs: tomorrow) {
            day = "Tomorrow"
        } else {
            day = DateText.string(start, template: "EEE")
        }
        let time = isAllDay ? "All day" : DateText.string(start, date: .none, time: .short)
        return "\(day) · \(time)"
    }
}
