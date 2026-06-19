import EventKit
import Foundation

struct CalendarEvent {
    let id: String
    let title: String
    let startDate: Date
}

final class CalendarAlertManager {
    static let leadMinutes: TimeInterval = 10

    private let eventStore = EKEventStore()
    private var pollTimer: Timer?
    private var alertedKeys = Set<String>()
    private var hasAccess = false
    private var isRequestingAccess = false
    private var lastErrorMessage: String?

    var onCalendarAlert: ((String) -> Void)?
    var onAccessChanged: ((Bool) -> Void)?

    var isConnected: Bool { hasAccess }

    var statusMessage: String {
        if hasAccess {
            return "Apple Calendar connected — Jazz alerts 10 min before meetings."
        }
        if isRequestingAccess {
            return "Waiting for calendar access…"
        }
        switch Self.authorizationStatus {
        case .denied, .restricted, .writeOnly:
            return "Calendar access denied. Enable it in System Settings → Privacy & Security → Calendars."
        default:
            break
        }
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            return lastErrorMessage
        }
        return "Connect Apple Calendar so Jazz can alert you 10 min before calls."
    }

    func start() {
        hasAccess = Self.hasCalendarAccess
        onAccessChanged?(hasAccess)
        if hasAccess {
            startPolling()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func requestAccess(completion: ((Bool) -> Void)? = nil) {
        if Self.hasCalendarAccess {
            hasAccess = true
            lastErrorMessage = nil
            startPolling()
            onAccessChanged?(true)
            completion?(true)
            return
        }

        isRequestingAccess = true
        lastErrorMessage = nil
        onAccessChanged?(false)

        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.finishAccessRequest(granted: granted, error: error, completion: completion)
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.finishAccessRequest(granted: granted, error: error, completion: completion)
                }
            }
        }
    }

    func disconnect() {
        hasAccess = false
        lastErrorMessage = nil
        stop()
        onAccessChanged?(false)
    }

    private func finishAccessRequest(granted: Bool, error: Error?, completion: ((Bool) -> Void)?) {
        isRequestingAccess = false
        if let error {
            lastErrorMessage = error.localizedDescription
        }
        hasAccess = granted && Self.hasCalendarAccess
        if hasAccess {
            lastErrorMessage = nil
            startPolling()
        } else if lastErrorMessage == nil {
            lastErrorMessage = "Calendar access was not granted."
        }
        onAccessChanged?(hasAccess)
        completion?(hasAccess)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        checkUpcomingEvents()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkUpcomingEvents()
        }
    }

    private func checkUpcomingEvents() {
        guard hasAccess, Self.hasCalendarAccess else {
            hasAccess = false
            onAccessChanged?(false)
            stop()
            return
        }

        let now = Date()
        guard let horizon = Calendar.current.date(byAdding: .hour, value: 24, to: now) else { return }

        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: now, end: horizon, calendars: calendars)
        let events = eventStore.events(matching: predicate).compactMap { event -> CalendarEvent? in
            guard !event.isAllDay, let start = event.startDate else { return nil }
            let title = (event.title ?? "Meeting").trimmingCharacters(in: .whitespacesAndNewlines)
            let id = event.eventIdentifier ?? UUID().uuidString
            return CalendarEvent(id: id, title: title, startDate: start)
        }

        lastErrorMessage = nil
        process(events: events, relativeTo: now)
    }

    private func process(events: [CalendarEvent], relativeTo now: Date) {
        let lead = Self.leadMinutes * 60
        let window: TimeInterval = 90

        for event in events where event.startDate > now {
            let secondsUntilStart = event.startDate.timeIntervalSince(now)
            let secondsUntilAlert = secondsUntilStart - lead
            guard secondsUntilAlert >= -window / 2, secondsUntilAlert <= window / 2 else { continue }

            let key = "\(event.id)|\(event.startDate.timeIntervalSince1970)"
            guard !alertedKeys.contains(key) else { continue }

            alertedKeys.insert(key)
            onCalendarAlert?(event.title)
        }

        pruneAlertedKeys()
    }

    private func pruneAlertedKeys() {
        guard alertedKeys.count > 200 else { return }
        alertedKeys = Set(alertedKeys.suffix(100))
    }

    private static var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    private static var hasCalendarAccess: Bool {
        switch authorizationStatus {
        case .fullAccess, .authorized:
            return true
        default:
            return false
        }
    }
}
